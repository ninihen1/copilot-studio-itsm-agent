# Phase 3 deployment runbook

**Authored:** 2026-05-02
**Updated:** 2026-05-02 (Phase 3.1 — caveat fixes shipped, see §Phase 3.1)
**Source:** `IMPLEMENTATION-PLAYBOOK.md` §9b (Phase 3 backlog), items 21-23
**Scope:** the three deliverables Catherine asked for to move ITSM beyond pilot toward marketable product

---

## Contents

| Deliverable | Repo path | Owner action |
|---|---|---|
| **1. Category + subcategory taxonomy** | `infra/sharepoint/lists/01b-subcategories.ps1`, `seed-subcategories.ps1`, `seed-categories.ps1` (updated), `lists/10-tickets.ps1` (updated) | Provision + seed via PnP |
| **2. Service Catalog with 5-10 items + RITM/SCTASK** | `infra/sharepoint/lists/05-service-catalog.ps1` (updated), `seed-catalog-items.ps1`, `flows/ritm-generator/definition.json`, `flows/sctask-orchestrator/definition.json` | Provision + seed + deploy 2 flows |
| **3. 5 more executors + JobTypes** | `infra/azure/provision-5-executors.ps1`, `flows/executors/{groups,licensing,exchange,sharepoint,teams}/definition.json` | Provision Entra apps + deploy 5 flows |

All three deliverables ship as **scripts + flow definitions ready to deploy**. Catherine deploys; this session cannot run PnP / `az` / PA REST against contoso directly.

---

## Deliverable 1 — Category + subcategory taxonomy

### What changed

| File | Change |
|---|---|
| `infra/sharepoint/seed-categories.ps1` | Added 5 research-parity top-level categories: Telecom & Mobile, Facilities, HR Cross-Over, Database & Storage, Reporting & Analytics. Total: 18 categories (was 13). |
| `infra/sharepoint/lists/01b-subcategories.ps1` | NEW. Provisions a Subcategories list with Title + ParentCategory (Lookup→Categories) + Status + SortOrder + JobTypeHint. Title display name is "Subcategory Name" (Phase B convention). |
| `infra/sharepoint/seed-subcategories.ps1` | NEW. Seeds **80 subcategories** across the 18 parent categories. Each subcategory carries an optional JobTypeHint to bias the triage agent's automation choice. |
| `infra/sharepoint/lists/10-tickets.ps1` | Subcategory column upgraded from Text → Lookup → Subcategories (cascade-filterable on Tickets.CategoryRef). |
| `infra/sharepoint/provision-lists.ps1` | Added `01b` entry between `01-categories` and `02-configuration-items`. |

### Coverage vs research baseline (`servicenow-itsm-ticketing-report.md` §4.1)

| Research category | Pre-Phase 3 | Post-Phase 3 |
|---|---|---|
| Hardware | ✓ no subcats | ✓ + 9 subcats |
| Software | ✓ no subcats | ✓ + 5 subcats |
| Account & Access | ✓ no subcats | ✓ + 8 subcats |
| Network & Connectivity | ✓ no subcats | ✓ + 7 subcats |
| Email & Messaging | ✓ no subcats | ✓ + 6 subcats |
| Telecom / Mobile | partial | ✓ + 6 subcats (NEW Telecom & Mobile category) |
| Security | ✓ no subcats | ✓ + 5 subcats |
| Facilities | ❌ | ✓ + 3 subcats (NEW) |
| HR (HRSD) | ❌ | ✓ + 7 subcats (NEW HR Cross-Over) |
| Database & Storage | partial | ✓ + 4 subcats (NEW) |
| Reporting & Analytics | ❌ | ✓ + 4 subcats (NEW) |
| General Inquiry | ✓ | ✓ |

Plus 5 agent-vocabulary categories (Identity & Access Management, Groups & Permissions, Licensing, SharePoint & Files, Teams & Collaboration, Mobile & Endpoint, Security & Compliance) each with their own subcategories aligned to seeded JobTypes.

### Deploy steps

