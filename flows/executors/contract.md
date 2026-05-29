# Executor Contract

**Status:** Draft v1
**Date:** 2026-04-29
**Pairs with:** [Dispatcher Contract](../dispatcher/contract.md)

This document specifies the contract every specialised executor flow must satisfy. There are six executors, one per service principal:

| Executor | Service Principal | Subscription | jobType prefixes |
|---|---|---|---|
| Identity & Lifecycle | SP-IT-Identity | `sub-identity` | `identity.*` |
| Group Membership | SP-IT-Groups | `sub-groups` | `groups.*` |
| Licensing | SP-IT-Licensing | `sub-licensing` | `licensing.*` |
| Exchange / Mail | SP-IT-Exchange | `sub-exchange` | `exchange.*` |
| SharePoint / OneDrive | SP-IT-SharePoint | `sub-sharepoint` | `sharepoint.*` |
| Teams / Endpoint | SP-IT-Teams | `sub-teams` | `teams.*`, `endpoint.*` |

Each executor is **one Power Automate flow per service principal**, with an internal switch on the granular action. Six flows total, not 25. Per [ADR 0001](../../decisions/0001-dispatcher-host.md).

---

## 1. Trigger

**Trigger:** "When a message is received in a topic subscription (peek-lock)" — Service Bus connector.

- **Topic:** `provisioning-jobs`
- **Subscription:** as per table above
- **Receive mode:** Peek-Lock (NOT auto-complete — executor must explicitly complete or abandon)
- **Concurrency control:** ON
- **Maximum concurrent runs:** start at 5, tunable per environment via flow setting

---

## 2. Input message shape (from Service Bus)

```json
{
  "jobId": "PJ-01J7F9...",
  "jobType": "identity.resetPassword",
  "target": { "type": "user", "upn": "alice@contoso.com" },
  "args": { "forceChangeOnNextLogin": true, "notifyUser": true },
  "ticketId": "INC0010234",
  "ritmId": null,
  "callerUpn": "bob@contoso.com",
  "correlationId": "01J7F9...ULID",
  "jwtJti": "01J7F9...ULID"
}
```

**Brokered properties to read:**

