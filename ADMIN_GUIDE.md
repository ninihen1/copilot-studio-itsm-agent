# ITSM Level 1 Pilot Admin Guide

**Audience:** IT managers, service desk leads, Power Platform admins, and tenant admins  
**System of record:** SharePoint site `https://contoso.sharepoint.com/sites/ITSM`  
**Power Platform environment:** Flow Studio Demo, environment id `00000000-0000-4000-8000-000000000045`

This guide explains how the ITSM pilot is structured and how admins operate the system.

## 1. Architecture Overview

The ITSM system follows a six-stage pipeline: Intake, Triage, Approval, Dispatch, Execution, and Audit. The operating rule is: **AI proposes, humans approve, scoped service principals execute.** No Copilot Studio agent has Microsoft Graph write permissions.

For the full architecture, pilot status, and implementation history, see [`../README.md`](../README.md) and [`../IMPLEMENTATION-PLAYBOOK.md`](../IMPLEMENTATION-PLAYBOOK.md).

## 2. Pilot Components

This table is a day-to-day operator reference. For full deployment status and implementation details, see [`../IMPLEMENTATION-PLAYBOOK.md`](../IMPLEMENTATION-PLAYBOOK.md).

### Core SharePoint Lists

| List | Purpose |
|---|---|
| Tickets | Parent record for Incidents, Requests, Problems, and Changes. |
| Request Items | RITM records created from Service Catalog items. |
| Tasks | SCTASK records under RITMs. |
| Provisioning Jobs | Audit row per privileged write. |
| Approvals | Approval session rows for tickets, RITMs, or jobs. |
| Approval Stages | Provisioned for multi-stage approval detail. |
| Approval Policies | Reusable approval policies. |
| JobTypes | Registry of valid automation job types. |
| Categories | Top-level taxonomy. |
| Subcategories | Child taxonomy with optional JobTypeHint. |
| Service Catalog | Orderable request items and order guides. |
| Priority Matrix | Impact x urgency to priority and SLA targets. |
| Config | Kill switch and environment toggles. |
| Knowledge Base | Published support articles. |
| Configuration Items | CMDB-style list of services, apps, devices, and systems. |
| Tickets-Archive | Archived closed tickets. |

### Deployed Pilot Flows

| Flow | Purpose |
|---|---|
| ITSM-Triage-Orchestrator | Runs when a ticket is created and calls the Triage Agent. |
| ITSM-Ticket-Type-Validator | Planned validation gate for new Tickets rows before triage, RITM generation, or major incident detection. |
| ITSM-Dispatcher | HTTP endpoint that dispatches approved jobs. |
| ITSM-Approval-Bridge | Pilot bridge from Approvals list to Dispatcher. |
| ITSM-Identity-Executor | Executes `identity.*` jobs such as password reset. |
| RITM Generator | Creates RITMs from Request tickets and Service Catalog matches. |
| RITM Approval | Holds RITMs pending manager approval, then creates SCTASKs. |
| SCTASK -> PJ Bridge | Creates Provisioning Jobs for automated SCTASKs. |
| SCTASK Orchestrator | Closes RITMs and parent tickets when tasks complete. |
| SLA Timer | Runs every 15 minutes in business hours and updates SLA status. |
| Archival | Copies older closed tickets to Tickets-Archive. |
| Major Incident Detector | Looks for clusters of related incidents and creates MI parent tickets. |

Some flows may be authored but not deployed in a given pilot environment. Confirm deployment in Power Automate before relying on them operationally.

## 3. Request And Automation Flow

For catalog requests, the normal flow is:

```text
Ticket created with TicketType=Request
  -> Ticket Type Validator confirms Request vs Incident classification
  -> RITM Generator matches Service Catalog by SubcategoryHint
  -> Request Item created with RitmState=Pending Approval
  -> RITM Approval sends manager approval
  -> On approval, SCTASKs are created from TaskTemplates
  -> SCTASK -> PJ Bridge creates Provisioning Jobs for tasks with JobType
  -> Dispatcher marks jobs Dispatched
  -> Executor flow performs job
  -> SCTASK closes based on job result
  -> SCTASK Orchestrator closes RITM and then parent Ticket
```

