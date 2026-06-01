# Approval Flow Specification

**Status:** Draft v1 (production-grade target)
**Date:** 2026-04-29
**Pilot deployed:** 2026-05-01 — `ITSM-Approval-Bridge` flow `00000000-0000-4000-8000-000000000001` (slimmed pilot replacement, see deviations below)
**Pairs with:** [Dispatcher Contract](../dispatcher/contract.md), [Executor Contract](../executors/contract.md)

The Approval flow sits between the Triage Agent's `ProposeAction` write and the Dispatcher's `POST /provisioning/jobs` call. It is the **only** producer of valid JWTs the Dispatcher will accept. Every privileged write traces back to an approval row created here.

---

## ⚠ Pilot deviations from this spec (2026-05-01)

The pilot ships a much simpler `ITSM-Approval-Bridge` flow that delivers the core value (route Approvals state changes to dispatcher) without building the full multi-stage policy engine. The full Approval-flow per this spec is deferred to Phase 2.

| Section | Production spec | Pilot deployed (`ITSM-Approval-Bridge`) |
|---|---|---|
| §1 Auto-approve | No auto-approve in v1; every JobType through full policy stages | Same — no auto-approve. Single approver flips Approvals row to `Approved`. |
| §2 Trigger | SP "When item created" on Provisioning Jobs filtered to `Status eq 'Proposed'` | SP "When Approvals item modified" (3-min poll) filtered to SessionState in {Approved, Rejected} AND CompletedAt empty |
| §3 Inputs | Read all PJ fields written by ProposeAction | Read Approvals row + look up linked PJ via `LinkedJobId eq JobId` |
| §4 Action sequence | 1) Validate inputs, 2) Determine policy from JobType+Risk+Caller, 3) Run stage-by-stage approvers (Manager/IT-Owner/CAB), 4) Sign JWT, 5) POST to dispatcher | 1) Get linked PJ, 2) Switch on SessionState: **Approved** → call dispatcher (HTTP POST, no JWT) → mark Approvals.CompletedAt; **Rejected** → patch PJ to Rejected → mark Approvals.CompletedAt |
| §5 Approval Policies | Multi-stage with timeout + delegation + escalation | NOT IMPLEMENTED — pilot has policies seeded in SP but no engine consuming them |
| §6 JWT minting | Sign claims with Key Vault HSM key via jwt-sign Function | NOT IMPLEMENTED — bridge calls dispatcher with no JWT (pilot dispatcher trusts SAS URL) |
| §7 ApprovalStages list | One row per stage decision | NOT IMPLEMENTED — pilot writes only the top-level Approvals row |

### Critical gotcha discovered

The Approvals SP polling trigger silently filters out rows whose Editor is a SharePoint App identity. Test rows inserted via PnP-cert NEVER trigger the bridge. Fix: edit via Graph API with a user token. See `~/.claude/projects/.../memory/reference_pa_sp_trigger_filters_app_identity.md`.

### Migration path from pilot to full Approval flow

When promoting to full spec:
1. Build the multi-stage approval engine (read `ApprovalPolicies` lookup, iterate stages, send Approval cards via Teams connector, capture stage decisions in `ApprovalStages`)
2. Deploy `jwt-sign` Azure Function with KV-HSM signing key
3. Add `Sign_JWT` action before `Call_Dispatcher` and include the JWT as Bearer header
4. Update dispatcher to require + validate JWT (per `flows/dispatcher/contract.md` §1.3)
5. The bridge becomes redundant — its trigger surface (Approvals row state change) merges into the full Approval flow's policy execution

The pilot bridge is a structural placeholder. It establishes the audit row pattern (Approvals row → dispatcher → executor → audit) without committing to any policy implementation.

---

## 1. v1 policy: no auto-approve

**Per Catherine's call (2026-04-29):** every privileged write in v1 goes through the full Approval Policy stages. There is no "high-confidence / low-risk → bypass approval" shortcut. The Triage Agent's auto-resolve branch (KB reply / no-op) is permitted because no privileged write occurs there — but any `ProposeAction` that targets the Dispatcher MUST traverse this flow to completion before a JWT is minted.

This may relax in v1.x once we have data on which job types are safe to allowlist. Phase-2 conversation, not v1.

---

## 2. Trigger

**Trigger:** "When an item is created" — SharePoint connector, list `Provisioning Jobs`, filter `Status eq 'Proposed'`.

The Triage Agent's `ProposeAction` tool writes a row into Provisioning Jobs with `Status = "Proposed"`. That insert fires this flow.

**Why SP-trigger and not HTTP:** the agent is already writing the proposal row for audit. A separate HTTP trigger would either duplicate that write or require a parallel non-audited path. Keep one source of truth.

---

## 3. Inputs from the Proposed row