- `MessageId` — Service Bus's own ID (matches `jobId`)
- `CorrelationId` — same as body `correlationId`
- `SessionId` — `ticketId` (used for FIFO per ticket)
- `Subject` / `Label` — the `jobType` (used for routing within the executor's switch).
  Azure Service Bus SQL filters evaluate this brokered-message property as `sys.Label`.
- `DeliveryCount` — read this; if > 1, this is a retry, log accordingly

---

## 3. Action sequence (per executor)

```
1.  Service Bus: receive message (peek-lock)
2.  Update Provisioning Jobs SP item (jobId): Status = "InProgress", StartedAt = now
3.  Emit executor.started to App Insights
4.  Switch on jobType (the granular action)
        case "identity.resetPassword":
              → call Graph: POST /users/{upn}/authentication/passwordMethods/.../resetPassword
        case "identity.disableUser":
              → call Graph: PATCH /users/{upn} { accountEnabled: false }
        case "identity.createUser":
              → call Graph: POST /users
        ...
5.  Capture Graph response: status, body, headers (especially x-ms-correlation-id)
6.  On Graph success:
        → Update Provisioning Jobs: Status = "Succeeded", ResultJSON, CompletedAt
        → Update IdempotencyKeys table (PartitionKey=jobType, RowKey=idempotencyKey):
              Status = "Succeeded", ResultRef = SP item URL
        → Emit executor.succeeded to App Insights
        → Service Bus: Complete the message
7.  On Graph 4xx (permanent failure — bad input, target not found, no permission):
        → Update Provisioning Jobs: Status = "Failed", ErrorJSON
        → Update IdempotencyKeys: Status = "Failed"
        → Emit executor.failed to App Insights
        → Service Bus: Dead-letter the message (do NOT abandon — abandon retries; this is permanent)
8.  On Graph 429 (throttled):
        → Read Retry-After header
        → Service Bus: Renew Lock or Defer the message
        → Delay (Retry-After seconds, capped at 5 min)
        → Retry the Graph call (up to 3 attempts within the same flow run)
        → If still throttled after 3: abandon the message (Service Bus retries, DeliveryCount increments)
9.  On Graph 5xx / network failure:
        → Service Bus: Abandon the message (will retry up to MaxDeliveryCount=5)
        → Emit executor.transient_error to App Insights
10. On internal flow error (try/catch):
        → Service Bus: Abandon (retry)
        → Emit executor.error
```

---

## 4. Status values (Provisioning Jobs SP list)

| Status | Set by | Meaning |
|---|---|---|
| `Queued` | Dispatcher | In Service Bus, not yet picked up |
| `InProgress` | Executor (step 2) | Picked up, Graph call in flight |
| `Succeeded` | Executor (step 6) | Graph confirmed success |
| `Failed` | Executor (step 7) | Permanent failure — will not auto-retry |
| `Compensated` | Compensation flow | This job was reverted by a compensating action |
| `DeadLettered` | DLQ monitor | Exceeded delivery count or explicit dead-letter |
| `Cancelled` | Ops console | Manually cancelled before execution |

State machine:

```
Queued → InProgress → Succeeded
                   → Failed
                   → DeadLettered
Succeeded → Compensated  (only via paired compensation job)
```

---

## 5. Output shape (audit row)

The Provisioning Jobs SP list row is the searchable audit record. App Insights is the durable audit log.

**Provisioning Jobs columns relevant to executor:**

| Column | Set by | Notes |
|---|---|---|
| `JobId` (Title) | Dispatcher | `PJ-{ULID}` |
| `JobType` | Dispatcher | |
| `TicketId` | Dispatcher | Lookup to Tickets list |
| `Status` | Both | See above |
| `StartedAt` | Executor | UTC datetime |
| `CompletedAt` | Executor | UTC datetime |
| `DurationMs` | Executor | `CompletedAt - StartedAt` |
| `ServicePrincipal` | Executor | The SP that did the write (e.g., `SP-IT-Identity`) |
| `GraphRequestId` | Executor | `x-ms-correlation-id` header from Graph |
| `ResultJSON` | Executor | Graph response body (truncated to 4000 chars; full body in App Insights) |
| `ErrorJSON` | Executor | On failure: `{ code, message, innerError }` |
| `RetryCount` | Executor | `DeliveryCount` from Service Bus (0 = first attempt) |
| `CompensationJobId` | Compensation flow | Lookup to the job that compensated this one |
| `IdempotencyKey` | Dispatcher | Mirror for searchability |
| `CallerUpn` | Dispatcher | Who originated |
| `CorrelationId` | Dispatcher | Same value across the whole pipeline |

---

## 6. App Insights events (executor side)

Standard custom dimensions on every event: `correlationId`, `ticketId`, `jobId`, `jobType`, `servicePrincipal`, `environment`.

| Event name | When emitted | Additional dimensions |
|---|---|---|
| `executor.started` | Step 3 | `deliveryCount`, `enqueuedTime`, `dequeueLatencyMs` |
| `executor.graph_call` | Each Graph call | `endpoint`, `httpStatus`, `graphRequestId`, `durationMs` |
| `executor.succeeded` | Step 6 | `totalDurationMs` |
| `executor.failed` | Step 7 | `graphErrorCode`, `graphErrorMessage`, `httpStatus` |
| `executor.transient_error` | Step 9 | `httpStatus`, `errorMessage` |
| `executor.throttled` | Step 8 | `retryAfterSec`, `attempt` |
| `executor.error` | Step 10 | `errorMessage`, `errorStep` |
| `executor.compensated` | Compensation completed | `originalJobId` |

---

## 7. Service Principal scope and identity

Each executor flow runs under exactly one service principal. The SP is wired via a connection that the flow author *does not own personally* — the connection is owned by a shared service account in the IT-Automation team to survive staff turnover.

**Required Graph application permissions per SP** (initial scope; tighten as job types are pruned):

| SP | Permissions |
|---|---|
| SP-IT-Identity | `User.ReadWrite.All`, `Directory.AccessAsUser.All`, `UserAuthenticationMethod.ReadWrite.All` |
| SP-IT-Groups | `Group.ReadWrite.All`, `GroupMember.ReadWrite.All` |
| SP-IT-Licensing | `Directory.ReadWrite.All`, `Organization.Read.All` |
| SP-IT-Exchange | Exchange Online: `Mail.ReadWrite`, `MailboxSettings.ReadWrite` (delegated where required), Graph: `User.Read.All` |
| SP-IT-SharePoint | `Sites.FullControl.All` *scoped to the IT-managed sites only via Sites.Selected pattern* |
| SP-IT-Teams | `TeamMember.ReadWrite.All`, `Channel.Create`, `DeviceManagementManagedDevices.ReadWrite.All` |

**Cert rotation:** every 90 days. Owner per SP is open question #2 from the design memo.

---

## 8. Compensation hooks

Each executor switches on `jobType`. A subset of job types are **compensable** — the `JobTypes` registry has a `CompensationJobType` column listing the inverse.

**Compensation pattern:**

- Compensation is **never automatic**. It is triggered by the saga flow (separate, future ADR 0002) or by the ops console.
- A compensation job is itself a normal job — it goes through approval, dispatcher, queue, executor. Same audit, same traceability.
- The compensation job's body has `compensatesJobId` field; the executor sets `CompensationJobId` on the original job's row to mark it `Compensated`.

Example compensation pairs:

| Original | Compensation |
|---|---|
| `identity.createUser` | `identity.disableUser` (cannot truly delete in 30 days; soft-delete) |
| `groups.addMember` | `groups.removeMember` |
| `licensing.assign` | `licensing.revoke` |
| `identity.resetPassword` | (not compensable — by design) |
| `sharepoint.grantAccess` | `sharepoint.revokeAccess` |

---

## 9. Concurrency and ordering

- **Per-ticket FIFO:** Service Bus sessions with `sessionId = ticketId`. An executor processes messages for the same ticket strictly in order; messages for different tickets in parallel.
- **Per-target safety:** Two jobs targeting the same `target.upn` may run concurrently across different executors (e.g., create user in Identity, assign license in Licensing). This is intentional. Where ordering matters across executors, the workflow encoding it must use a single ticket and chain via approvals.
- **Max concurrent runs per executor:** 5 (initial). Tune up only after Graph throttling telemetry shows headroom.

---

## 10. Failure recovery

| Scenario | Recovery |
|---|---|
| Executor flow run crashes mid-Graph-call | Service Bus message lock expires (5 min), message redelivered, executor retries. Idempotency key in Table Storage prevents double-write because the executor reads `IdempotencyKeys.Status` first and skips if already `Succeeded`. |
| Graph call succeeded but SP audit write failed | App Insights still has the `executor.graph_call` event. Reconciliation flow (daily) compares App Insights successful Graph calls against Provisioning Jobs `Succeeded` rows; gaps are backfilled. |
| Service Bus subscription is offline / queue stalled | DLQ monitor flow alerts in `#itsm-dlq-alerts`. Ops console offers re-drive. |
| Idempotency table rejects a "first" attempt because of a prior orphan | Compensation: scheduled flow scans `IdempotencyKeys` rows older than 5 min with no matching SP `Provisioning Jobs` row, deletes them. (Defensive — should be rare.) |

---

## 11. What an executor flow must NOT do

- **Must not** write to a target without first reading `IdempotencyKeys.Status` for its `(jobType, idempotencyKey)` and short-circuiting on `Succeeded`.
- **Must not** auto-complete the Service Bus message at the trigger (peek-lock only — explicit complete/abandon/dead-letter).
- **Must not** call any Graph endpoint not declared in the SP's `RequiredScopes` for that `jobType` (registry-enforced).
- **Must not** execute a `jobType` outside its prefix table above (subscription filter prevents it, but defence-in-depth: assert at action 4's switch default).
- **Must not** retry on 4xx (permanent). Only on 429 and 5xx.
- **Must not** swallow errors. Any unhandled path = Service Bus abandon + App Insights `executor.error`.

---

## 12. Out of scope for this contract

- Compensation orchestration (the saga flow itself) — ADR 0002 planned.
- Per-`jobType` `args` schemas — live in the `JobTypes` SP list `InputSchema` column.
- Throttling adaptive tuning — phase 2.
- Long-running jobs (> 5 min lock) — none today; if introduced, requires `RenewLock` pattern.

---

## 13. Open items

1. **Sites.Selected for SP-IT-SharePoint.** Need the list of IT-managed site collections to scope. Catherine to confirm.
2. **Exchange permissions.** Some Exchange operations require RBAC role assignments, not just Graph permissions. The SP-IT-Exchange flow may need EXO PowerShell connector for a subset of actions.
3. **Cert rotation calendar.** Six SPs × 90-day rotation = 1 rotation every 15 days. Needs an owner and a reminder flow.
