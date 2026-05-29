# SharePoint Infrastructure

PnP PowerShell-based provisioning for the ITSM solution. Idempotent — re-runs are safe and treated as no-ops where state already matches.

## Prerequisites

1. **PnP.PowerShell module** (≥ 2.4.0)
   ```powershell
   Install-Module -Name PnP.PowerShell -Scope CurrentUser
   ```
2. **Cert-based authentication** to SharePoint Online. Create an Entra app registration `SP-IT-Provisioning` with `Sites.FullControl.All` (application). Grant admin consent. Upload public key cert; private key in `kv-itsm-{env}` Key Vault.
3. **Pilot site** — `https://{tenant}.sharepoint.com/sites/ITSM` must already exist. Create via SharePoint Admin Center as a **Team site (no Microsoft 365 group)** for cleanest permissions.

## Files

| File | Purpose |
|---|---|
| `provision-lists.ps1` | Master orchestrator. Runs all per-list scripts in dependency order. |
| `lists/_helpers.ps1` | Shared idempotent functions: `Ensure-PnPList`, `Ensure-PnPField`, `Ensure-PnPIndex`, etc. |
| `lists/01-categories.ps1` | Categories list (provisioned first — referenced by others) |
| `lists/02-configuration-items.ps1` | CMDB |
| `lists/03-assets.ps1` | Asset Management |
| `lists/04-knowledge-base.ps1` | KB articles |
| `lists/05-service-catalog.ps1` | Orderable items |
| `lists/06-priority-matrix.ps1` | 9-row Impact×Urgency matrix |
| `lists/07-approval-policies.ps1` | Approval policy definitions |
| `lists/08-job-types.ps1` | Job type registry (for dispatcher) |
| `lists/09-config.ps1` | Kill switch + system config |
| `lists/10-tickets.ps1` | Master tickets list (depends on Categories + CIs + Priority Matrix) |
| `lists/11-tickets-archive.ps1` | Archive list (mirrors Tickets schema; receives Closed tickets > 12 months) |
| `lists/12-request-items.ps1` | RITM children |
| `lists/13-tasks.ps1` | SCTASK fulfillment work units |
| `lists/14-approvals.ps1` | Approval audit (per-stage rows) |
| `lists/15-approval-stages.ps1` | Per-stage decision audit |
| `lists/16-provisioning-jobs.ps1` | Audit row per privileged write |
| `grant-sites-selected.ps1` | Grants SP-IT-SharePoint app `fullcontrol` on `sites/ITSM` |
| `seed-priority-matrix.ps1` | Loads the 9 Impact×Urgency rows |
| `seed-approval-policies.ps1` | Loads the 6 seed policies (no auto-approve) |
| `seed-job-types.ps1` | Loads the initial JobTypes registry |

## Order of operations

```
1. Run provision-lists.ps1                    # creates 17 lists (incl. Subcategories)
2. Run ensure-license-costs-sync-schema.ps1   # creates the License Costs list (18th solution list)
3. Run grant-sites-selected.ps1               # grants SP-IT-SharePoint write access
4. Run seed-priority-matrix.ps1               # loads the 9-row matrix
5. Run seed-approval-policies.ps1             # loads the 6 seed policies
6. Run seed-job-types.ps1                     # loads JobTypes registry
7. Run seed-categories.ps1 / seed-subcategories.ps1 / seed-catalog-items.ps1
8. Manually populate CIs / KB                 # one-time data import (out of scope)
```

## Schema source of truth

[`../../sharepoint-itsm-schema.xlsx`](../../sharepoint-itsm-schema.xlsx). Per-list scripts must match the spreadsheet column-for-column. When the schema changes, update both — the spreadsheet for documentation, the script for execution.

Columns added to `Tickets` beyond the schema xlsx (per [open items 2026-04-29](../../decisions/0001-dispatcher-host.md)):

| Column | Type | Purpose |
|---|---|---|
| `ConfidentialityLevel` | Choice (Public/Restricted/Confidential) | Drives item-level perm break |
| `PermSyncedAt` | Date/Time | Last time the perm-sync flow ran on this item |

> `AuthorizedReaders` (Person, multi) was designed for explicit readers when level ≠ Public, but is **not provisioned on the live Tickets list** — the perm-sync flow and the Confidential tier are deferred (see [`../../flows/permsync/README.md`](../../flows/permsync/README.md)). The provisioning script does not create it.

Ticket-type validation adds another Tickets schema increment:

| Column | Type | Purpose |
|---|---|---|
| `TicketTypeValidated` | Boolean | True after the validator confirms or corrects Incident vs Request classification |
| `TicketTypeValidationStatus` | Choice (`Valid`, `AutoReclassified`, `NeedsConfirmation`, `Bypassed`) | Validation outcome for downstream trigger guards |
| `TicketTypeValidationReason` | Note | Human-readable reason or ambiguity details |
| `SuggestedTicketType` | Choice (`Incident`, `Request`) | Recommended type when the row needs confirmation |
| `TypeOverrideConfirmed` | Boolean | Records that the creator intentionally kept a mismatched type |

## Eighteen solution lists

The original schema xlsx specifies 13 lists. The build adds more (Subcategories, Tickets-Archive, JobTypes, Config, ApprovalStages, Provisioning Jobs, License Costs) for **18 solution lists** total. `provision-lists.ps1` creates 17 of them; `License Costs` is created by `ensure-license-costs-sync-schema.ps1`. (Two further lists exist in the tenant — `FlowDocsInventory` and `ITSM Project Tracker` — but those are AI-coworker operational lists, **not part of the solution**.)

Key additions beyond the xlsx:

| Added | Why |
|---|---|
| `Tickets-Archive` | Closed > 12 months land here to keep main Tickets list under the 50k unique permission scope limit. Mirror schema. |
| `JobTypes` | Dispatcher contract §6 — the registry the dispatcher loads at start-of-day. |
| `Config` | Kill switch + per-environment toggles. Referenced by dispatcher contract §7. |
| `ApprovalStages` | Approval flow contract §9 — per-stage decision audit rows. |
| `ProvisioningJobs` | Dispatcher contract §3 + executor contract §5 — the audit list. |

Some of those overlap with what's already in the schema xlsx under different names (e.g., the schema's "Approvals" list is what we call ApprovalStages). The provisioning scripts use the names referenced in the contract specs as the source of truth where there's drift; the xlsx will be updated to match in a separate pass.

## Running it

```powershell
# Set parameters (or use a -ParameterFile)
$tenant     = 'contoso'
$siteUrl    = "https://$tenant.sharepoint.com/sites/ITSM"
$appId      = '<SP-IT-Provisioning client ID>'
$keyVault   = 'kv-itsm-dev'
$certName   = 'SP-IT-Provisioning'

# Provision all lists
./provision-lists.ps1 `
    -SiteUrl $siteUrl `
    -AppId $appId `
    -KeyVaultName $keyVault `
    -CertificateName $certName `
    -Verbose
```

Re-runnable. The `Ensure-*` helpers check current state before mutating; output reports `[CREATED]` / `[UPDATED]` / `[NO-CHANGE]` per element.

## Open items before first run

1. **Pilot tenant URL** — open item #1 in the design memo. Until decided, run against a dev tenant.
2. **App registration `SP-IT-Provisioning`** — create in Entra, grant `Sites.FullControl.All`, admin consent, upload cert.
3. **Cert in Key Vault** — `kv-itsm-dev` must exist with `SP-IT-Provisioning` certificate.
4. **Site exists** — `/sites/ITSM` must be created via SharePoint Admin Center first (the script does NOT create the site).
