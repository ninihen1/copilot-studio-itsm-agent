# Dispatcher Contract

**Status:** Draft v1 (production-grade target)
**Date:** 2026-04-29
**Pilot deployed:** 2026-05-01 — flow `00000000-0000-4000-8000-000000000033` in env `<env-id>`
**Host:** Power Automate HTTP-request-triggered flow (see [ADR 0001](../../decisions/0001-dispatcher-host.md))

This is the load-bearing artefact. The host is swappable; the contract is not. Any caller (Approval flow, future re-driver, ops console) and any executor flow must conform to this spec.

---

## ⚠ Pilot deviations from this contract (2026-05-01)

The deployed pilot dispatcher (`97a4c109-...`) implements a slim subset of this contract to prove the loop end-to-end without standing up the full Phase 2 Azure infra. **Read this before implementing any caller.**

| Section | Production contract | Pilot deployed |
|---|---|---|
| §1.1 Endpoint | `POST {DISPATCHER_BASE}/provisioning/jobs` with Bearer JWT + X-Idempotency-Key header | PA-managed trigger URL with SAS sig in querystring; idempotency key + JWT-equivalent in body |
| §1.2 Body | Caller-supplied: jobType, target, args, ticketId, callerUpn, correlationId | Reference-supplied: `pjId` (existing PJ row), idempotencyKey, callerUpn, approverUpn, approvalSessionId, jobType, correlationId. **Pilot dispatcher PATCHES an existing PJ row instead of CREATING one** — the agent's ProposeAction is responsible for creating the row in `Proposed`/`AwaitingApproval` state first |
| §1.3 JWT validation | Sig + iss + aud + exp + jti replay + jobType + targetHash + argsHash | NOT IMPLEMENTED — dispatcher trusts the SAS URL on its trigger |
| §3 step 6 (Idempotency) | Azure Table Storage `IdempotencyKeys` with `If-None-Match: *` | SP query: `Provisioning Jobs $filter=IdempotencyKey eq '...' and ID ne {pjId}`. Returns 200 idempotent on match. **Race-vulnerable** under truly-concurrent callers. |
| §3 step 7 (PJ row) | Dispatcher CREATES PJ row in `Queued` | Dispatcher PATCHES existing PJ row to `Dispatched` (skip Queued state) |
| §3 step 8 (Service Bus) | Publish to `provisioning-jobs` topic with subject/label = jobType, sessionId = ticketId | NOT IMPLEMENTED — executor polls PJ list directly |
| §3 step 9 (App Insights) | Emit `dispatcher.completed` to App Insights | NOT IMPLEMENTED — only PA run history + SP audit row |
| §5 Service Bus topology | Topic + 6 per-executor subscriptions with SQL filters | NOT IMPLEMENTED |
| §7 Kill switch | SP `Config!KillSwitch` checked on every request | ✅ implemented (Config row id=1) |
| §8 App Insights events | All 6 event types | NOT IMPLEMENTED |

### Pilot response shapes (verified)

- **202 Accepted**: `{ idempotent: false, pjId, jobId, jobType, status: "Dispatched", ticketId, correlationId, dispatchedAt, trackingUrl }`
- **200 Idempotent**: `{ idempotent: true, reason, originalPjId, originalJobId, originalStatus, trackingUrl }`
- **400 Bad Request** (jobType mismatch with PJ row): `{ error: "bad_request", field, reason, expected, received }`
- **409 Conflict** (PJ not in Proposed/AwaitingApproval): `{ error: "invalid_state", reason, currentState, pjId, jobId }`
- **503 Kill Switch**: `{ error: "kill_switch", reason, pjId }`

### Migration path from pilot to full contract

Per [ADR 0001](../../decisions/0001-dispatcher-host.md), the migration triggers are: first SOC 2 customer, sustained > 5,000 jobs/week, or multi-tenant deployment. Each Phase 2 hardening is independently addable:
1. **JWT** — write Approval flow, deploy `jwt-sign` + `jwt-validate` Functions, add validation as dispatcher step 4
2. **Azure Table idempotency** — replace `Check_Idempotency` SP query with HTTP call to Table Storage
3. **Service Bus** — add `Send_To_Topic` action after `Patch_PJ_To_Dispatched`; rewrite executor as Service Bus subscriber instead of SP poller
4. **App Insights** — add HTTP custom-event posts at `dispatcher.received` / `dispatcher.completed` / `dispatcher.rejected`

The dispatcher's contract surface to callers stays the same on items 2-4. Item 1 (JWT) is the only API-visible change.

---

## 1. Request

### 1.1 Endpoint

```
POST {DISPATCHER_BASE}/provisioning/jobs
Content-Type: application/json
Authorization: Bearer {approvalJwt}
X-Idempotency-Key: {string, ≤128 chars}
```

