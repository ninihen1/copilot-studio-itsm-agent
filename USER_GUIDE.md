# ITSM Level 1 Pilot User Guide

**Audience:** pilot users, managers, and Level 1 service desk staff  
**System:** Copilot Studio ITSM on Microsoft 365  
**Pilot tenant:** `https://contoso.sharepoint.com/sites/ITSM` *(`contoso` is a placeholder for your own tenant — the pilot itself ran in a private Microsoft 365 demo tenant)*

This guide explains how users submit IT requests, how the Helpdesk Triage Agent responds, how approvals work, and how to track a ticket through the Level 1 pilot.

Support staff and ITSM admins should also read [`ADMIN_GUIDE.md`](ADMIN_GUIDE.md) for catalog, SLA, permissions, archival, major incident, and kill-switch operations.

## 1. What The ITSM Pilot Does

The ITSM pilot gives users a self-service IT help desk backed by SharePoint, Power Automate, and Copilot Studio. Users submit a ticket through the ITSM Service Portal; behind the scenes a Power Automate flow calls the Helpdesk Triage Agent to classify and triage it.

Users can:

- Submit incidents and service requests through the portal.
- Get a fast knowledge-base answer when the agent can resolve the issue.
- Answer the agent's follow-up questions on an approval card when it needs more detail, so the request keeps moving instead of dead-ending.
- Approve request items when they are the assigned approver.
- View ticket and request status in SharePoint, each tagged with a ticket number.

The agent classifies and proposes work, but it does not chat with users directly, and it never performs privileged IT changes itself. Actions such as password resets, group membership changes, license assignment, mailbox access, Teams changes, and SharePoint restore work go through approval and executor flows. When a request can't be automated it's handed to the IT service desk rather than dropped, and if a change fails the ticket is closed honestly — not marked resolved — and you're told.

## 2. Submitting A Ticket

### Choosing Incident Or Request

Use **Incident** when something is broken or degraded, such as an outage, access failure, device problem, or application error.

Use **Request** when you are asking IT to provide something, such as access to a group, a license, shared mailbox permission, software, onboarding, or offboarding.

You choose the ticket type when you submit. Just after the ticket is saved, the **ITSM-Ticket-Type-Validator** flow checks the type against the chosen category and subcategory: if they map to an active Service Catalog item it routes the ticket down the **Request** path; otherwise the ticket stays an **Incident** for triage. (A portal prompt that recommends the type *before* you submit is planned, not yet enabled.)

### Submit From the Service Portal

The portal writes directly to the **Tickets** SharePoint list. The submit flow is:

1. Choose **Incident** or **Request**.
2. Enter a short description and details.
3. Choose category, subcategory, impact, and urgency.
4. Submit.

For a **license request**, pick from the dropdown of licenses your organisation already owns, or choose *Other (not listed)* and name what you need. Either way the request arrives as structured detail the system can validate quickly.

After submission, the Ticket-Type-Validator flow runs and the ticket continues into triage; downstream automation then creates RITMs, triage records, or major incident links as appropriate.

### Other Intake Channels

For the Level 1 pilot, the **ITSM Service Portal is the only way to raise a ticket.** There is no email-to-ticket or Teams-to-ticket intake — sending an email or a Teams message does **not** create a ticket. (Email ingestion is a possible future channel; it is not built for this pilot.)

## 3. How The Triage Agent Handles A Ticket

The Helpdesk Triage Agent classifies each submitted ticket before routing it. It will try to identify:

- Ticket type: Incident or Request (the Level 1 pilot handles these two; Change and Problem are out of pilot scope).
- Category and subcategory.
- Impact and urgency.
- Affected configuration item, service, app, user, or group.
- Whether a knowledge article can resolve the issue.
- Whether the request maps to an automated fulfilment action.

When triage is uncertain, the agent does not guess. It puts the request on hold and sends you an **approval card** with its questions. Answer in the card and validation runs again automatically — you can go back and forth over a few rounds until it has what it needs — or click **Cancel** and the request closes cleanly. This happens when:

- The target user is ambiguous.
- Multiple systems or services match the request.
- The action affects more than one person.
- The request appears high-risk.
- The confidence score is low.

This clarification works the same on the catalog/request path (`RITM-Validation-Triage`) and on form tickets (`Triage-Orchestrator`).

For knowledge-base issues, the agent deflects: it resolves and closes the ticket with the relevant KB article attached, and no automation job is created.

When a request can't be matched to anything the automation can do, the agent hands it to the **IT service desk** instead of dead-ending. The request goes on hold against the service desk queue, you're told it was received and passed on, and a fulfiller picks it up from the portal's **Service desk** page. You're notified again once it's closed.

## 4. Approving Request Items

Some requests create a Request Item, also called a **RITM**, that requires approval before work starts.

In the Level 1 pilot:

- The RITM approval flow sends an approval request to the requested user's manager when manager approval is configured.
- The pilot approval bridge can also use the **Approvals** SharePoint list for manual approval-state changes.
- Production-grade multi-stage approval policies are designed but not fully enabled for the pilot.

### Approve From Teams Or Email

1. Open the approval card.
2. Review the request summary, requested user, risk, and business justification.
3. Select **Approve** or **Reject**.
4. Add a rejection reason if rejecting.

After approval:

- The RITM moves from **Pending Approval** to **Approved**.
- Catalog tasks, or **SCTASKs**, are created.
- Automated SCTASKs create Provisioning Jobs.
- Executor flows perform approved work and update audit fields.

After rejection:

- The RITM is marked **Closed Incomplete** or the linked Provisioning Job is marked **Rejected**.
- No privileged action is executed.

