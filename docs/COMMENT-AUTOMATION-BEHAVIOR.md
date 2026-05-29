# Comment Automation Behavior

This guide explains what happens when someone adds a comment or work note to an ITSM ticket. It is written for IT staff and end users.

The short version: comments keep people informed, and in two specific cases they also move the ticket back into active work.

## What Counts as a Comment

**Comments** are messages intended for the caller and IT staff. End users can use comments to answer questions, add information, or say that a resolved issue is not fixed.

**Work notes** are internal IT notes. They are for handovers, investigation notes, and operational updates that should stay within the IT team.

## When Comments Trigger Automation

| Ticket situation | What the comment means | What happens next |
|---|---|---|
| Awaiting Caller | The caller has replied with the information IT was waiting for. | The ticket resumes and returns to the active helpdesk queue. IT staff are notified. |
| In Progress | Someone has added more information while IT is already working on the ticket. | The ticket stays In Progress. Relevant people are notified. |
| Resolved | The caller is saying the issue still needs attention or has a follow-up question. | The ticket reopens for IT review. IT staff are notified. |
| Work Notes | IT has added an internal update. | IT followers are notified. The caller is not notified, and the ticket status does not change. |

## Awaiting Caller

When IT needs more information, the ticket may be set to Awaiting Caller.

If the caller adds a comment, the system treats that as a reply. The ticket moves back into active handling so IT can continue work. The caller does not need to open a new ticket or separately ask for the ticket to resume.

## In Progress

When a ticket is In Progress, IT is already working on it.

New comments are treated as updates. They notify the right people, but they do not change the ticket status. This keeps the ticket with the current owner while still making sure new information is seen.

## Resolved

When a ticket is Resolved, IT believes the issue is fixed.

If the caller adds a comment after resolution, the system treats that as a sign that the issue may still need attention. The ticket reopens for IT review. The caller does not need to create a duplicate ticket.

## Work Notes

Work notes are internal to IT.

Adding a work note sends an update to IT followers only. It does not notify the caller, resume an Awaiting Caller ticket, or reopen a Resolved ticket.

## Practical Guidance

For end users:

- Reply in the ticket comments when IT asks for more information.
- Comment on a resolved ticket if the issue is not actually fixed.
- Create a new ticket only when the request is about a different issue.

For IT staff:

- Use comments for updates the caller should see.
- Use work notes for internal investigation, handover, and support context.
- Set tickets to Awaiting Caller only when the next action is with the caller.
- Resolve tickets when work is complete and ready for caller confirmation.
