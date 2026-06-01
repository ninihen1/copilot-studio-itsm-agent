# ADR 0002 — Triage→Approval→Dispatch reconciliation

**Status:** Accepted (docs reconciled 2026-05-30; flow changes followed)
**Date:** 2026-05-30
**Owner:** Catherine Han
**Supersedes the intake/approval assumptions in:** `itsm-design-memo.md` §3-4, `flows/approval/spec.md`, `flows/triage-orchestrator/SPEC.md`
**Pairs with:** [ADR 0001 — Dispatcher host](0001-dispatcher-host.md)

> **Correction 2026-05-30:** Divergence 3 (Request-path kill-switch bypass) was **retracted** after a live read of `ITSM-SCTASK-PJ-Bridge` — it creates the PJ at `AwaitingApproval` and calls the Dispatcher inline, so the kill-switch is intact and there is no bypass. The original claim came from a stale 2026-05-03 note. Divergences 1 (doc says `Proposed`, live is `AwaitingApproval`), 2 (incident approval dormant), and 4 (ProposeAction retired) stand. Net: reality is more coherent than the first draft implied — the Dispatcher is the genuine universal choke-point.

## Context

A 2026-05-30 audit compared the live flows in **Flow Studio Demo** against the design docs and found the implementation had drifted from both the original design and the documented pilot, concentrated at the **Triage → Approval → Dispatch seam**. Two flows had been modified the same day (Triage-Orchestrator `8214cc66` at 00:36; ProposeAction `e0f99dd7` retired at 05:42). This ADR records what is actually live, the evidence, and the agreed direction.

### Evidence (live run history, pulled 2026-05-30)

- **Approval-Bridge (`05b00ed2`)** — every run since **2026-05-01** is a sub-second (~60 ms) no-op short-circuit. Only the four 2026-05-01 runs (1.4–2.7 s) actually POSTed the Dispatcher. **No incident approval has dispatched through the bridge in 29 days.** Triage *does* create the `Approvals` row (`SessionState=InProgress`), but nothing flips it to `Approved`, so the bridge never fires.
- **Triage-Orchestrator (`8214cc66`)** — last run 2026-05-30 00:32 **Failed**: agent returned `propose` for a stale/deleted ticket, `Update_Ticket_OnPropose` PatchItem returned **HTTP 404 "Could not find list item"**, so all downstream propose actions skipped. Root cause is a stale polling-trigger replay, not a logic bug.
- **Dispatcher (`97a4c109`)** — healthy, but every invocation is `manual` (direct HTTP smoke tests). None of its successes came from the Approval-Bridge.
- **Request/RITM path** — the only approval mechanism actually carrying traffic. `ITSM-RITM-Approval` (`fe842a60`) raises its own Teams `WaitForAnApproval` card; this is what the smoke test exercised.

### Divergences found

1. **PJ `Proposed` stage collapsed.** Triage writes the Provisioning Job (PJ = executable-action audit row) directly as `JobStatus=AwaitingApproval` and also creates an `Approvals` row. The triage SPEC said it writes `Status=Proposed` and "the Approval flow §4 takes over (trigger: `Status eq Proposed`)". **No flow triggers on PJ at all** — the Approval-Bridge triggers on the `Approvals` list. The dispatcher contract already accepts `AwaitingApproval`, so this is a documentation/spec inconsistency, not a dispatcher break.
2. **Incident-path approval is unwired and dormant.** No flow raises a Teams card or sets `Approvals.SessionState=Approved` for incident proposals. Rows sit at `InProgress` forever (see evidence). The "wire approval card" tasks were never proven.
3. ~~Request path bypasses the Dispatcher and its kill-switch.~~ **RETRACTED 2026-05-30 (live read).** `ITSM-SCTASK-PJ-Bridge` (`f966bb1e`, modified 2026-05-14) creates the PJ at `JobStatus=AwaitingApproval` and then calls the **Dispatcher inline** (HTTP POST to workflow `9bec7f27` — the same endpoint the Approval-Bridge uses), which patches it to `Dispatched`. So the Request path **does** route through the Dispatcher and **is** covered by the kill-switch. The bypass claim came from a stale 2026-05-03 note that predated the 2026-05-14 rewrite — true then, false now. **No kill-switch bypass exists.** Live-verified 2026-05-30: the Dispatcher (`97a4c109`) returns 503 + Terminate before `Patch_PJ_To_Dispatched` when `Config[Key=KillSwitch].Value` lowercases to `true` (`Get_KillSwitch`→`Check_KillSwitch`). ⚠ It engages **only** on `'true'` — if the Config row stores `Yes`/`No` the kill switch is silently inert; verify the stored value before relying on it.
4. **Agent HTTP write path retired.** `ITSM-ProposeAction` is RETIRED (2026-05-30). The architecture inverted to **flow-drives-agent**: Triage-Orchestrator calls the Copilot agent server-side via `ExecuteCopilotAsyncV2` and writes the rows itself.