`{DISPATCHER_BASE}` is the Power Automate trigger URL stored in Key Vault. The trigger's SAS signature is the network-edge auth; the JWT is the application-layer auth and is the one that matters.

### 1.2 Body

```json
{
  "jobType": "identity.resetPassword",
  "target": {
    "type": "user",
    "upn": "alice@contoso.com"
  },
  "args": {
    "forceChangeOnNextLogin": true,
    "notifyUser": true
  },
  "ticketId": "INC0010234",
  "ritmId": null,
  "callerUpn": "bob@contoso.com",
  "correlationId": "01J7F9...ULID"
}
```

**Field rules:**

| Field | Required | Notes |
|---|---|---|
| `jobType` | Y | Must match `^[a-z]+\.[a-zA-Z]+$`. Registry of valid values lives in `JobTypes` SP list. |
| `target.type` | Y | `user` \| `group` \| `mailbox` \| `site` \| `device`. |
| `target.upn` / `target.id` | Y | UPN for user/mailbox; GUID for group/site/device. |
| `args` | Y | Object. Schema per `jobType` lives in `JobTypes` list (`InputSchema` JSON column). |
| `ticketId` | Y | Source ticket (audit linkage). |
| `ritmId` | N | RITM if request, else null. |
| `callerUpn` | Y | The human who originated. NOT the agent's identity. |
| `correlationId` | Y | ULID. Same value flows through approval → dispatcher → executor → audit row. |

### 1.3 JWT claims (`Authorization: Bearer …`)

Issued by the Approval flow on final approval. Validated by the dispatcher as its **first action**.

```json
{
  "iss": "https://approvals.itsm.contoso.com",
  "aud": "https://dispatcher.itsm.contoso.com",
  "sub": "INC0010234",
  "jti": "01J7F9...ULID",
  "iat": 1745928000,
  "exp": 1745931600,
  "jobType": "identity.resetPassword",
  "targetHash": "sha256:9f86d0...",
  "argsHash": "sha256:e3b0c4...",
  "approvers": [
    { "upn": "manager@contoso.com", "stage": "manager", "decidedAt": "2026-04-29T08:14:22Z" }
  ],
  "policyId": "AP-PWD-RESET-V1",
  "policyVersion": 3
}
```

**Validation rules (in order — fail fast):**

1. **Signature** verifies against the Approval engine's public key (cached from Key Vault, refreshed every 60 min).
2. **`iss`** = configured issuer URL. **`aud`** = configured dispatcher URL.
3. **`exp`** > now. **`iat`** ≤ now. Max age = 1 hour from `iat` (not just `exp`-honoured — defence in depth).
4. **`jti`** has not been seen before (look up in `JwtReplay` Azure Table; insert with TTL = `exp` + 5 min). Replay attempt → 401.
5. **`jobType`** matches body `jobType`.
6. **`targetHash`** = `sha256(canonical(body.target))`. Mismatch → 400.
7. **`argsHash`** = `sha256(canonical(body.args))`. Mismatch → 400.

`canonical()` = JCS (RFC 8785) JSON Canonicalization. Both sides must use the same library — pin the version.

Failures emit `dispatcher.rejected` to App Insights with reason code, then return the corresponding HTTP status. **No enqueue, no SP write.**

---

## 2. Response

### 2.1 Sync responses (no queueing happens)

| Code | Meaning | Body |
|---|---|---|
| 401 | JWT invalid / expired / replayed | `{ "error": "auth_failed", "reason": "..." }` |
| 400 | Body invalid / hash mismatch / unknown jobType | `{ "error": "bad_request", "field": "...", "reason": "..." }` |
| 403 | Approver lacked authority for this jobType (cross-check `policyId` allows these approvers) | `{ "error": "forbidden", "reason": "..." }` |
| 503 | Kill switch is ON | `{ "error": "kill_switch", "reason": "All dispatcher writes paused." }` |

### 2.2 Async response (job accepted)

| Code | Meaning | Body |
|---|---|---|
| 202 | Job accepted, queued for execution | See below |
| 200 | Idempotent replay — job already exists with this `X-Idempotency-Key` | Same body as 202, with `idempotent: true` |

```json
{
  "jobId": "PJ-01J7F9...",
  "status": "Queued",
  "jobType": "identity.resetPassword",
  "ticketId": "INC0010234",
  "correlationId": "01J7F9...ULID",
  "queuedAt": "2026-04-29T08:14:25Z",
  "trackingUrl": "{PROVISIONING_JOBS_LIST_URL}?id=PJ-01J7F9...",
  "idempotent": false
}
```

The dispatcher does **not** wait for execution. Callers poll `trackingUrl` (Provisioning Jobs SP list) or subscribe to a Service Bus completion topic if they need the result.

---