```powershell
cd "c:\Users\ninih\GitHub\Copilot Studio\infra\sharepoint"

# 1. Provision the Subcategories list (and any pending updates to others)
./provision-lists.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/ITSM" `
    -AppId "be813252-..." `  # SP-IT-Provisioning per memory
    -KeyVaultName "kv-itsm-demo" `
    -CertificateName "sp-it-provisioning-cert" `
    -ListsToProvision "01b"

# 2. Seed the 5 new top-level categories (idempotent — re-runs only add the new ones)
./seed-categories.ps1 -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName ...

# 3. Seed the 80 subcategories
./seed-subcategories.ps1 -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName ...

# 4. (Manual schema migration) Tickets.Subcategory was a Text column; now needs to be Lookup.
#    PnP's Ensure-PnPField won't change a column type. Two options:
#    (a) Delete the existing Subcategory column (safe — pilot tickets have no Subcategory data)
#        then re-run provisioning for list 10:
#        Remove-PnPField -List Tickets -Identity Subcategory -Force
#        ./provision-lists.ps1 ... -ListsToProvision "10"
#    (b) Leave the column as Text in production lists until next major migration.
#        Tickets created via Power Apps form should still bind to the Lookup definition;
#        SP just stores it as Text underneath.
```

### Caveat — orchestrator wiring

Tickets created with `Subcategory` populated will have `body/Subcategory/Id` available to flows. The Triage Orchestrator's category-resolve step needs an additional Subcategory-resolve step (lookup Subcategories by Title from agent reasoning text → patch `Subcategory/Id`). Phase 3.1 work; not in this delivery.

---

## Deliverable 2 — Service Catalog with 5-10 items + RITM/SCTASK

### What changed

