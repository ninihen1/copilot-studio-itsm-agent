# SharePoint Permission Group Definitions - ITSM Pilot

Scope: `https://contoso.sharepoint.com/sites/ITSM`  
Status: readiness definition  
Applies to: SharePoint site groups, list permissions, and item-level permission sync design

## Goals

- Keep end users away from privileged audit and execution lists.
- Let users submit and read their own tickets through supported UX paths.
- Let service desk staff triage and update operational records without tenant admin rights.
- Let approvers approve without exposing executor internals.
- Keep configuration and provisioning-job audit data admin-only.

## Groups

Use these SharePoint site groups for the pilot. Names intentionally avoid personal accounts and can later be mapped to Entra security groups.

| Group | Purpose | Initial members | SharePoint permission level |
|---|---|---|---|
| `ITSM-Admins` | Full ITSM site and list administration | Site owner plus a named backup/admin custodian | Full Control |
| `ITSM-ServiceDesk` | Helpdesk agents who triage, update, resolve, and manage ticket queues | L1/L2 service desk staff and IT automation operators | Contribute or Edit depending on list |
| `ITSM-Approvers` | Managers, IT owners, CAB members, and backup approvers who action approvals | Helpdesk leads, managers, IT owners, CAB members, HR partners as needed | Read on request/ticket context, Contribute on approval decision lists |
| `ITSM-Users` | Pilot employees who submit tickets, browse catalog, and read published KB | All pilot users or all employees | Read on reference/KB/catalog lists; no direct access to privileged lists |

> **Note — two similarly named things.** `ITSM-ServiceDesk` above is a SharePoint site permission group. Separately, a Microsoft 365 group named **ITSM Service Desk** is the out-of-catalog hand-off *fulfilment queue* — the target the validation flow routes unfulfillable requests to. Its members work those requests from the portal's **Service desk** page (Mark fulfilled / Decline closes the RITM and resolves the ticket). Keep the two distinct: the site group controls list access; the M365 group is the routing/queue target.

Optional specialized groups when the pilot matures:

| Group | Purpose | Use when |
|---|---|---|
| `ITSM-KB-Authors` | Create and maintain Knowledge Base articles | KB ownership is separated from service desk operations |
| `ITSM-CAB` | Change Advisory Board approvers | Change records get CAB-specific approval stages |
| `ITSM-HR-Approvers` | HR confirmation for onboarding/offboarding | HR-sensitive catalog items go live |
| `ITSM-Automation-Operators` | Operators allowed to inspect/re-drive failed provisioning jobs | Production support split from general service desk |

## Site-Level Permissions

| Group | Site-level permission | Notes |
|---|---|---|
| `ITSM-Admins` | Full Control | Owns site settings, list schema, app pages, permissions, and emergency fixes. |
| `ITSM-ServiceDesk` | Edit | Can operate ticket queues and maintain non-sensitive reference data where explicitly granted. |
| `ITSM-Approvers` | Read | Approval lists grant additional Contribute where needed. |
| `ITSM-Users` | Read | User writes should happen through forms/flows, not broad direct list edit rights. |

## List Permission Matrix

Break inheritance on sensitive lists. Keep inheritance on low-risk read-only reference lists if site-level permissions already match the matrix.

