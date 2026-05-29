# Changelog

All notable changes to the Copilot Studio ITSM Level 1 pilot are tracked here.

Dates follow the requested release labels. Detailed work timing is tracked in `PROJECT_TIMELINE.md`.

## [Unreleased] - Day 4 in progress

Current Day 4 detail is tracked in `flows/CURRENT-STATUS.md`: 56 tasks total, 31 done, 20 pending review, and 5 blocked as of the 2026-05-08 strict evidence audit.

### Added

- ProposeAction secured flow deployed, added to named solution `FS Demo`, and wired to the Triage Agent action component.
- Six Adaptive Card notification paths:
  - Approval request.
  - Approval granted.
  - Approval denied.
  - Ticket resolved.
  - SLA breach.
  - Major incident detected.
- Knowledge Base seed set imported with 40 published starter articles across password/MFA, license/access, email/calendar, Teams/SharePoint, and device/software scenarios.
- SharePoint permission groups created for ITSM admins, approvers, agents, and users.
- App Insights, Azure Table idempotency storage, and Service Bus dispatch topology provisioned for the pilot hardening path.
- Day 3 operational regression coverage rerun successfully for SLA Timer, Archival, and Major Incident Detector.

### Changed

- Day 4 evidence model tightened: source/docs/wiring-only items without saved runtime proof were demoted to `PENDING REVIEW`.
- SharePoint executor hardening, Teams executor hardening, and executor pre-flight work are documented but remain pending runtime/audit proof where noted in `flows/CURRENT-STATUS.md`.

### Fixed

- SharePoint list audit fixed to match the current schema, including identifier fields stored in `Title` and KB author mapping to `KbAuthor`.
- Triage Orchestrator patched and redeployed to update deflected non-Incident tickets and stop writing text to the `Subcategory` lookup.
- Task 22 regression reverted and hotfixed so blank KB search results route to a general AI fallback instead of asking `Did that help`.

### Deployed

- Day 4 deployed components include `ITSM-ProposeAction`, `ITSM-Triage-Orchestrator`, SharePoint group/permission updates, KB seed import, Azure hardening resources, and refreshed operational-flow validation. Items that still need live runtime proof remain listed as `PENDING REVIEW` or `BLOCKED` in `flows/CURRENT-STATUS.md`.

## [0.3.0] - 2026-05-06 (Day 3)

### Added

- SLA Timer operational flow:
  - Business-hours recurrence, Monday-Friday, 9:00-16:00 Australia/Sydney.
  - 15-minute interval processing.
  - Pause-on-hold behavior.
  - Warning threshold at 75%.
  - Breach threshold at 100%.
- Archival operational flow:
  - Daily 02:00 schedule.
  - 90-day threshold for closed or resolved tickets.
  - Copy to Tickets-Archive.
  - Original-ticket archive marker fields.
- Major Incident Detector:
  - Triage Agent semantic clustering.
  - One-hour incident window.
  - Parent major incident creation.
  - Related incident linking.
- Day 3 test matrix at `prompts/day3_testing_results.md`.
- User, admin, deployment, and troubleshooting documentation drafts.
- Documentation consolidation:
  - Documentation Map in `README.md`.
  - `DEPLOYMENT.md` retained as active deployment runbook.
  - `docs/DEPLOYMENT_GUIDE.md` reduced to a pointer.

### Changed

- Major Incident Detector changed from `OpenedDate` field dependency to SharePoint-created timestamp behavior where needed.
- Major Incident Detector excludes already-escalated incidents to avoid duplicate parent tickets.
- Admin and troubleshooting docs trimmed to reduce deployment duplication.
- `DEPLOYMENT.md` updated with Phase 3/3.1 flow order, Triage Agent configuration notes, and final validation checklist.

### Fixed

- Major Incident duplicate-parent issue fixed by excluding already-escalated incidents.
- Major Incident field mismatch fixed by moving away from the `OpenedDate` dependency.
- Day 3 schema concern BUG-D3-001 resolved after validating live SharePoint fields:
  - SLA fields: `SlaStatus`, `OnHoldSince`, `TotalPausedMinutes`, `SlaBusinessMinutesElapsed`, `SlaPercentElapsed`, `SlaTargetMinutes`, `SlaWarningAt`, `SlaBreachedAt`.
  - Archival fields: `Archived`, `ArchivedAt`.
  - Major Incident fields: `MajorIncidentFlag`, `EscalationFlag`, `MajorIncidentClusterKey`, `MajorIncidentDetectedAt`, `ParentTicket`.

### Deployed

- `ITSM-SLA-Timer`
  - Flow ID: not recorded in repo.
  - Proven run ID: `08584235481311151630469117691CU26`.
  - Evidence: Ticket 66 reached 77% warning threshold; Ticket 67 paused correctly while On Hold.
- `ITSM-Scheduled-Archival`
  - Flow ID: not recorded in repo.
  - Proven run ID: `08584235481305009034217097116CU17`.
  - Evidence: Ticket 68 archived successfully and archive item created with `ArchivedByFlow`.
- `ITSM-Major-Incident-Detector`
  - Flow ID: not recorded in repo.
  - Proven run ID: `08584235476789484157853561119CU45`.
  - Evidence: Tickets 78-80 clustered into one parent MI, ticket 81.