| File | Change |
|---|---|
| `infra/sharepoint/lists/05-service-catalog.ps1` | Added 2 new fields: `TaskTemplates` (Note, JSON array of SCTASK templates for multi-task Order Guides), `SubcategoryHint` (Lookup → Subcategories, used by RITM Generator to match catalog items by ticket subcategory). Title display name is "Item Code". |
| `infra/sharepoint/seed-catalog-items.ps1` | NEW. Seeds **8 catalog items**: 6 single-task (Password Reset, License Request, Add to Group, Shared Mailbox Access, Restore SharePoint File, Software Install) + 2 multi-task Order Guides (New Hire Onboarding, User Offboarding). |
| `flows/ritm-generator/definition.json` | NEW. Triggered when a Tickets row is created with TicketType=Request. Looks up the Service Catalog item by Subcategory hint, creates a RITM, parses TaskTemplates JSON, and creates one SCTASK per task entry (or one SCTASK using the item's JobType if TaskTemplates is empty). Add the planned ticket-type validation guard before relying on this in mixed Incident/Request intake. |
| `flows/sctask-orchestrator/definition.json` | NEW. Triggered when a Tasks row reaches a terminal state (Closed Complete / Incomplete / Skipped / Cancelled). Cascades: when all SCTASKs of a RITM are closed → close the RITM; when all RITMs of a Ticket are closed → resolve the Ticket. Handles failure aggregation (any SCTASK failed → RITM Closed Incomplete; any RITM failed → Ticket close code "Not Solved"). |

### State machine

```
Tickets.row created (TicketType=Request, Subcategory=X)
    │
    ▼
Ticket Type Validator confirms Request classification
    │
    ▼
RITM Generator (1-min poll on GetOnNewItems)
    │
    ├─ Find Service Catalog item where SubcategoryHint = X
    │
    ├─ Create RITM (state=Pending Approval)
    │
    └─ ForEach task in TaskTemplates (or single task using item.JobType):
            Create SCTASK (state=Open, sortOrder)
    │
    ▼
[Manual approval / human work / executor invocation per task]
    │
    ▼
SCTASK Orchestrator (2-min poll on GetOnUpdatedItems)
    │
    ├─ When SCTASK reaches Closed Complete / Incomplete / Skipped:
    │     ├─ Get sibling tasks under same RITM
    │     ├─ If all closed → patch RITM to Closed Complete (or Incomplete if any failed)
    │     │
    │     └─ When RITM closed:
    │           ├─ Get sibling RITMs under same Ticket
    │           ├─ If all RITMs closed → patch Ticket to Resolved
    │           │     CloseCode: Solved Permanently / Not Solved
```

### Deploy steps

```powershell
# 1. Update Service Catalog list schema (TaskTemplates + SubcategoryHint columns)
cd "c:\Users\ninih\GitHub\Copilot Studio\infra\sharepoint"
./provision-lists.ps1 ... -ListsToProvision "05"

# 2. Seed the 8 catalog items (depends on Categories, Subcategories, Approval Policies seeded)
./seed-catalog-items.ps1 ...

# 3. Provision ticket-type validation columns and deploy ITSM-Ticket-Type-Validator

# 4. Deploy RITM Generator flow with validation-complete guard
#    Use FlowStudio MCP `add_live_flow_to_solution` or POST to PA REST API
#    POST https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/{env}/flows?api-version=2016-11-01
#    Body: { properties: { displayName: "ITSM-RITM-Generator (1.5)",
#                          definition: <flows/ritm-generator/definition.json>,
#                          connectionReferences: { shared_sharepointonline: { connectionName: "shared-sharepointonline-...", ... } } } }
#    Per memory `reference_pa_rest_api_create_flow.md` POST creates a new flow.

# 5. Deploy SCTASK Orchestrator flow
#    Same shape, different definition.json

# 6. End-to-end smoke test
#    a. Insert a Tickets row: TicketType=Request, Subcategory=Password Reset
#    b. Verify validator marks the row valid before RITM Generator creates the RITM.
#    c. Wait 60s. Verify RITM created with state=Pending Approval and 1 SCTASK created.
#    d. Manually patch SCTASK state → Closed Complete.
#    e. Wait 120s. Verify RITM auto-patched to Closed Complete and Ticket auto-resolved.
```

### Known limitations / Phase 3.1 follow-ups

- **No approval gate inside RITM lifecycle.** RITMs go from Pending Approval → SCTASKs created immediately. Real ITSM holds RITM at Pending Approval until manager approves; then transitions to Approved → In Progress → SCTASKs spawned. Add an approval gate flow in 3.1.
- **SCTASK with non-empty `jobType` does NOT auto-create a Provisioning Job.** Today the agent / orchestrator creates PJs from agent reasoning. To make SCTASKs trigger PJs automatically, add a SCTASK→PJ bridge flow that fires when a SCTASK is created with `jobType` set. 3.1 work.
- **Failure compensation not wired.** If SCTASK 2 of 5 fails in onboarding, the system marks RITM as Closed Incomplete but doesn't roll back SCTASKs 1 (which already succeeded). Compensation mapping exists in JobTypes registry (`CompensationJobType`). 3.1 should wire automatic compensation for failed multi-step Order Guides.
- **Subcategory match is exact.** RITM Generator looks up Service Catalog by `SubcategoryHint = ticket.Subcategory`. The validator and portal should require explicit selection when multiple active catalog items share a subcategory; do not let RITM Generator pick the first match silently.

---

## Deliverable 3 — 5 more executors + matching JobTypes

### What changed

| File | Change |
|---|---|
| `infra/azure/provision-5-executors.ps1` | NEW. Provisions 5 Entra apps (SP-IT-Groups, SP-IT-Licensing, SP-IT-Exchange, SP-IT-SharePoint, SP-IT-Teams), grants Graph application permissions, generates KV secrets, assigns directory roles. Idempotent. |
| `flows/executors/groups/definition.json` | Replaced stub with production-ready flow (425 lines, JobTypes: groups.addMember, groups.removeMember). Pattern matches identity executor. |
| `flows/executors/licensing/definition.json` | Replaced (446 lines, JobTypes: licensing.assign, licensing.revoke). |
| `flows/executors/exchange/definition.json` | Replaced (441 lines, JobTypes: exchange.grantFullAccess, exchange.revokeFullAccess). **Caveat**: Graph cannot grant Exchange Full Access — these are stubs that record intent; actual EXO grant requires a wrapper Function in 3.1. |
| `flows/executors/sharepoint/definition.json` | Replaced (327 lines, JobTypes: sharepoint.restoreFile). |
| `flows/executors/teams/definition.json` | Replaced (440 lines, JobTypes: teams.createChannel, teams.addChannelMember). **Note**: Teams JobTypes were not in the original seed-job-types.ps1 — see "JobTypes seed" below. |
| `infra/sharepoint/seed-job-types.ps1` | Already had groups / licensing / exchange / sharepoint JobTypes seeded in pilot Phase 2. **Pending**: add `teams.createChannel` and `teams.addChannelMember` rows to complete coverage. |

### Architectural finding — dispatcher needs no changes

The dispatcher is a **broadcast** router, not a Switch_OnJobType router:

1. Caller POSTs `{ pjId, jobType, ... }` to the dispatcher.
2. Dispatcher validates JobType anti-tamper, kill-switch, idempotency.
3. Dispatcher patches the PJ row to `JobStatus=Dispatched`.
4. Returns 202.

Each executor flow polls `Provisioning Jobs` every 3 minutes via `GetOnUpdatedItems` and filters:

```
JobStatus.Value == 'Dispatched' AND startsWith(JobType, '<category>.')
```

Adding a new executor = adding a new flow with its own prefix filter. **Zero dispatcher changes required.** This was confirmed by reading `flows/dispatcher/definition/definition.json` — there is no `Switch_OnJobType` action.

### Deploy steps

```powershell
# 1. Sign in to az CLI as a contoso global admin (needed for app create + role assignment + admin consent)
az login --tenant contoso.onmicrosoft.com
az account set --subscription "Microsoft Partner Network"  # MPN — per memory ref_az_subscription_rights_contoso.md

# 2. Provision the 5 SPs + KV secrets + directory roles
cd "c:\Users\ninih\GitHub\Copilot Studio\infra\azure"
./provision-5-executors.ps1 `
    -TenantId "00000000-0000-4000-8000-000000000009" `
    -KeyVaultName "kv-itsm-demo" `
    -ResourceGroup "rg-itsm-pilot"

# Output: 5 AppIds in a summary table. Save these.

# 3. Edit each executor flow definition to replace the AppId placeholder
#    For each of: flows/executors/{groups,licensing,exchange,sharepoint,teams}/definition.json
#    Replace `<APPID-GROUPS>` etc. with the real AppId from step 2 (one find/replace per file).

# 4. Deploy each flow
#    Same POST pattern as RITM Generator:
#    POST https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/{env}/flows?api-version=2016-11-01
#    Repeat for all 5 executors.
#    Or use FlowStudio MCP add_live_flow_to_solution.

# 5. Smoke test (one PJ per executor)
#    Insert a Tickets row, let the orchestrator/agent propose a JobType (or hand-create a PJ).
#    Once PJ.JobStatus=Dispatched, watch the appropriate executor pick it up within 3 min.
#    Verify Graph call success in PA run history; check PJ.JobStatus=Succeeded with GraphRequestId populated.

# 6. Add Teams JobTypes to the registry (one-off seed addition)
./seed-job-types.ps1 ...  # idempotent — only inserts new rows
# Add the 2 entries to the $jobTypes array if not already present:
#   { JobType='teams.createChannel', Category='teams', RiskTier='low', ... }
#   { JobType='teams.addChannelMember', Category='teams', RiskTier='low', ... }
```

### Known limitations / Phase 3.1 follow-ups

- **Exchange Full Access stubs.** The exchange executor's two JobTypes record intent but don't actually call `Add-MailboxPermission`. 3.1 needs a wrapper Function (Azure Function with Exchange Online PowerShell module) that the executor invokes via Http call.
- **SharePoint scope.** Pilot uses Sites.ReadWrite.All (broad). 3.1 should switch to Sites.Selected with per-site grants — restore-file flow grants Sites.Selected on /sites/ITSM only.
- **Teams Administrator role is broad.** The Teams executor SP carries Teams Administrator directory role for cross-tenant team operations. Tighten to per-team membership in 3.1.
- **No retry / DLQ.** Each executor's failure path patches PJ to Failed but doesn't retry. Phase 2 backlog #4 (Service Bus) and #8 (DLQ monitor) cover this.
- **Idempotency at executor level.** PJ-level idempotency is enforced at dispatcher (Check_Idempotency in dispatcher flow). Executor doesn't double-check — relies on Graph being idempotent for its operations (PATCH disable/enable is, POST add member is not — second add returns 400 ObjectAlreadyExists). 3.1 should pre-flight Graph state checks for non-idempotent operations.

---

## End-to-end deployment order

If deploying all 3 deliverables clean (recommended):

1. **Categories + Subcategories** (foundation — Service Catalog and Tickets both depend on these)
   - Provision 01b list
   - Seed 5 new categories
   - Seed 80 subcategories
   - Migrate Tickets.Subcategory column to Lookup (manual delete + re-provision)

2. **5 Executors infrastructure** (independent of catalog work)
   - Run `provision-5-executors.ps1`
   - Edit 5 flow definitions to substitute AppIds
   - Deploy 5 executor flows

3. **Service Catalog + RITM + SCTASK**
   - Provision 05 list (TaskTemplates + SubcategoryHint additions)
   - Seed 8 catalog items
   - Deploy RITM Generator flow
   - Deploy SCTASK Orchestrator flow
   - Smoke test with a Tickets insert (TicketType=Request, Subcategory=Password Reset)

Total deployment time estimate: **2-4 hours** assuming az + PnP + PA REST tooling is configured.

---

## What this does NOT cover

Phase 3 backlog items 24-30 (multi-tenant installer, end-user surface, email-to-ticket ingestion, Power BI reporting, Problem/Change Management, SLA engine, Order Guides UX) remain backlog. Reaching ready-to-market also needs Phase 2 production-hardening items 1-20.

After Catherine deploys these 3 deliverables, the system will:
- ✅ Have research-parity category taxonomy
- ✅ Demo Service Catalog → RITM → SCTASK lifecycle
- ✅ Run automation against 5 more JobType categories (was 1, now 6)

But will NOT yet:
- ❌ Be installable at a customer (still hardcoded to contoso)
- ❌ Have an end-user portal / form
- ❌ Have reporting dashboards
- ❌ Cover Problem / Change Management modules properly

Per playbook §9b, those are the next gate.

---

## Phase 3.1 — caveat fixes (shipped 2026-05-02)

The five "known limitations" Catherine flagged on the original Phase 3 delivery have all been addressed as code:

| # | Caveat | Fix shipped |
|---|---|---|
| 1 | Tickets.Subcategory schema migration is manual | `infra/sharepoint/migrate-tickets-subcategory.ps1` — guarded migration with dry-run, row-count probe, delete + re-provision |
| 2 | Teams JobTypes not in seed | `seed-job-types.ps1` extended with `teams.createChannel` + `teams.addChannelMember` |
| 3 | RITM has no approval gate | RITM Generator no longer spawns SCTASKs immediately. New `flows/ritm-approval/definition.json` triggers on RITM creation, sends Power Automate Approval to RequestedFor's manager (Office 365 Users connector), and on Approve patches RITM to Approved + spawns SCTASKs from TaskTemplates; on Reject patches to Closed Incomplete |
| 4 | SCTASK with jobType doesn't auto-create a PJ | New `flows/sctask-pj-bridge/definition.json` — triggers on SCTASK create, reads new `Tasks.JobType` column, fetches parent RITM/Ticket, constructs Target+Args from RITM.Variables, creates PJ in Dispatched state with stable IdempotencyKey, then watches PJ to terminal state and closes the SCTASK accordingly. New `Tasks.JobType` column added to `lists/13-tasks.ps1` |
| 5 | Exchange Full Access stubs | `infra/azure/functions/exo-mailbox-permission/{run.ps1,function.json}` + `profile.ps1` + `requirements.psd1` + `host.json` — PowerShell-based Function App that wraps `Add/Remove-MailboxPermission`. Cert-based app-only EXO auth, cert loaded from KV at cold start via Managed Identity. New `infra/azure/setup-exo-cert.ps1` generates the cert, uploads to SP-IT-Exchange app, stores PFX+password in KV. Updated `flows/executors/exchange/definition.json` to call the Function (with key from KV) instead of the Graph stub. |

### 3.1 deploy steps (in dependency order)

```powershell
# Fix #2 — Teams JobTypes (smallest; do first so tests have valid JobTypes)
./seed-job-types.ps1 ...   # idempotent; adds the 2 new rows

# Fix #1 — Tickets.Subcategory migration
# Pre-req: 01b-subcategories.ps1 must be provisioned + seed-subcategories.ps1 run
./migrate-tickets-subcategory.ps1 ...           # dry-run first
./migrate-tickets-subcategory.ps1 ... -Confirm  # actually migrate

# Fix #4 — Tasks.JobType column (re-run Tasks list provisioning to add the column)
./provision-lists.ps1 ... -ListsToProvision "13"

# Fix #3 — Deploy the new RITM Approval flow
#   POST flows/ritm-approval/definition.json via PA REST or FlowStudio MCP add_live_flow_to_solution

# Re-deploy the updated RITM Generator (no longer spawns SCTASKs)
#   PATCH flows/ritm-generator/definition.json onto the existing flow

# Fix #4 — Deploy SCTASK→PJ bridge
#   POST flows/sctask-pj-bridge/definition.json

# Fix #5 — Exchange EXO PS Function
cd infra/azure
./setup-exo-cert.ps1 -AppId <SP-IT-Exchange AppId> -KeyVaultName kv-itsm-demo
# Follow the printed instructions to add Exchange.ManageAsApp permission and grant admin consent
# Then provision + deploy the Function App per infra/azure/functions/README.md
# Store the Function default key in KV as 'ExoMailboxPermission-FunctionKey'
# Re-deploy flows/executors/exchange/definition.json with substituted AppId
```

### 3.1 smoke tests

```powershell
# Test #1 — RITM approval gate
# 1. Insert Tickets row: TicketType=Request, Subcategory=Password Reset (or any catalog-mapped subcat)
# 2. Wait 60s — RITM Generator creates RITM in Pending Approval. NO SCTASKs yet.
# 3. RITM Approval flow fires within 60s — Approval request sent to RequestedFor's manager via Teams + email.
# 4. Manager approves — RITM patched to Approved. SCTASKs spawn from TaskTemplates.
# 5. SCTASK→PJ bridge fires within 60s — for each SCTASK with JobType, a PJ is created in Dispatched.
# 6. Executor (e.g., identity executor) picks up PJ, runs to Succeeded.
# 7. SCTASK→PJ bridge polls PJ — when Succeeded, SCTASK patched to Closed Complete.
# 8. SCTASK Orchestrator fires — when all SCTASKs Closed Complete, RITM patched to Closed Complete.
# 9. SCTASK Orchestrator fires — when all RITMs Closed Complete, Ticket patched to Resolved.

# Test #5 — EXO Function
$key = az keyvault secret show --vault-name kv-itsm-demo --name ExoMailboxPermission-FunctionKey --query value -o tsv
$url = "https://func-itsm-dev.azurewebsites.net/api/exo-mailbox-permission?code=$key"
$body = @{ action='grant'; mailboxUpn='shared@contoso.onmicrosoft.com'; delegateUpn='arwen@contoso.onmicrosoft.com' } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri $url -ContentType 'application/json' -Body $body
# Expect: { ok = $true, action = 'grant', ... }
# Verify in Exchange Admin Center: shared mailbox permissions show arwen with FullAccess.
```

### 3.1 outstanding (smaller items — Phase 3.2)

- **SharePoint Sites.Selected scope** — pilot still uses Sites.ReadWrite.All. Phase 3.2 implements the per-site grant pattern.
- **Teams Administrator role narrowing** — pilot still uses tenant-wide Teams Administrator. Phase 3.2 adds the SP as owner of each touched team via Graph rather than relying on the role.
- **Pre-flight idempotency at executor level** — second `groups.addMember` for an already-member user returns 400. Phase 3.2 adds a HEAD/GET pre-flight per non-idempotent JobType.
- **Multi-stage approval policy engine** — RITM approval gate currently routes to RequestedFor's manager only. The full policy engine in `flows/approval/spec.md` (manager → IT owner → CAB) is Phase 3.2 work.
- **Function App cold start** — first EXO call may take 5+ seconds. Acceptable for pilot; Phase 4 may move to Premium tier if volume warrants.