## 3. Dispatcher flow — action sequence

```
1.  HTTP request trigger (PA)
2.  Compose: validate body schema (jobType pattern, required fields)
        → on fail: emit dispatcher.rejected, return 400
3.  HTTP: fetch Approval public key from Key Vault (cached in flow's environment variable, refreshed hourly)
4.  Compose: validate JWT signature, claims, hashes
        → on fail: emit dispatcher.rejected, return 401/400
5.  Get item: KillSwitch from Config SP list
        → if ON: emit dispatcher.killed, return 503
6.  HTTP: Azure Table Storage — Insert IdempotencyKeys
        partition: jobType, row: X-Idempotency-Key
        If-None-Match: *
        → 409 (duplicate): fetch the existing row, return 200 idempotent replay
        → 201: continue
7.  Create item: Provisioning Jobs SP list — status "Queued", all metadata
8.  Send message: Service Bus topic "provisioning-jobs"
        subject/label: jobType
        message body: { jobId, jobType, target, args, ticketId, ritmId, callerUpn, correlationId, jwtJti }
        message properties:
          - correlationId (header)
          - sessionId = ticketId (FIFO per ticket)
        Time-to-live: 24h
        Lock duration: 5 min (executor must complete or extend)
9.  Emit dispatcher.completed to App Insights
        custom dimensions: jobId, jobType, ticketId, correlationId, idempotent=false, durationMs
10. Return 202 with body
```

**Failure modes between steps:**

- Step 6 succeeds, step 7 fails → idempotency key is reserved but no SP row. Compensation: scheduled flow scans `IdempotencyKeys` for rows older than 5 min with no matching SP row, deletes them.
- Step 7 succeeds, step 8 fails → SP row exists in "Queued" but never executes. Compensation: scheduled flow scans Provisioning Jobs for "Queued" rows older than 10 min, re-enqueues.
- Step 8 succeeds, step 9 fails → audit log missing the completion event. Acceptable; reconcile from Service Bus message logs.

---

## 4. Idempotency table schema

**Storage:** Azure Table Storage. Account in same region as Power Automate environment. Use a separate storage account from anything else (blast-radius isolation).

**Table:** `IdempotencyKeys`

| Column | Type | Notes |
|---|---|---|
| `PartitionKey` | string | `jobType` (e.g., `identity.resetPassword`). |
| `RowKey` | string | `X-Idempotency-Key` from the request. Caller-supplied. |
| `JobId` | string | The Provisioning Job ID this key resolved to. |
| `TicketId` | string | For audit cross-reference. |
| `CallerUpn` | string | Who submitted. |
| `CreatedAt` | datetime | Insert timestamp (UTC). |
| `Status` | string | Mirrors job status: `Queued` \| `InProgress` \| `Succeeded` \| `Failed` \| `Compensated`. Updated by executor. |
| `ResultRef` | string | Provisioning Job SP item URL. |
| `Timestamp` | datetime | Auto (Table Storage built-in). Used for TTL. |

**TTL:** 30 days. Idempotency window is operational, not eternal. After 30 days the same key may be reused (extremely rare; alert if it ever happens).

**Insert semantics:** `Insert Entity` with header `If-None-Match: *`. On 409 response, do `Get Entity` and return 200 idempotent replay using `JobId`/`Status`/`ResultRef`.

**Caller guidance for `X-Idempotency-Key`:** ULID per logical operation. The Approval flow generates it once per approval and includes it in the dispatch call. Re-drivers reuse it.

---

## 5. Service Bus topology