Manual tasks have an empty `JobType` and should be fulfilled by the assigned group.

### Ticket Type Validation Gate

Ticket type validation should run immediately after a row is created in **Tickets** and before downstream automation acts on the row.

Recommended implementation:

- Create a separate `ITSM-Ticket-Type-Validator` flow with a SharePoint **When an item is created** trigger on the **Tickets** list.
- Add validation columns to **Tickets**: `TicketTypeValidated`, `TicketTypeValidationStatus`, `TicketTypeValidationReason`, `SuggestedTicketType`, and optionally `TypeOverrideConfirmed`.
- Auto-reclassify only deterministic low-risk rows, such as an Incident whose subcategory maps to exactly one active Service Catalog item and has no existing RITM, Provisioning Job, approval, or major incident link.
- Prompt the caller or service desk for ambiguous rows, such as multiple catalog matches, missing subcategory, or a Request that has no active catalog match.
- Exclude `TicketSource=ProposeAction` rows from forced reclassification unless explicitly required; those rows are created by the agent action after its own validation.

Downstream trigger guards should wait for validation before acting:

- RITM Generator: `TicketType=Request` and validation complete or `TicketSource=ProposeAction`.
- Triage Orchestrator: non-Request tickets after validation, still excluding `TicketSource=ProposeAction`.
- Major Incident Detector: validated Incident tickets only.
- SLA Timer: open tickets, preferably excluding rows with `TicketTypeValidationStatus=NeedsConfirmation`.

Do not add validation as a simple parallel branch in RITM Generator, Triage Orchestrator, or Major Incident Detector. Those flows already race on the same create event; validation must be a gate or the downstream flows must be guarded.

## 4. Operational Flows

### SLA Timer

The SLA Timer flow runs every 15 minutes during business hours, Monday to Friday, 09:00-16:00 in **AUS Eastern Standard Time**.

It:

- Reads open tickets that are not Resolved, Closed, or Cancelled.
- Calculates target minutes from ticket priority.
- Pauses SLA tracking when a ticket is On Hold.
- Marks tickets as **Warning** at 75% elapsed.
- Marks tickets as **Breached** at 100% elapsed.
- Writes work notes when SLA state changes.

Admin checks:

- Confirm open tickets have valid Priority values.
- Confirm `SlaStatus`, `SlaWarningAt`, `SlaBreachedAt`, and `MadeSla` update as expected.
- Review flow run history for failed PatchItem actions.

### Archival

The Archival flow runs daily at 02:00 AUS Eastern Standard Time.

It:

- Finds tickets with state Closed or Resolved.
- Uses the `ArchiveAfterDays` parameter, default `90`.
- Copies ticket details to **Tickets-Archive**.
- Marks the original ticket `Archived=true` and records `ArchivedAt`.

Admin checks:

- Confirm `Tickets-Archive` preserves the needed fields.
- Confirm closed-ticket list views exclude archived items.
- Test with a small synthetic sample before enabling in production.

### Major Incident Detector

The Major Incident Detector runs when new tickets are created.

It:

- Evaluates new Incident tickets.
- Looks back over a configurable window, default `60` minutes.
- Uses a threshold, default `3` related incidents.
- Calls a Copilot Studio agent to analyze symptoms and related context.
- Creates a Major Incident parent ticket when a cluster is detected.
- Links child incidents to the parent.

Admin checks:

- Confirm the trigger uses user-created tickets, not app-only test rows.
- Review created Major Incident tickets for false positives.
- Tune `WindowMinutes` and `Threshold` based on pilot volume.

## 5. Service Catalog Management

The Service Catalog list stores orderable request items.

Important fields:

| Field | Use |
|---|---|
| Title | Item code, such as `CAT-PWD-RESET`. |
| ItemName | User-facing catalog item name. |
| Category | Parent category lookup. |
| SubcategoryHint | Used by RITM Generator to match requests. |
| JobType | Automation job type for single-task items. Empty means manual. |
| ApprovalPolicy | Policy lookup that overrides category default. |
| InputSchema | JSON schema for variables captured from the user. |
| TaskTemplates | JSON array for multi-task order guides. |
| Visibility | Controls intended audience. |
| SlaDays | Target fulfillment window. |