Stale-but-not-broken: `ITSM-Ticket-Type-Validator` (`0af8362e`) is now LIVE (docs said "Planned/Not created"); Triage trigger is `GetOnUpdatedItems` gated on `TicketTypeValidated=true` (docs said `GetOnNewItems`); triage markers are `<<<TRIAGE_BEGIN>>>`/`<<<TRIAGE_END>>>` (docs said `==TRIAGE_RESULT==`).

## Decision

Adopt a **hybrid**: keep the reality's better intake, restore the plan's governance, finish the one approval mechanism that works.

| Dimension | Verdict | Action |
|---|---|---|
| Intake | Reality wins (flow-drives-agent) | Keep `ProposeAction` retired; Triage-Orchestrator owns intake. |
| Choke-point / kill-switch | Already intact — no action | Both lanes route through the Dispatcher (incident via Approval-Bridge; Request via SCTASK-PJ-Bridge's inline `Call_Dispatcher`), so the kill-switch already covers every write. The Triage rewrite keeps the incident lane calling the Dispatcher. |
| Approval | Converge | Use one approval mechanism — the working `RITM-Approval` Teams-card pattern — for the incident path too; retire the dormant `Approvals`-row + `Approval-Bridge` detour (or drive it from the same card). No incident proposal may silently dead-end. |
| Auth (JWT) + policy engine | Defer | Remain Phase 2 / NOT BUILT. Stop documenting them as if pending; the dispatcher trusts the SAS URL for the pilot (acceptable, single-env). |
| PJ state model | Honesty | Document `AwaitingApproval` as the real first state; the `Proposed` stage is retired. |
| Approval timeout | Escalate once → reject | See below. |

**Approval timeout (decided 2026-05-30, applies to the Triage incident-approval rewrite):** the `WaitForAnApproval` must time out — the native action has no built-in timeout, so implement via a parallel `Delay` race or a `Scope` with `runAfter: TimedOut`. On timeout, **escalate once**: raise a fresh approval assigned to the fallback approver(s), restart the timer (default 24h), capped at one escalation. ⚠ `CreateAnApproval`'s `assignedTo` takes a **semicolon-separated list of UPNs/emails — NOT a SharePoint group id or group object** (verified against the connector schema + live RITM-Approval, which feeds a bare UPN). So the "ITSM Approvers" fallback must be resolved to member UPNs: **pilot = a `Config`-stored semicolon UPN list** (e.g., `Config` `Key=FallbackApprovers`), or expand the SP group at runtime via SharePoint REST (`_api/web/sitegroups/getbyid(<id>)/users` → map `Email` → `join(';')`; watch for nested security-group members + blank emails). Multiple UPNs = first-to-respond. The fallback should be a *different* person from the fixed primary approver. On the **second** timeout, **auto-reject**: PJ → `Rejected`/`Expired`, parent ticket → `On Hold` with reason, notify caller + approver. **Never auto-approve on timeout** (default-deny; matches approval spec §6 `auto_approve` = "not used in v1"). Pilot fallback is a fixed `Config`-stored UPN list (not a group id — see the `assignedTo` note above); dynamic manager-of-target resolution stays a later phase. **Note:** `ITSM-RITM-Approval` currently waits indefinitely (no timeout) and carries the same silent-stall risk — apply the same policy there for consistency.

**As-built deltas (2026-05-30, from the flow build):**
- **A — `Generate_ApprovalSessionId` retained** (an earlier note suggested removing it with the Approvals row). It's no longer tied to the dead Approvals list; it now stamps a correlation/audit id onto the PJ row, the `Call_Dispatcher` body (`approvalSessionId`, which the Dispatcher persists onto the PJ at dispatch), and the reject `ErrorJson`. **Only `Get_PolicyId` + `Create_Approvals_Row` are removed.**
- **B — every reject/timeout path must touch the ticket + notify, not just the PJ.** Each path patches the PJ (`Rejected` + `ErrorJson`) and must ALSO update the parent ticket + notify the caller (mirror RITM-Approval's denied-notification). Verified details (live reads 2026-05-30):
  - **HoldReason is a fixed-choice dropdown (`allowTextEntry=false`)** with only `Awaiting Caller` / `Awaiting Change` / `Awaiting Problem` / `Awaiting Vendor` — none fit "approval declined" and it can't be free text. **Add a new choice** (e.g. `Approval Declined`) — additive/non-breaking — used for both reject + timeout, with reject-vs-timeout detail in WorkNotes/`ErrorJson`. Do **not** reuse `Awaiting Caller` (it's the trigger for `ITSM-Comment-Awaiting-Caller-Resume` → a caller comment would silently revive the ticket).
  - ⚠ **SLA interaction (verified by reading `ITSM-Scheduled-SLA-Timer`):** `If_On_Hold` keys on `TicketState == 'On Hold'` **only — it ignores HoldReason** — and `Patch_On_Hold_Pause` freezes the SLA clock. So a rejected ticket set to `On Hold` **never breaches and never pressures anyone** (silent-stall risk). **Open decision:** if rejected/timed-out incidents must stay accountable, route to an **active state (`In Progress` + assignment) so the SLA keeps running and breach-notify fires**; use `On Hold` only to deliberately park them out of SLA. This supersedes the earlier blanket "→ On Hold".
  - **Adjacent open question:** during the approval *wait*, Triage leaves the ticket `In Progress`, so the SLA clock **burns through the 24–48h wait** (business-hours accrual; low-priority target ≈ 1440 business-min/24h) — a long approval can breach before the approver acts. Decide the ticket's SLA posture *during* the wait (e.g. `On Hold` while awaiting approval, then move on outcome).
  - **Patch method = SP REST `MERGE`** (`Send an HTTP request to SharePoint`, `X-HTTP-Method: MERGE`, `IF-MATCH: *`, `odata=nometadata`) writing only the changed fields — a true partial update (untouched columns keep current server values → no clobber, no `GetItem` needed). This is the **exact pattern `ITSM-Scheduled-SLA-Timer` already uses** — copy that action shape. Connector `PatchItem` is the fallback but requires ALL Required columns, so it needs a *fresh* `GetItem` + ~14-field payload (RITM-Approval `Patch_Parent_Ticket_Rejected` style). Caveat: appending a WorkNotes audit line needs the *current* WorkNotes read first (MERGE only writes sent fields).

## Consequences

- **Docs (this change):** reconcile the specs/status/ADR text to the above. Done in the same session as this ADR.
- **Flows (separate work stream):** implement the single approval mechanism — inline `CreateAnApproval`/`WaitForAnApproval` in Triage's `Outcome_Propose` (copy `ITSM-RITM-Approval`'s human-gate pattern) plus `Create_PJ`(AwaitingApproval)→`Call_Dispatcher` inline (copy `ITSM-SCTASK-PJ-Bridge`'s dispatch leg) — then Stop the Approval-Bridge. Plus stale-trigger hardening on the Validator/Triage polling triggers. Until that lands, the incident-path approval remains a manual `Approvals`-row flip. **Choke-point routing needs no work — both lanes already go through the Dispatcher (corrected divergence 3).**
- Phase-2 JWT/policy/Service Bus items from ADR 0001 are unchanged and still deferred.

## Out of scope

- The full multi-stage Approval Policy engine and JWT minting (ADR 0001 hardening item 2; approval spec §5-§10).
- Service Bus dispatch topology (ADR 0001 hardening item 4).
