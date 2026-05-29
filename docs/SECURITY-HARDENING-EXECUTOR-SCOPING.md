# Executor Security Hardening Guide

Scope: Day 4 recommendations for the six ITSM executor service principals  
Principle: AI proposes, humans approve, scoped service principals execute

## Current Executor Identities

| Executor | Service principal | AppId | JobType prefix |
|---|---|---|---|
| Identity | `SP-IT-Identity` | `00000000-0000-4000-8000-000000000014` | `identity.*` |
| Groups | `SP-IT-Groups` | `00000000-0000-4000-8000-000000000055` | `groups.*` |
| Licensing | `SP-IT-Licensing` | `00000000-0000-4000-8000-000000000025` | `licensing.*` |
| Exchange | `SP-IT-Exchange` | `00000000-0000-4000-8000-000000000058` | `exchange.*` |
| SharePoint | `SP-IT-SharePoint` | `00000000-0000-4000-8000-000000000046` | `sharepoint.*` |
| Teams | `SP-IT-Teams` | `00000000-0000-4000-8000-000000000013` | `teams.*` |

## Hardening Targets

| Area | Pilot posture | Target posture |
|---|---|---|
| SharePoint executor | Broad SharePoint permission may be present during pilot | `Sites.Selected` with explicit per-site grants |
| Teams executor | Broad Teams Administrator role may be present during pilot | Narrow Graph app permissions plus per-team ownership where viable |
| Exchange executor | EXO Function wrapper performs mailbox permission changes | Cert-based EXO app-only auth with explicit Exchange RBAC assignment |
| Dispatcher to executor | SharePoint polling and PJ status transition | Service Bus topic with per-executor subscription and lock handling |
| Secret model | Client secrets in Key Vault for pilot SPs | Certificate credentials, rotation calendar, and break-glass owner |

## SharePoint Executor: Sites.Selected Pattern

Target: `SP-IT-SharePoint` should not hold broad tenant-wide SharePoint access unless a job type explicitly requires it and Catherine accepts the risk.

Recommended permissions:

| Permission | Use |
|---|---|
| `Sites.Selected` | Required baseline for selected-site app-only access. |
| Per-site `read` grant | Read site/list/file metadata. |
| Per-site `write` grant | Restore files and update list/library metadata. |
| Per-site `manage` or `fullcontrol` grant | Only if the job type must manage permissions on that site. |

Initial selected sites:

| Site | Recommended grant | Rationale |
|---|---|---|
| `https://contoso.sharepoint.com/sites/ITSM` | `write` or `manage` | ITSM system of record and pilot file restore target. |
| Other managed IT sites | Confirm with Catherine | Add only after a catalog item or executor job type needs it. |

Implementation notes:

- Maintain a controlled `ManagedSharePointSites` config source with `siteUrl`, `siteId`, `grantLevel`, `owner`, and `expiry/reviewDate`.
- Validate the requested `siteUrl` from `ArgsJson` is in the managed-site allow-list before any SharePoint executor call.
- Reject or route to human review if a request targets a site without an explicit grant.
- For restore jobs, pre-check that the recycle bin item belongs to the approved site before calling restore.

Grant example shape:

```http
POST https://graph.microsoft.com/v1.0/sites/{site-id}/permissions
Content-Type: application/json

{
  "roles": ["write"],
  "grantedToIdentities": [
    {
      "application": {
        "id": "00000000-0000-4000-8000-000000000046",
        "displayName": "SP-IT-SharePoint"
      }
    }
  ]
}
```

Decision for Catherine:

- Is `SP-IT-SharePoint` allowed to operate only on `/sites/ITSM` for Slice 1, or should it also cover selected business sites?
- Does `sharepoint.restoreFile` need permission-management capability, or only file restore/write?

## Teams Executor: Narrow Permission Model

Target: remove tenant-wide Teams Administrator role if the current job types can be served by narrower app permissions and per-team controls.

Current job types:

- `teams.createChannel`
- `teams.addChannelMember`