Seeded catalog examples:

- Password Reset
- License Request
- Add to Group
- Shared Mailbox Access
- Restore SharePoint File
- Software Install Request
- New Hire Onboarding
- User Offboarding

### Adding A Catalog Item

1. Confirm the top-level category and subcategory exist.
2. Confirm the `JobType` exists and is active in JobTypes if automation is needed.
3. Create a Service Catalog row.
4. Set `ApprovalPolicy`.
5. Add `InputSchema`.
6. For multi-task requests, add `TaskTemplates` JSON.
7. Smoke test with a Request ticket using the matching subcategory.

For ticket-type validation, each subcategory that should auto-route to Request should map to exactly one active Service Catalog item. If multiple active items share the same `SubcategoryHint`, the portal must ask the user to choose a catalog item and the validator should treat the ticket as ambiguous rather than guessing.

Task template example:

```json
[
  {
    "sortOrder": 10,
    "jobType": "groups.addMember",
    "shortDescription": "Add user to approved security group",
    "assignmentGroup": ""
  },
  {
    "sortOrder": 20,
    "jobType": "",
    "shortDescription": "Notify requester that access is ready",
    "assignmentGroup": "IT-Service-Desk"
  }
]
```

## 6. Subcategory Configuration

The taxonomy uses:

- **Categories** for top-level routing.
- **Subcategories** for precise classification and catalog matching.

Each Subcategories row includes:

- Title, displayed as Subcategory Name.
- ParentCategory lookup.
- Status.
- SortOrder.
- JobTypeHint.

`JobTypeHint` helps the Triage Agent infer an automation path. It does not execute anything by itself.

When changing taxonomy:

1. Add or update the parent category first.
2. Add active subcategories under the parent.
3. Set JobTypeHint only when the automation is valid and approved for pilot use.
4. Update Service Catalog `SubcategoryHint` for requestable services.
5. Test the Triage Agent classification and RITM Generator matching.

## 7. Permission Groups

Create these SharePoint groups for pilot operations:

| Group | Members | Access |
|---|---|---|
| IT-ITSM-Admins | Catherine plus named backup | Full admin access to ITSM lists and config. |
| IT-Approvers-Backup | Helpdesk leads | Backup approval path. |
| Change-Advisory-Board | Senior IT approvers | CAB approval for future Change flows. |
| HR-Confirmation-Approvers | HR partners | HR confirmation for onboarding and offboarding. |
| ITSM-Agent-Users | Pilot users | Read access to user-facing lists and submit access through supported surfaces. |

Recommended list permissions:

| List | Access |
|---|---|
| Tickets | Users read relevant rows; admins full control. |
| Knowledge Base | Users read published articles; KB authors edit. |
| Configuration Items | Users read; admins full control. |
| Categories, Subcategories, Service Catalog | Users read; admins edit. |
| Provisioning Jobs | Admins only. |
| Approvals and Approval Stages | Admins and approvers only. |
| JobTypes | Users read; admins edit. |
| Config | Admin edit only. Break inheritance. |

The Tickets list has a `ConfidentialityLevel` field: Public, Restricted, Confidential. Item-level permission synchronization is authored but may not be enabled in every pilot environment.

## 8. SLA Configuration And Monitoring

Priority is derived from Impact and Urgency. The **Priority Matrix** list defines:

- Impact
- Urgency
- Priority
- ResponseHours
- ResolutionHours

Operational guidance:

- Keep the matrix small and stable.
- Review SLA Warning and Breached tickets daily during pilot.
- Use list views for `SlaStatus=Warning` and `SlaStatus=Breached`.
- Treat On Hold as a pause only when a valid hold reason exists.
- Confirm `ClosedDate`, `ResolvedDate`, and `MadeSla` are populated during closure.

## 9. Kill Switch

The global kill switch is stored in the **Config** list.

To pause new privileged writes:

1. Open `/sites/ITSM/Lists/Config`.
2. Edit the row where `Key=KillSwitch`.
3. Set `Value=true`.
4. Add a clear `ChangeReason`.
5. Save.

The Dispatcher checks this setting before dispatching jobs and returns a `503` kill-switch response when active.

Return `Value=false` when pilot testing can resume.