**Namespace:** `sb-itsm-{env}` (Standard tier minimum — Basic doesn't support topics).

### 5.1 Topic: `provisioning-jobs`

- Default TTL: 24 hours
- Max size: 5 GB
- Duplicate detection: ON (10-minute window) — defence in depth alongside Table Storage idempotency
- Partitioning: ON
- Sessions: ON (sessionId = ticketId, ensures FIFO per ticket)

### 5.2 Subscriptions (one per executor SP)

| Subscription | Filter (SQL filter on `sys.Label`) | Executor flow | Service Principal |
|---|---|---|---|
| `sub-identity` | `sys.Label LIKE 'identity.%'` | Executor: Identity & Lifecycle | SP-IT-Identity |
| `sub-groups` | `sys.Label LIKE 'groups.%'` | Executor: Group Membership | SP-IT-Groups |
| `sub-licensing` | `sys.Label LIKE 'licensing.%'` | Executor: Licensing | SP-IT-Licensing |
| `sub-exchange` | `sys.Label LIKE 'exchange.%'` | Executor: Exchange / Mail | SP-IT-Exchange |
| `sub-sharepoint` | `sys.Label LIKE 'sharepoint.%'` | Executor: SharePoint / OneDrive | SP-IT-SharePoint |
| `sub-teams` | `sys.Label LIKE 'teams.%' OR sys.Label LIKE 'endpoint.%'` | Executor: Teams / Endpoint | SP-IT-Teams |

Azure Service Bus SQL filters use `sys.Label` for the brokered-message label. Modern SDKs expose the same field as `Subject`; dispatcher send actions must set whichever field the connector exposes so that `sys.Label` receives the `jobType`.

### 5.3 Per-subscription settings

- Max delivery count: 5
- Lock duration: 5 minutes (executor must complete or call `Renew Lock`)
- Dead-letter queue: ON, captures messages that exceed delivery count or are explicitly dead-lettered
- `MaxConcurrentCalls` per executor flow: starts at 5, tunable per-environment

### 5.4 Dead-letter handling

A separate scheduled flow `dlq-monitor` (every 5 min):
1. Reads from each `*/$DeadLetterQueue`
2. Updates the matching Provisioning Job row to `Failed` with DLQ reason
3. Posts to `#itsm-dlq-alerts` Teams channel
4. Does NOT auto-retry. Re-drive is human-initiated via the ops console.

---

## 6. JobTypes registry

A SharePoint list, not hardcoded. New job types are added by appending a row.

**List:** `JobTypes`

| Column | Type | Notes |
|---|---|---|
| `JobType` (Title) | string | e.g., `identity.resetPassword`. Must match `^[a-z]+\.[a-zA-Z]+$`. |
| `Category` | choice | identity \| groups \| licensing \| exchange \| sharepoint \| teams \| endpoint |
| `RiskTier` | choice | low \| medium \| high — drives default Approval Policy |
| `DefaultPolicyId` | lookup → ApprovalPolicies | Default policy if catalogue item / category doesn't override |
| `InputSchema` | multiline (plain) | JSON Schema for `args` object |
| `RequiredScopes` | multiline (plain) | Graph permissions used (for SP cert review) |
| `CompensationJobType` | string | The job type that undoes this one (or empty for non-compensable) |
| `Status` | choice | active \| deprecated |
| `OwningTeam` | Person | Engineering owner |

The dispatcher loads this list at start-of-day into a flow variable; refreshed via `Trigger.Conditions` on item changes (or hourly fallback).

---

## 7. Kill switch

**Source of truth:** SharePoint list `Config`, item `KillSwitch`, column `Value` (`true`/`false`; the dispatcher compares `toLower(Value) == 'true'`).

**Verified live (2026-06-02):** the `Config` row stores `false` — correct format, kill OFF by default; setting it to `true` engages (every job returns 503 before any tenant change).

**Read frequency:** dispatcher checks on every request (cached in flow run; not cached across runs — this is the kill switch, must be live).

**Effect when ON:** Dispatcher returns 503 immediately after JWT validation. No enqueue, no SP write, no audit beyond `dispatcher.killed` event in App Insights with the JWT `jti`.

**Who can flip it:** Members of `IT-ITSM-Admins` SP group (item-level permissions on the Config item).

---

## 8. App Insights events

All events have these standard custom dimensions: `correlationId`, `ticketId`, `jobType`, `callerUpn`, `environment`.

| Event name | When emitted | Additional dimensions |
|---|---|---|
| `dispatcher.received` | Step 1 (request trigger fires) | `httpStatus=null`, `jwtJti`, `idempotencyKey` |
| `dispatcher.rejected` | Steps 2/4 fail | `reason`, `httpStatus` (400/401/403) |
| `dispatcher.killed` | Step 5 returns 503 | `httpStatus=503` |
| `dispatcher.idempotent_replay` | Step 6 returns 409, replay served | `httpStatus=200`, `originalJobId` |
| `dispatcher.completed` | Step 9 | `httpStatus=202`, `jobId`, `durationMs` |
| `dispatcher.error` | Any unhandled failure | `errorMessage`, `errorStep` |

Telemetry sink: `appi-itsm-{env}` Application Insights resource. Connection string in Key Vault, surfaced to PA via environment variable.

---

## 9. Out of scope for this contract

- Executor flow internals — see `flows/executors/contract.md` (next).
- Approval flow internals — see `flows/approval/spec.md` (next).
- Compensation/saga across multi-step jobs — separate ADR (0002, planned).
- Approval timeout / delegation — separate ADR (0003, planned).
- Rate-limit policy per `callerUpn` or per `ticketId` — phase 2.

---

## 10. Open items

1. **JWT signing key custody.** Key Vault HSM-backed key recommended, but final decision pending Catherine's call on SP ownership (open question #2 from design memo).
2. **Service Bus tier.** Standard is the minimum for topics. Premium gives geo-DR. Pilot = Standard. Production = revisit.
3. **Idempotency key max age.** 30 days assumed. Confirm against any retention or audit constraint Catherine has from customers.
