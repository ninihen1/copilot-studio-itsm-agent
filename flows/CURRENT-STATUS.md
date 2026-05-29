# ITSM Pilot — Current Status

> Concise, verified status summary for this public copy. (The detailed internal task tracker lives in the private working repo.) Flow states below were confirmed live against the Power Platform environment.

**Pilot:** Level 1 ITSM on Microsoft 365 — Copilot Studio (triage) + Power Automate (orchestration/execution) + SharePoint (system of record) + an SPFx Service Portal (intake & status).

**State:** Operational pilot. The core loop — **portal intake → ticket-type validation → AI triage → approval → dispatch → scoped execution → audit** — is deployed and proven end-to-end. Production-hardening items are designed and partially wired (see *Pilot limitations*).

## Deployed and running

**Intake & triage**
- **ITSM Service Portal** (SPFx web part) — ticket intake and status.
- **ITSM-Triage-Orchestrator** — fires on new tickets, calls the Copilot Studio triage agent, applies the deflect / ask / propose outcome.
- **ITSM-Ticket-Type-Validator** — Incident-vs-Request validation gate; live and firing on ticket-create.
- **ITSM-SearchKnowledgeBase** — knowledge-base lookup helper.

**Request pipeline**
- **ITSM-RITM-Generator** → **ITSM-RITM-Validation-Triage** → **ITSM-RITM-Approval** — request-item creation, validation, and approval hold.
- **ITSM-SCTASK-Orchestrator** + **ITSM-SCTASK-PJ-Bridge** — task fan-out and Provisioning Job creation; terminal SCTASKs cascade closure up to the RITM and parent ticket.
- **ITSM-Approval-Bridge** — pilot approval routing from the Approvals list to the dispatcher.
- **ITSM-Dispatcher** — broadcast router: validates a job, marks it Dispatched.

**Executors** (all running; all E2E-proven) — Identity, Groups, Licensing, Exchange, SharePoint, Teams. Each is a scoped service principal that self-selects jobs by `JobType` prefix.

**Operational & scheduled**
- **ITSM-Scheduled-SLA-Timer**, **ITSM-Scheduled-Archival**, **ITSM-Major-Incident-Detector** — deployed and tested.
- **ITSM-Comment-Awaiting-Caller-Resume**, **ITSM-Comment-Resolved-Reopen** — comment-driven ticket state changes.
- **ITSM-Scheduled-License-Costs-Sync**, **ITSM-Helper-License-Lookup**, **ITSM-Helper-GetSiteInfo** — reference/helper flows.

**Retired / not in use**
- **ITSM-ProposeAction** (the agent-callable HTTP intake) — **retired**. The shipped path is flow-triggered triage on the Tickets list, not an agent→flow handoff.
- **ITSM-Approval** (original multi-stage draft) — superseded by the pilot Approval-Bridge.
- **ITSM-Comment-Notification** — currently stopped.

## Tested and proven

| Area | Result |
|---|---|
| Identity / Groups / Licensing / Exchange / SharePoint / Teams executors | All six paths verified end-to-end (password reset, group add/remove, license assign/revoke, mailbox grant/revoke, file restore, Teams channel + member). |
| Request fulfilment | Request → RITM → approval → SCTASK → Provisioning Job → executor chain proven. |
| Operational flows | SLA timer (warning / breach / pause-on-hold), archival, and major-incident clustering tested. |
| Taxonomy & catalog | 18 categories, ~80 subcategories, 8 catalog items (incl. 2 order guides) seeded. |

## Pilot limitations (designed; hardening in progress)

| Limitation | Current pilot behavior | Production direction |
|---|---|---|
| Dispatcher authentication | Trusts a signed Power Automate trigger URL. | Approval-signed JWT validated by the dispatcher. |
| Idempotency | SharePoint `IdempotencyKey` lookup (race-vulnerable). | Azure Table Storage insert with ETag. |
| Queueing | Executors poll the Provisioning Jobs list. | Service Bus topic with per-executor subscriptions. |
| Audit | SharePoint audit row + Power Automate run history. | Application Insights structured events as the system-wide log. |
| Secrets | Per-SP credentials in Key Vault. | Certificate-based auth with rotation. |
| Approval policy | Single-stage approval bridge. | Multi-stage policy engine (Manager → IT Owner → CAB). |
| Notifications | Adaptive Card templates exist; delivery wiring/proof in progress. | Approval, resolution, SLA, and MI cards fully wired. |

## References

- `IMPLEMENTATION-PLAYBOOK.md` — builder and architecture source of truth.
- `flows/dispatcher/contract.md`, `flows/approval/spec.md` — full production contracts with pilot-deviation tables.
- `decisions/0001-dispatcher-host.md` — dispatcher host decision and hardening path.