| Column | Set by Triage Agent | Notes |
|---|---|---|
| `JobId` (Title) | Agent | `PJ-{ULID}` — same ID flows through approval and dispatch |
| `Status` | Agent | `Proposed` (filter) |
| `JobType` | Agent | Must exist in `JobTypes` registry |
| `TicketId` | Agent | Lookup → Tickets list |
| `RitmId` | Agent (if request) | Lookup → Request Items |
| `Target` | Agent | JSON: `{ type, upn, id }` |
| `Args` | Agent | JSON object — must validate against `JobTypes.InputSchema` |
| `CallerUpn` | Agent | The human who originated |
| `CorrelationId` | Agent | ULID |
| `IdempotencyKey` | Agent | ULID — generated once per proposal |
| `ProposedAt` | Agent | UTC datetime |
| `Confidence` | Agent | 0–1 (informational; not a gate in v1) |
| `Risk` | Agent | low/medium/high (informational; chooses default policy) |

---

## 4. Action sequence

```
1.  Trigger: SP item created with Status = "Proposed"
2.  Update item: Status = "AwaitingApproval", AwaitingApprovalAt = now
3.  Emit approval.received to App Insights
4.  Validate inputs:
        a. JobType exists in JobTypes registry and Status = "active"
        b. Args schema-validates against JobTypes.InputSchema
        c. Target.upn / Target.id resolves in Graph (LookupUser / LookupGroup)
        d. CallerUpn resolves and is enabled in Graph
        → on any fail: Status = "Rejected", Reason = ..., emit approval.invalid, end
5.  Resolve Approval Policy:
        a. If Service Catalog item ordered (RitmId present), use sc_cat_item.PolicyId
        b. Else use Categories.PolicyId for the ticket's category
        c. Else fall back to JobTypes.DefaultPolicyId
        → if no policy resolves: Status = "Rejected", Reason = "no_policy", end
6.  For each stage in policy.Stages (ordered):
        a. Resolve approver(s) per stage's ApproverResolver
        b. Send Adaptive Card via Teams (or fallback email)
        c. Wait on response (timeout per stage, see §7)
        d. Record stage result in ApprovalStages SP list
        e. Apply stage rule (All / Any / Majority) to determine pass/fail
        f. On fail: Status = "Rejected", Reason = "stage_{n}_rejected", end
        g. On stage timeout: invoke escalation policy (see §7)
7.  All stages passed:
        a. Build JWT claims (see Dispatcher Contract §1.3)
        b. Sign with private key (Key Vault HSM, custodian: Catherine)
        c. POST to Dispatcher /provisioning/jobs with the JWT
        d. On 202: Update item Status = "Dispatched", DispatchedAt = now, JobId set, emit approval.dispatched
        e. On 200 idempotent replay: same as 202 but log idempotent flag
        f. On 4xx: Update Status = "DispatchRejected", Reason = response, emit approval.dispatch_rejected
        g. On 5xx / network: retry up to 3 with exponential backoff; if still failing, Status = "DispatchFailed", emit approval.dispatch_failed, alert in #itsm-dispatcher-alerts
8.  Notify caller (Teams or email) with outcome and ticket link
```

The Triage Agent receives no synchronous response — it watches the ticket for state changes and reports to the user.

---

## 5. Approval Policies SP list

| Column | Type | Notes |
|---|---|---|
| `PolicyId` (Title) | string | e.g., `AP-PWD-RESET-V1`, `AP-USER-CREATE-V1` |
| `DisplayName` | string | Human-readable |
| `Description` | multiline | When this policy applies, examples |
| `Stages` | multiline (JSON) | Array — see §6 |
| `Version` | int | Increment on any Stages change. JWT carries this. |
| `Status` | choice | `active` / `deprecated` |
| `OwningTeam` | Person | Who maintains this policy |
| `EffectiveFrom` | datetime | |
| `EffectiveUntil` | datetime | Optional |

### Seed policies for v1 (no auto-approve)

| PolicyId | Stages | Notes |
|---|---|---|
| `AP-LOW-RISK-V1` | Manager (Any) | Default for low-risk job types — single-stage manager approval |
| `AP-MED-RISK-V1` | Manager (Any) → IT-Owner (Any) | Default for medium-risk |
| `AP-HIGH-RISK-V1` | Manager (Any) → IT-Owner (Any) → CAB (Majority) | Default for high-risk and Change Management |
| `AP-PWD-RESET-V1` | Manager (Any) | Specific to `identity.resetPassword` — same as low but pinned for clarity |
| `AP-USER-CREATE-V1` | Manager (Any) → IT-Owner (Any) → HR-Confirm (Any) | New user creation needs HR confirmation that the hire is real |
| `AP-USER-DISABLE-V1` | Manager (Any) → IT-Owner (Any) | Offboarding |