### Approve From SharePoint In Pilot Testing

Admins may test approval by editing the **Approvals** list:

1. Open `/sites/ITSM/Lists/Approvals`.
2. Find the approval session linked to the ticket or job.
3. Set **State** to `Approved` or `Rejected`.
4. Save.

Use a user identity for pilot testing. Power Automate SharePoint polling triggers can skip rows created or edited by app-only identities.

## 5. Viewing Ticket Status

Users and service desk staff can view tickets in SharePoint if they have access:

1. Open the ITSM SharePoint site.
2. Open the **Tickets** list.
3. Search by ticket number, short description, caller, status, or assigned person.
4. Open the ticket row to view status, comments, work notes, priority, SLA fields, and resolution notes.

Every portal page shows the ticket number (for example `Ticket #142`), and the detail view, Service desk queue, and approval cards show the ticket and request numbers together (`Ticket #142 · RITM #77`). Quote these when you follow up. When a request finishes you get a plain-English message — "your request is done" or "it couldn't be completed" — with those numbers and a link.

Common ticket statuses:

| Status | Meaning |
|---|---|
| New | Ticket has been created and is awaiting triage or assignment. |
| In Progress | IT is actively working the ticket. |
| On Hold | Waiting on your clarification answer, the IT service desk hand-off queue, a vendor, a change, or another dependency. |
| Resolved | Work is complete and resolution notes have been added. |
| Closed | Finalized — either resolved, or closed because the work couldn't be completed or a hand-off was declined. |
| Cancelled | Ticket was withdrawn or not needed. |

Requests only enter the catalog fulfillment path when the ticket type is **Request** and the selected subcategory maps to an active Service Catalog item. Incidents enter triage and incident-management paths.

For service requests, users may also see:

| Record | Meaning |
|---|---|
| Request | The parent ticket submitted by the user. |
| RITM | A request item created from a catalog item. |
| SCTASK | A worker task under the RITM. One RITM can have one or many tasks. |
| Provisioning Job | Audit row for an approved privileged write. Visible to admins, not general users. |

## 6. Ticket Lifecycle

The Level 1 pilot supports both break/fix incidents and service catalog requests.

### Incident Lifecycle

```text
User reports issue
  -> Ticket created
  -> Triage Agent classifies category, impact, urgency, and priority
  -> Service desk investigates or routes
  -> Ticket moves to In Progress
  -> Ticket is Resolved with close code and close notes
  -> Ticket is Closed
```

### Request Lifecycle

```text
Request ticket
  -> RITM created from Service Catalog item
  -> RITM Pending Approval
  -> Manager or approver approves
  -> SCTASKs created
  -> Automated SCTASKs create Provisioning Jobs
  -> Dispatcher validates and dispatches the job
  -> Executor performs approved work
  -> SCTASK closes
  -> RITM closes when all SCTASKs close
  -> Request ticket resolves when all RITMs close
```

If an executor can't complete the work, the job is marked failed: the ticket is **closed** (not resolved), you're told it couldn't be completed, and the service desk is alerted to follow up.

### Hand-off (a request the automation can't fulfil)

```text
Request the automation can't fulfil
  -> RITM put On Hold against the IT Service Desk queue
  -> Logged to the Catalog Demand list
  -> Requester told it was received and passed to the service desk
  -> Fulfiller marks it fulfilled or declines on the Service desk page
  -> RITM closes and the ticket resolves
  -> Requester notified the request is closed
```

### Example: Password Reset

```text
User: Submits a ticket — "I forgot my password."
Flow: Fires on the new ticket and calls the Triage Agent.
Agent: Classifies as Request > Account & Access > Password Reset, and maps it to the action identity.resetPassword.
System: Creates Request and RITM for Password Reset.
Approver: Approves the RITM or linked job.
System: Creates SCTASK and Provisioning Job with jobType identity.resetPassword.
Dispatcher: Marks the job Dispatched.
Identity Executor: Calls Microsoft Graph and resets the password.
System: Marks job Succeeded, closes SCTASK, closes RITM, resolves ticket, and tells the requester it's done. (Had the reset failed, the ticket would be closed — not resolved — the requester told it couldn't be completed, and the service desk alerted.)
```

## 7. Screenshots To Capture For Pilot Training

Capture these screenshots from the pilot environment for rollout material:

| Screenshot | Purpose |
|---|---|
| Service Portal submit form | Shows how users start a request. |
| Clarification approval card in Teams | Shows the agent asking for more detail; the user answers in the card and it re-validates. |
| Service desk hand-off queue page | Shows where fulfillers work requests the automation couldn't handle. |
| SharePoint Tickets list filtered to "My Tickets" | Shows status tracking. |
| Approval card in Teams or email | Shows manager approval flow. |
| Request Items list showing RITM state | Shows request lifecycle. |
| Tasks list showing SCTASKs | Shows fulfillment tasks. |
| Resolved ticket with close notes | Shows closure and audit trail. |
| "Couldn't be completed" notification | Shows the honest-failure message a requester gets when a job fails. |
| Ticket #N and Ticket #N · RITM #N identifiers | Shows the trackable numbers across portal pages. |

Use real pilot screenshots only after removing personal data, passwords, access tokens, Graph request IDs if not needed, and any sensitive user details.

## 8. Good Ticket Descriptions

Good descriptions help the agent classify faster.

Include:

- What you were trying to do.
- What happened instead.
- When it started.
- Whether other people are affected.
- The application, device, file, site, group, mailbox, or service involved.
- Business deadline or impact.

Avoid:

- Sending passwords or secrets.
- Asking for bulk changes affecting more than five users.
- Requesting access without business justification.
- Asking the agent to bypass approval.