| List | ITSM-Admins | ITSM-ServiceDesk | ITSM-Approvers | ITSM-Users | Notes |
|---|---|---|---|---|---|
| Tickets | Full Control | Edit | Read relevant rows | Read relevant rows / submit through UX | Item-level permission sync should enforce caller and confidentiality access. |
| Tickets-Archive | Full Control | Read | No access by default | No access | Archive is operational/audit data, not user-facing. |
| Request Items | Full Control | Edit | Read relevant approval context | Read own rows | Request Item = RITM. User access should be scoped by requester. |
| Tasks | Full Control | Edit | Read if needed for approval context | No direct access by default | SCTASKs are operational fulfillment tasks. |
| Provisioning Jobs | Full Control | Read or Edit only for automation operators | No access | No access | Contains privileged action audit and target JSON. |
| Catalog Demand | Full Control | Edit | No access | No access | Out-of-catalog demand log (requester UPNs, RITM refs, DemandStatus). Written by RITM-Validation-Triage; ServiceDesk triages it to decide what to onboard. |
| Approvals | Full Control | Read | Contribute/Edit own assigned approvals | No direct access | Approval UX should filter to assigned approver. |
| Approval Stages | Full Control | Read | Contribute/Edit assigned stage decisions | No access | Stage decisions are not general helpdesk data. |
| Approval Policies | Full Control | Read | Read | No access | Policies affect authorization behavior. |
| JobTypes | Full Control | Read | Read | Read | Users/agents can read allowed automation catalog; only admins edit. |
| License Costs | Full Control | Read | Read | No access | Per-SKU pricing reference read by the License Lookup flow; not user-facing. |
| Config | Full Control | No access unless automation operator | No access | No access | Kill switch and global toggles. Break inheritance. |
| Knowledge Base | Full Control | Edit | Read | Read | If `ITSM-KB-Authors` exists, give it Edit and reduce ServiceDesk to Contribute/Read. |
| Categories | Full Control | Edit | Read | Read | Reference taxonomy. |
| Subcategories | Full Control | Edit | Read | Read | Reference taxonomy. |
| Service Catalog | Full Control | Edit | Read | Read | Users browse; admins/service desk maintain catalog metadata. |
| Priority Matrix | Full Control | Read | Read | Read | Priority/SLA policy should be admin-edited only. |
| Configuration Items | Full Control | Edit or Read | Read | Read limited | Consider hiding sensitive CI fields before broad user read. |
| Assets | Full Control | Edit or Read | Read | Read limited | Physical/licensed inventory; consider hiding sensitive fields before broad user read. |
| Categories-Routing | Full Control | Edit | No access | No access | Routing rules are operational configuration. |
| Watchers | Full Control | Edit | Read relevant rows | Contribute own subscriptions | Use item-level scoping for watchers. |

## Confidentiality Model

The `Tickets` list has `ConfidentialityLevel` values:

- `Public`
- `Restricted`
- `Confidential`

Recommended access behavior:

| Confidentiality | Reader set | Editor set |
|---|---|---|
| Public | Caller, watchers, `ITSM-ServiceDesk`, `ITSM-Admins` | `ITSM-ServiceDesk`, `ITSM-Admins`, owning automation flows |
| Restricted | Caller, assigned service desk, explicit authorized readers, `ITSM-Admins` | Assigned service desk, `ITSM-Admins` |
| Confidential | Explicit authorized readers, named assigned service desk, `ITSM-Admins` | `ITSM-Admins` and named assigned service desk only |

Do not rely only on views for confidentiality. Views are filtering convenience, not security. The permission sync flow should break inheritance for restricted/confidential rows and grant explicit access.

## Permission Setup Order

1. Create SharePoint groups at `/sites/ITSM/_layouts/15/people.aspx`.
2. Add initial members or Entra security groups.
3. Apply site-level baseline permissions.
4. Break inheritance on sensitive lists.
5. Apply the list matrix above.
6. Run a permission smoke test for one member of each group.
7. Enable or validate item-level permission sync for `Tickets`.

## Smoke Tests

| Test | Expected result |
|---|---|
| ITSM-Users member opens Knowledge Base | Can read published articles. |
| ITSM-Users member opens Provisioning Jobs | Access denied. |
| ITSM-ServiceDesk member opens ticket queue | Can edit tickets and tasks. |
| ITSM-Approvers member opens Approvals | Can update assigned approval rows only through supported UI/list permissions. |
| ITSM-Admins member opens Config | Can edit kill switch and configuration rows. |
| Non-member opens ITSM site | Access denied unless site is intentionally exposed tenant-wide. |

## Decisions To Confirm

- Whether `ITSM-Users` maps to all employees or only a pilot subset.
- Whether service desk can edit Knowledge Base directly or KB authoring gets its own `ITSM-KB-Authors` group.
- Whether approvers should get direct SharePoint list access or only approve via Power Automate approval cards.
- Whether archived tickets need any non-admin read access for reporting.
- Whether the Service desk hand-off page is restricted to the `ITSM Service Desk` M365 group or also open to `ITSM-ServiceDesk` site-group members.