`JobTypes.DefaultPolicyId` points to one of these per job type.

---

## 6. Stages JSON shape

```json
{
  "Stages": [
    {
      "name": "manager",
      "approverResolver": {
        "type": "manager_of_target",
        "fallback": { "type": "group", "value": "IT-Approvers-Backup" }
      },
      "rule": "any",
      "timeoutHours": 24,
      "onTimeout": "escalate"
    },
    {
      "name": "it_owner",
      "approverResolver": {
        "type": "ci_owner",
        "fallback": { "type": "group", "value": "IT-ITSM-Admins" }
      },
      "rule": "any",
      "timeoutHours": 12,
      "onTimeout": "escalate"
    },
    {
      "name": "cab",
      "approverResolver": { "type": "group", "value": "Change-Advisory-Board" },
      "rule": "majority",
      "timeoutHours": 48,
      "onTimeout": "reject"
    }
  ]
}
```

### `approverResolver` types

| Type | Resolves to | Used for |
|---|---|---|
| `manager_of_target` | Graph: `/users/{target.upn}/manager` | Most personal-impact actions |
| `manager_of_caller` | Graph: `/users/{callerUpn}/manager` | When caller is requesting on someone else's behalf |
| `ci_owner` | CMDB: `ConfigurationItems[ciId].Owner` | Service-impacting changes |
| `group` | Static SP group or Entra group | CAB, IT-Owner pools |
| `person` | Named person | Rare — should be a group |
| `cost_center_manager` | Graph + finance lookup | Catalogue items with cost |

### `rule`

| Rule | Pass condition |
|---|---|
| `any` | At least one approver approves |
| `all` | Every resolved approver approves |
| `majority` | > 50% of resolved approvers approve |

### `onTimeout`

| Action | Effect |
|---|---|
| `escalate` | Re-resolve approver via the resolver's fallback, send a fresh card, restart the stage timer (capped at 1 escalation per stage to prevent loops) |
| `reject` | Treat as rejection, end the flow with Reason = `stage_{n}_timeout` |
| `auto_approve` | **Not used in v1.** Reserved for low-risk job types in v1.x. |

---

## 7. Approval timeouts and delegation (interim — full design in ADR 0003)

**v1 interim rules**:

- **Default timeout:** 24h for manager stages, 12h for IT-Owner, 48h for CAB. Override per stage in policy JSON.
- **OOO detection:** before sending a card, query Graph `/users/{upn}/mailboxSettings`. If `automaticRepliesSetting.status = alwaysEnabled`, skip the user, fall back to:
  1. Their delegate (if `automaticRepliesSetting.scheduledStartDateTime` present and falls in current window)
  2. Their manager
  3. The policy's stage fallback group
- **Out-of-band approval revocation:** an approver can revoke an in-flight approval by replying `revoke` to the card. Revocation halts the flow at the current stage with Status = `Revoked`. Cannot revoke after Dispatcher returns 202 — once the JWT is minted, revocation is a separate compensation flow.

ADR 0003 will formalize: cascading delegation, multi-day timeouts, business-hours awareness, holidays, contractor exclusions, P1 incident fast-track. None of those land in v1.

---

## 8. Adaptive Card payload

Card sent to each stage's resolved approver(s) in Teams. Email fallback if Teams DM fails.

**Card content:**
- Title: `Approval needed — {jobType}`
- Body:
  - Caller: `{callerUpn}` (link to user in M365 admin)
  - Target: `{target.upn}` (link)
  - Action: human-readable from JobTypes registry
  - Args: pretty-printed JSON
  - Ticket: `{ticketId}` — link to SharePoint
  - Stage: `{n} of {total}` — `{stageName}`
  - Confidence: `{confidence}` (informational)
  - Risk: `{risk}`
- Actions:
  - **Approve** (primary)
  - **Reject** (requires comment)
  - **Defer 1h** (re-sends the card in 1h, stage timer paused; max 2 defers)
  - **Revoke** (only available if previously approved — see §7)

The card response webhook posts back into the Approval flow run via the connector's "Wait for an approval" pattern. (Power Automate Approvals connector can drive this directly; we wrap it with our own SP audit row to avoid being trapped in the Approvals connector backing store.)

---

## 9. Audit — ApprovalStages SP list

One row per stage attempt, including timeouts and escalations.

| Column | Notes |
|---|---|
| `JobId` | Lookup to Provisioning Jobs |
| `StageName` | manager / it_owner / cab / etc. |
| `StageOrder` | int |
| `ApproversResolved` | multiline (JSON) — UPNs the resolver chose |
| `ApproversWhoActed` | multiline (JSON) — UPN + decision + time |
| `Rule` | any / all / majority |
| `Outcome` | approved / rejected / timeout / escalated / revoked |
| `StartedAt` | datetime |
| `CompletedAt` | datetime |
| `DurationMs` | int |
| `EscalatedFrom` | string (optional — if this row is an escalation, the prior approver) |
| `Comments` | multiline append-only — captures rejection reasons, defer comments |