## [0.2.0] - 2026-05-02 (Day 2)

### Added

- Five additional executor service principals and executor paths beyond Identity:
  - Groups.
  - Licensing.
  - Exchange.
  - SharePoint.
  - Teams.
- Full executor coverage for Level 1 pilot automation categories.
- Phase 3.1 Exchange Online PowerShell Function wrapper path for mailbox permission operations.
- SCTASK to Provisioning Job bridge path for catalog tasks with a `JobType`.

### Changed

- Request fulfillment path now supports Service Catalog to RITM to approval to SCTASK to Provisioning Job to executor.
- Exchange executor path changed from Graph-only stub behavior to EXO Function-backed mailbox permission handling.
- SharePoint executor implementation changed to use SharePoint REST where connector metadata was stale or insufficient.

### Fixed

- BUG-D2-001: SCTASK-PJ Bridge plain-text Variables parsing issue.
- BUG-D2-002: SharePoint connector metadata staleness, resolved by switching affected operations to SharePoint REST API.
- BUG-D2-003: Ticket state transition handlers for SCTASK, RITM, and parent Ticket closure.

### Deployed

- Service principals and AppIds:
  - `SP-IT-Identity`: `00000000-0000-4000-8000-000000000014`.
  - `SP-IT-Groups`: `00000000-0000-4000-8000-000000000055`.
  - `SP-IT-Licensing`: `00000000-0000-4000-8000-000000000025`.
  - `SP-IT-Exchange`: `00000000-0000-4000-8000-000000000058`.
  - `SP-IT-SharePoint`: `00000000-0000-4000-8000-000000000046`.
  - `SP-IT-Teams`: `00000000-0000-4000-8000-000000000013`.
- Executor flows:
  - `ITSM-Identity-Executor`: `00000000-0000-4000-8000-000000000043`.
  - `ITSM-Groups-Executor`: flow ID not recorded in repo.
  - `ITSM-Licensing-Executor`: flow ID not recorded in repo.
  - `ITSM-Exchange-Executor`: flow ID not recorded in repo.
  - `ITSM-SharePoint-Executor`: flow ID not recorded in repo.
  - `ITSM-Teams-Executor`: flow ID not recorded in repo.
- E2E test evidence:
  - Ticket 22 to PJ 6: password reset succeeded.
  - Tickets 30-31 to PJs 11-12: group add/remove succeeded.
  - Tickets 32-33 to PJs 13-14: license assign/revoke succeeded.
  - Tickets 34-35 to PJs 15-16: EXO permission grant/revoke succeeded.
  - Ticket 36 to PJ 17: SharePoint file restore and permission grant succeeded.
  - Tickets 37-38 to PJs 18-19: Teams channel create and member add succeeded.

## [0.1.0] - 2026-05-01 (Day 1)

### Added

- Initial Microsoft 365 ITSM pilot infrastructure:
  - SharePoint system of record.
  - Power Automate orchestration and execution layer.
  - Copilot Studio Helpdesk Triage Agent path.
- 16 SharePoint lists provisioned and seeded.
- 18 categories and 80 subcategories.
- Service Catalog with 8 items:
  - 6 single-task catalog items.
  - 2 order guides: New Hire Onboarding and User Offboarding.
- Catalog orchestration flows:
  - RITM Generator.
  - RITM Approval.
  - SCTASK Orchestrator.
  - SCTASK-PJ Bridge.
- Base approval, dispatch, and identity execution loop.

### Changed

- Ticket taxonomy upgraded from free-text-only subcategory behavior to structured category/subcategory lookup model.
- Service Catalog expanded with `TaskTemplates` for multi-task request fulfillment.
- Request fulfillment model aligned with ServiceNow-style Request to RITM to SCTASK lifecycle.

### Fixed

- Initial pilot gotchas documented during infrastructure work:
  - Power Automate SharePoint triggers can skip app-only-authored rows.
  - Graph application permissions require matching directory roles for privileged data-plane actions.
  - Power Automate secureData settings differ by action type.
  - Power Automate REST flow creation uses POST.

### Deployed

- Power Platform environment:
  - Flow Studio Demo: `00000000-0000-4000-8000-000000000045`.
- SharePoint site:
  - `https://contoso.sharepoint.com/sites/ITSM`.
- Azure resources:
  - Resource group: `rg-itsm-pilot`.
  - Key Vault: `kv-itsm-demo`.
  - Subscription: Microsoft Partner Network, `00000000-0000-4000-8000-000000000037`.
- Service principals:
  - `SP-IT-Provisioning`: `00000000-0000-4000-8000-000000000020`.
  - `SP-IT-Identity`: `00000000-0000-4000-8000-000000000014`.
- Base flows with recorded IDs:
  - `ITSM-Triage-Orchestrator`: `00000000-0000-4000-8000-000000000030`.
  - `ITSM-Identity-Executor`: `00000000-0000-4000-8000-000000000043`.
  - `ITSM-Dispatcher`: `00000000-0000-4000-8000-000000000033`.
  - `ITSM-Approval-Bridge`: `00000000-0000-4000-8000-000000000001`.
  - `ITSM-Helper-GetSiteInfo`: `00000000-0000-4000-8000-000000000052`.
