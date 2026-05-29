# ITSM Level 1 Pilot User Guide

**Audience:** pilot users, managers, and Level 1 service desk staff  
**System:** Copilot Studio ITSM on Microsoft 365  
**Pilot tenant:** `https://contoso.sharepoint.com/sites/ITSM`

This guide explains how users submit IT requests, how the Helpdesk Triage Agent responds, how approvals work, and how to track a ticket through the Level 1 pilot.

Support staff and ITSM admins should also read [`ADMIN_GUIDE.md`](ADMIN_GUIDE.md) for catalog, SLA, permissions, archival, major incident, and kill-switch operations.

## 1. What The ITSM Pilot Does

The ITSM pilot gives users a self-service IT help desk backed by SharePoint, Power Automate, and Copilot Studio. Users submit a ticket through the ITSM Service Portal; behind the scenes a Power Automate flow calls the Helpdesk Triage Agent to classify and triage it.

Users can:

- Submit incidents and service requests through the portal.
- Get a fast knowledge-base answer when the agent can resolve the issue.
- Approve request items when they are the assigned approver.
- View ticket and request status in SharePoint.

The agent classifies and proposes work, but it does not chat with users directly, and it never performs privileged IT changes itself. Actions such as password resets, group membership changes, license assignment, mailbox access, Teams changes, and SharePoint restore work go through approval and executor flows.

## 2. Submitting A Ticket

### Choosing Incident Or Request

Use **Incident** when something is broken or degraded, such as an outage, access failure, device problem, or application error.

Use **Request** when you are asking IT to provide something, such as access to a group, a license, shared mailbox permission, software, onboarding, or offboarding.

The SharePoint portal submit experience should ask for the ticket type before the ticket is saved. If the chosen category and subcategory map to a Service Catalog item, the portal should recommend **Request** and ask you to confirm before submission. If you choose **Request** but the selected subcategory does not map to an active catalog item, the portal should ask you to choose a valid catalog item or submit the item as an Incident for triage.

### Submit From the Service Portal

The portal writes directly to the **Tickets** SharePoint list. The expected submit flow is:

1. Choose **Incident** or **Request**.
2. Enter a short description and details.
3. Choose category, subcategory, impact, and urgency.
4. Review any type recommendation shown by the portal.
5. Confirm the final ticket type before submitting.

After submission, the ticket should be marked for ticket-type validation before downstream automation creates RITMs, triage proposals, or major incident links.

### Submit From Email

Email-to-ticket ingestion is a planned intake channel. For the current Level 1 pilot, Teams and SharePoint-backed intake are the supported paths.

If your team has enabled a mailbox-to-ticket flow after pilot deployment, use the published helpdesk mailbox and include:

- Short description in the subject.
- Full details in the email body.
- Affected user, device, application, or service.
- Business impact and urgency.
- Any screenshots as attachments.

The email flow should normalize the message into a row in the **Tickets** SharePoint list.

## 3. How The Triage Agent Handles A Ticket

The Helpdesk Triage Agent classifies each submitted ticket before routing it. It will try to identify:

- Ticket type: Incident, Request, Change, or Problem.
- Category and subcategory.
- Impact and urgency.
- Affected configuration item, service, app, user, or group.
- Whether a knowledge article can resolve the issue.
- Whether an automated action can be proposed.

When triage is uncertain, the agent does not guess. It marks the ticket **On Hold (Awaiting Caller)** and asks — through the ticket — for the missing detail, then triage runs again when the caller responds. This happens when:

- The target user is ambiguous.
- Multiple systems or services match the request.
- The action affects more than one person.
- The request appears high-risk.
- The confidence score is low.

For knowledge-base issues, the agent deflects: it resolves and closes the ticket with the relevant KB article attached, and no automation job is created.

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

Common ticket statuses:

| Status | Meaning |
|---|---|
| New | Ticket has been created and is awaiting triage or assignment. |
| In Progress | IT is actively working the ticket. |
| On Hold | The ticket is waiting on the caller, a vendor, a change, or another dependency. |
| Resolved | Work is complete and resolution notes have been added. |
| Closed | Ticket is finalized and ready for archival later. |
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

### Example: Password Reset

```text
User: Submits a ticket — "I forgot my password."
Flow: Fires on the new ticket and calls the Triage Agent.
Agent: Classifies as Request > Account & Access > Password Reset; proposes identity.resetPassword.
System: Creates Request and RITM for Password Reset.
Approver: Approves the RITM or linked job.
System: Creates SCTASK and Provisioning Job with jobType identity.resetPassword.
Dispatcher: Marks the job Dispatched.
Identity Executor: Calls Microsoft Graph and resets the password.
System: Marks job Succeeded, closes SCTASK, closes RITM, resolves ticket.
```

## 7. Screenshots To Capture For Pilot Training

Capture these screenshots from the pilot environment for rollout material:

| Screenshot | Purpose |
|---|---|
| Service Portal submit form | Shows how users start a request. |
| Ticket On Hold / Awaiting Caller | Shows how the agent asks for more detail when triage is uncertain. |
| SharePoint Tickets list filtered to "My Tickets" | Shows status tracking. |
| Approval card in Teams or email | Shows manager approval flow. |
| Request Items list showing RITM state | Shows request lifecycle. |
| Tasks list showing SCTASKs | Shows fulfillment tasks. |
| Resolved ticket with close notes | Shows closure and audit trail. |

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
