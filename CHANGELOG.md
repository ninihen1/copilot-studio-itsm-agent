# Changelog

Notable changes to this Microsoft 365 ITSM project, grouped by release.

## [Unreleased]

### Added
- `ITSM-PJ-Ticket-Resolver` flow: resolves the parent ticket once a propose-path provisioning job completes successfully (the propose/Incident analogue of the Request path's SCTASK-PJ-Bridge closure), closing the gap where propose-path tickets stayed *In Progress* after their job succeeded.
- Flow-invoked AI triage: a Power Automate flow calls the Copilot Studio Helpdesk Triage Agent on each new ticket to classify it, search the knowledge base, and propose an action.
- Six Adaptive Card notification paths: approval request, approval granted, approval denied, ticket resolved, SLA breach, and major incident detected.
- Knowledge Base seed set with 40 published starter articles across password/MFA, license/access, email/calendar, Teams/SharePoint, and device/software scenarios.
- SharePoint permission groups for ITSM admins, approvers, agents, and users.
- Pilot hardening services provisioned: Application Insights, Azure Table idempotency storage, and a Service Bus dispatch topology.
- `ITSM-Ticket-Type-Validator` flow that checks every new ticket, auto-reclassifies deterministic low-risk mismatches, and pauses ambiguous tickets for caller confirmation.

### Changed
- Triage Orchestrator updates deflected non-Incident tickets and no longer writes text to the `Subcategory` lookup.

### Fixed
- SharePoint list schema aligned (identifier fields stored in `Title`, KB author mapped to `KbAuthor`).
- Blank KB search results route to a general AI fallback instead of asking "Did that help?".

## [0.3.0] - 2026-05-06

### Added
- SLA Timer flow: business-hours recurrence (Mon–Fri, 9:00–16:00 Australia/Sydney), 15-minute interval processing, pause-on-hold, 75% warning and 100% breach thresholds.
- Archival flow: daily 02:00 schedule, 90-day threshold for closed/resolved tickets, copy to Tickets-Archive with archive marker fields.
- Major Incident Detector: semantic clustering via the Triage Agent, a one-hour incident window, parent major-incident creation, and related-incident linking.
- User, admin, deployment, and troubleshooting documentation.

### Changed
- Major Incident Detector uses the SharePoint-created timestamp where needed and excludes already-escalated incidents to avoid duplicate parents.

### Fixed
- SLA, archival, and major-incident field mappings validated against the live SharePoint schema.

## [0.2.0] - 2026-05-02

### Added
- Five additional executor service principals and paths beyond Identity — Groups, Licensing, Exchange, SharePoint, and Teams — for full executor coverage of the Level 1 automation categories.
- An Exchange Online PowerShell Function wrapper for mailbox-permission operations.
- An SCTASK → Provisioning Job bridge for catalog tasks that carry a `JobType`.

### Changed
- Request fulfilment path: Service Catalog → RITM → approval → SCTASK → Provisioning Job → executor.
- Exchange executor moved from a Graph-only stub to EXO Function-backed mailbox-permission handling.
- SharePoint executor uses SharePoint REST where connector metadata was insufficient.

### Fixed
- SCTASK-PJ bridge plain-text `Variables` parsing.
- SharePoint connector metadata staleness (switched affected operations to SharePoint REST).
- Ticket state-transition handling for SCTASK, RITM, and parent-ticket closure.

## [0.1.0] - 2026-05-01

### Added
- Initial Microsoft 365 ITSM foundation: SharePoint as system of record, Power Automate for orchestration and execution, and the Copilot Studio Helpdesk Triage Agent.
- SharePoint lists provisioned and seeded; 18 categories and 80 subcategories.
- Service Catalog with 8 items (6 single-task items plus 2 order guides: New Hire Onboarding and User Offboarding).
- Catalog orchestration flows: RITM Generator, RITM Approval, SCTASK Orchestrator, and SCTASK-PJ Bridge.
- Base approval, dispatch, and identity execution loop.

### Changed
- Ticket taxonomy upgraded from free-text subcategories to a structured category/subcategory lookup model.
- Service Catalog extended with `TaskTemplates` for multi-task request fulfilment.

### Fixed
- Documented early platform gotchas: Power Automate SharePoint triggers can skip app-only-authored rows; Graph application permissions require matching directory roles for privileged actions; `secureData` settings differ by action type; REST flow creation uses POST.