The JWT claims `approvers[]` array is populated from the *successful* stages — the actual humans whose decision authorized the dispatch. Failed/timeout stages stay in this list for audit but don't appear in the JWT.

---

## 10. JWT issuance (step 7 detail)

**Signing key:** RS256 from Key Vault HSM-backed key. Key name: `itsm-approval-signing-{env}`. Custodian: Catherine. Rotation: every 180 days; old key kept in JWKS for 7 days after rotation to allow in-flight JWTs to validate.

**JWKS endpoint:** the Approval flow exposes `https://approvals.itsm.{tenant}.com/.well-known/jwks.json` (a separate read-only flow that returns current + recent public keys). Dispatcher caches this for 60 minutes.

**Token lifetime:** `exp = iat + 60 minutes`. Long enough to absorb retry windows, short enough that a leaked token is operationally bounded.

**Replay protection:** `jti = JobId` (unique per proposal). Dispatcher persists in `JwtReplay` Azure Table with TTL `exp + 5 min`.

**Claims building order (so `argsHash` matches what Dispatcher computes):**
1. Read the Proposed row's `Target` and `Args` JSON
2. Canonicalize each per RFC 8785 (JSON Canonicalization Scheme)
3. SHA-256 the canonical bytes → `targetHash`, `argsHash`
4. Build claims object, sign

The Approval flow MUST use the exact same JCS implementation as the Dispatcher. Pin the library.

---

## 11. App Insights events

Standard custom dimensions: `correlationId`, `ticketId`, `jobId`, `jobType`, `callerUpn`, `policyId`, `policyVersion`, `environment`.

| Event | When |
|---|---|
| `approval.received` | Step 3 |
| `approval.invalid` | Step 4 fails |
| `approval.no_policy` | Step 5 fails |
| `approval.stage_started` | Per stage |
| `approval.stage_decided` | Per stage outcome |
| `approval.stage_escalated` | Escalation triggered |
| `approval.dispatched` | 202 from dispatcher |
| `approval.dispatch_rejected` | 4xx from dispatcher |
| `approval.dispatch_failed` | 5xx after retries |
| `approval.revoked` | Approver revoked pre-dispatch |

---

## 12. State on the Provisioning Jobs row

This flow drives the row through these statuses:

```
Proposed (set by agent)
   → AwaitingApproval (step 2)
   → Rejected | DispatchRejected | DispatchFailed | Dispatched (terminal for this flow)
```

After `Dispatched`, ownership transfers to the Dispatcher → Executor pipeline (Queued → InProgress → Succeeded/Failed/...).

---

## 13. What this flow MUST NOT do

- **Must not** call Graph for any privileged write. Reads only (manager lookup, OOO check, group membership).
- **Must not** mint a JWT before all policy stages return success.
- **Must not** mint a JWT for a `JobType` whose `Status = deprecated`.
- **Must not** rely on the Power Automate Approvals connector backing store as the audit record. Always mirror to ApprovalStages SP list (which is in-tenant and survives connector data resets).
- **Must not** treat absence of a manager (Graph returns 404 on `/manager`) as auto-approve. Falls through to the policy's fallback group.
- **Must not** include `Args` in App Insights events at risk of PII (e.g., new user's home address). Log `argsHash` only; full args live in the SP audit row which has tenant-controlled retention.

---

## 14. Out of scope for this spec

- The Adaptive Card schema's exact layout (handled inline in the notification flows, not this spec).
- ADR 0003 — full timeout / delegation / escalation policy.
- Phase-2 auto-approve allowlist when v1.x relaxes the rule.
- Integration with HR-Confirm stage for `AP-USER-CREATE-V1` — needs an HR system or HRSD list of "real new hires" to confirm against. Open item.

---

## 15. Open items

1. **HR-Confirm stage source.** The `AP-USER-CREATE-V1` policy includes an HR confirmation stage. What system is the source of truth for "this is a real hire"? HRSD list? Workday integration? File for now: hardcode to a Teams DM to a named HR person until source is decided.
2. **CAB membership.** The `Change-Advisory-Board` group needs members named. Pilot can use IT-ITSM-Admins as a stand-in; production must have a real CAB.
3. **OOO delegate detection.** Graph `mailboxSettings.automaticRepliesSetting` doesn't expose a "delegate UPN" cleanly — only a status and date range. Real delegation reading needs Exchange Online PowerShell. For v1, OOO triggers fallback-group, not delegate.
