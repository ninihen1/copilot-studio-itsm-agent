# tickets-perm-sync flow

Implements the item-level permissions pattern decided 2026-04-29. When a Tickets row's `ConfidentialityLevel` changes (or a new row is created), this flow brings the item's permissions in line with the level.

## Trigger

SharePoint webhook on Tickets list — fires on create or modify. Filters internally by `ConfidentialityLevel` value.

## Logic by level

| Level | Action |
|---|---|
| `Public` | Restore inheritance from list. No unique scope. |
| `Restricted` | Break inheritance, grant Caller + AssignedTo Read role. List owners retain access via Full Control role inherited from site. |
| `Confidential` | (TODO — placeholder) Same as Restricted plus explicit AuthorizedReaders. Pilot tickets default to Public; vast majority of sensitive cases work as Restricted. Confidential implementation deferred to phase 2 unless usage data shows demand. |

The flow always stamps `PermSyncedAt` on completion so drift detection has a timestamp to query.

## Why webhook, not "On modified"

Power Automate's `When item created or modified` connector trigger fires on EVERY field change. We don't want to rebuild perms on each work-note edit. A webhook + filter inside the flow gives us a single re-run only when ConfidentialityLevel actually changes.

In practice the webhook fires on every modify, and the flow checks `ConfidentialityLevel` on each fire. The cost is low (one SP read per flow run); the simplicity is high.

## Authentication note

The flow uses the SharePoint REST API (`_api/web/lists/.../items(...)/breakroleinheritance`) for permission ops because the connector doesn't expose them. This requires the connection's identity to have **Manage Permissions** on the Tickets list. Use a service account in the SP group `IT-ITSM-Admins`, NOT Catherine's account.

## Pilot week 1 deliverable

This flow is provisioned as part of Week 1, alongside the SharePoint lists. Without it, the ConfidentialityLevel column does nothing visible.

## Connections required

- `shared_sharepointonline` — service account in IT-ITSM-Admins with Manage Permissions on Tickets

## Parameters

- `ItsmSiteUrl` — full URL of `/sites/ITSM`