Recommended pattern:

| Job type | Preferred scope | Precondition |
|---|---|---|
| `teams.createChannel` | Graph channel create permission plus team-scoped ownership where possible | Target team must be on allow-list and have an owner approval. |
| `teams.addChannelMember` | Graph channel/team membership permission plus team allow-list | User and team/channel must be validated before write. |

Hardening controls:

- Maintain a `ManagedTeams` allow-list with `teamId`, `displayName`, `ownerUpn`, `allowedJobTypes`, and `approvalPolicy`.
- Do not allow arbitrary `teamId` from agent output to pass directly to Graph.
- Require owner or manager approval for private/shared channel membership changes.
- Log every target `teamId`, `channelId`, and `userId` to the Provisioning Job audit row.
- Prefer team-level ownership or resource-specific consent patterns where they meet the job requirement; keep Teams Administrator only as a temporary pilot exception.

Decision for Catherine:

- Which Teams are in scope for automated channel creation?
- Are private/shared channels allowed in pilot automation, or standard channels only?
- Can `SP-IT-Teams` be made owner of managed Teams instead of holding broad admin role?

## Groups Executor

Target: constrain group operations to allowed groups.

Recommended controls:

- Add `ManagedGroups` config/list with `groupId`, `displayName`, `ownerUpn`, `allowedActions`, and `requiresOwnerApproval`.
- Pre-check target group is in allow-list.
- For highly privileged groups, require a stricter approval policy or force human fulfillment.
- Avoid broad dynamic rule edits in the same executor unless separately scoped and approved.

## Licensing Executor

Target: constrain license assignment to approved SKUs and avoid accidental cost expansion.

Recommended controls:

- Maintain `AllowedLicenseSkus` with SKU ID, product name, cost center, approval policy, and available seat threshold.
- Pre-check available seats before assignment.
- Require approval for high-cost SKUs or low remaining seat counts.
- Revoke only the SKU requested, not every assigned SKU.

## Exchange Executor

Target: keep mailbox permission changes behind the EXO Function wrapper with explicit Exchange RBAC.

Recommended controls:

- Use certificate-based app-only EXO auth.
- Assign only the Exchange role needed for mailbox permission management.
- Validate mailbox and delegate identities before invoking the Function.
- Require mailbox owner approval except for break-glass or offboarding policy flows.
- Keep Function key in Key Vault and rotate it; do not embed it in flow definitions.

## Identity Executor

Target: keep high-risk identity actions constrained by job type and directory role.

Recommended controls:

- Keep `SP-IT-Identity` in Password Administrator only for password/MFA flows where possible.
- Do not grant Global Administrator.
- Separate user lifecycle creation/disablement into a higher approval tier than password reset.
- Validate target UPN belongs to the tenant and is not a protected admin account.
- Block automation against break-glass accounts and privileged role holders unless explicitly approved by `ITSM-Admins`.

## Required Operational Guardrails

| Guardrail | Requirement |
|---|---|
| JobType allow-list | Executor must reject any job type outside its prefix. |
| Target allow-list | SharePoint sites, Teams, and Groups must be checked against managed allow-lists. |
| Approval policy | High-risk targets or operations must map to stricter approval policies. |
| Kill switch | Dispatcher and any dispatcher-bypassing bridges must check kill switch before privileged writes. |
| App Insights | Every privileged call should log target, job type, service principal, status, and correlation ID. |
| Rotation | All executor credentials need owner, expiry, and rotation reminder. |

## Priority Implementation Order

1. Add allow-list checks for SharePoint sites, Teams, and Groups.
2. Move `SP-IT-SharePoint` to `Sites.Selected` and grant only `/sites/ITSM`.
3. Remove or reduce Teams Administrator dependency after validating `teams.createChannel` and `teams.addChannelMember`.
4. Add protected-account checks to Identity executor.
5. Add license SKU/cost guardrails.
6. Convert pilot client secrets to certificate credentials with rotation tracking.
