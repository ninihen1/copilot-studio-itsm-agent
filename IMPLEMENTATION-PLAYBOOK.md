# ITSM Implementation Playbook

**Audience:** A fresh AI agent (or new engineer) tasked with rebuilding, extending, or auditing the ITSM pilot from scratch.
**Last updated:** 2026-05-08 (Day 4 status tracked in `flows/CURRENT-STATUS.md`)
**Pairs with:** [`itsm-design-memo.md`](itsm-design-memo.md) (canonical design), [`README.md`](README.md), [`DEPLOYMENT.md`](DEPLOYMENT.md)

This is the **single doc to read first.** It describes everything implemented, the order it must be built in, the exact tools and permissions used, and every gotcha that cost time to discover.

---

## 1. Mission

Build a ServiceNow-style IT helpdesk on Microsoft 365 — SharePoint as system of record, Power Automate for orchestration, Copilot Studio for the user-facing agents. AI proposes; humans approve; scoped service principals execute. **No agent ever holds Graph write permissions.**

Pilot scope (proven 2026-05-01): a caller files a ticket → the Triage Orchestrator flow calls the Helpdesk Triage Agent to classify it → the orchestrator writes a Provisioning Job + an Approvals row → human approver approves → Dispatcher patches PJ to Dispatched → Identity-Executor calls Microsoft Graph to reset the user's password → audit row written. Closed loop. (The original agent-callable ProposeAction handoff was retired 2026-05-30; see ADR 0002.)

---

## 2. Architecture

### 2.1 Six-stage design (production target)

```
1. INTAKE     — Outlook / Teams / Service Portal / Voice → Tickets SP row
2. TYPE GATE  — validate Incident vs Request before RITM, triage, or MI automation
3. TRIAGE     — Helpdesk Triage Agent classifies (READ-ONLY, no privileged writes)
4. APPROVAL   — Approval flow runs policy stages (Manager / IT-Owner / CAB), signs JWT
5. DISPATCH   — POST /provisioning/jobs validates JWT, idempotency, queues to Service Bus
6. EXECUTION  — 6 executor flows fan-out by JobType, each behind its own scoped SP
7. AUDIT      — Provisioning Jobs SP row + App Insights + caller notification
```

The type gate is implemented in two layers: frontend validation in the portal submit form, plus a post-create `ITSM-Ticket-Type-Validator` flow on the Tickets list. The validator must set explicit validation fields before normal created-ticket subscribers act.

### 2.2 Pilot architecture (what's actually deployed)

```mermaid
flowchart TD
    user[Caller / Catherine] -->|chat| triage[Helpdesk Triage Agent<br/>Copilot Studio]
    triage -->|classifies| orch[ITSM-Triage-Orchestrator<br/>flow 8214cc66-...]
    orch -->|writes PJ + Approvals row| pj[(Provisioning Jobs<br/>SP list)]
    catherine[Catherine via Graph API] -->|patch row| approvals[(Approvals<br/>SP list)]
    approvals -->|3-min poll trigger| bridge[ITSM-Approval-Bridge<br/>flow 05b00ed2-...]
    bridge -->|HTTP POST| dispatcher[ITSM-Dispatcher<br/>flow 97a4c109-...]
    dispatcher -->|PATCH JobStatus=Dispatched| pj
    pj -->|3-min poll trigger| executor[ITSM-Identity-Executor<br/>flow c06e63bf-...]
    executor -->|GetSecret| kv[(Key Vault<br/>kv-itsm-demo)]
    executor -->|client_credentials| aad[Entra ID]
    aad -->|access_token| executor
    executor -->|PATCH /users/upn/passwordProfile| graph[Microsoft Graph]
    executor -->|PATCH JobStatus=Succeeded<br/>+ GraphRequestId + ResultJson| pj
```

**Pilot deviations from §3-7 of the design memo** (each reversible per `decisions/0001-dispatcher-host.md`):

| Production design | Pilot shortcut |
|---|---|
| JWT signed by Approval flow, validated by Dispatcher | Trust SAS URL; no JWT |
| Azure Table `IdempotencyKeys` with `If-None-Match: *` | SP `IdempotencyKey` field query (race-vulnerable) |
| Service Bus topic + 6 subscriptions | Executor polls PJ list directly |
| Six dedicated executor SPs | Only `SP-IT-Identity` exists for `identity.*` JobTypes |
| Cert in HSM-backed KV | 1-year client secret in standard KV |
| App Insights primary audit | PA run history + SP audit row |
| Multi-stage Approval flow with JWT minting | `ITSM-Approval-Bridge` (single approver flips SP row) |

---

## 3. Tools required (install before starting)

| Tool | Why | Install |
|---|---|---|
| **PowerShell 7+** | Everything is PowerShell scripted | https://aka.ms/install-powershell |
| **PnP.PowerShell ≥ 2.4.0** | All SharePoint provisioning, list ops | `Install-Module PnP.PowerShell -MinimumVersion 2.4.0 -Scope CurrentUser` |
| **Azure CLI (`az`)** | Entra app reg, Key Vault, role assignments | https://learn.microsoft.com/cli/azure/install-azure-cli |
| **FlowStudio MCP** | Read/inspect Power Automate flows, action outputs | https://mcp.flowstudio.app — installed as Claude Code MCP |
| **Microsoft.Graph.* PowerShell** | Directory role assignments, identity lookups | `Install-Module Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Authentication` |
| **VS Code Copilot Studio extension** | Clone/push agent YAML | VS Code marketplace |
| **VS Code FlowStudio MCP extension** *(optional)* | Same as MCP but UI-driven | VS Code marketplace |
| **`python-docx`** *(optional)* | Round-trip docx ↔ md | `pip install python-docx` |

---

## 4. Identities used

### 4.1 Tenant + subscriptions

| Identity | Value |
|---|---|
| Tenant | `contoso.onmicrosoft.com` (id `00000000-0000-4000-8000-000000000009`) |
| User | `catherine.han@flowstudio.app` (object id `00000000-0000-4000-8000-000000000002`) |
| Pilot Azure subscription | **Microsoft Partner Network** (`00000000-0000-4000-8000-000000000037`) — Catherine has Owner here. **Use this for any `az` resource creation.** |
| Power Platform environment | **Flow Studio Demo** (`00000000-0000-4000-8000-000000000045`, region australia) |
| SharePoint site | `https://contoso.sharepoint.com/sites/ITSM` |

### 4.2 Service principals

| App | AppId | Permissions | Directory role | Cert/Secret | Pilot |
|---|---|---|---|---|---|
| `SP-IT-Provisioning` | `00000000-0000-4000-8000-000000000020` | `Sites.FullControl.All` | n/a | Cert (local, used by PnP scripts) | ✅ |
| `SP-IT-Identity` | `00000000-0000-4000-8000-000000000014` | `User.ReadWrite.All`, `UserAuthenticationMethod.ReadWrite.All` | **Password Administrator** | Client secret in KV `SP-IT-Identity-ClientSecret` (1y, exp 2027-05-01) | ✅ |
| SP-IT-Groups | TBD | `Group.ReadWrite.All`, `GroupMember.ReadWrite.All` | Groups Administrator | TBD | ❌ Week 5 |
| SP-IT-Licensing | TBD | `User.ReadWrite.All`, `Organization.Read.All` | License Administrator | TBD | ❌ Week 5 |
| SP-IT-Exchange | TBD | `Mail.ReadWrite`, `MailboxSettings.ReadWrite`, `User.Read.All` | Exchange Administrator | TBD | ❌ Phase 2 |
| SP-IT-SharePoint | TBD | `Sites.Selected` (NOT FullControl) | SharePoint Administrator | TBD | ❌ Week 5 |
| SP-IT-Teams | TBD | `TeamMember.ReadWrite.All`, `Channel.Create`, `DeviceManagement*` | Teams Administrator | TBD | ❌ Phase 2 |

**🔴 Critical:** Graph application permissions (e.g. `User.ReadWrite.All`) alone do NOT authorize destructive writes like password resets. Each SP also needs an **Entra directory role** matching its scope (e.g. Password Administrator for identity ops). Without the role: 403 `Authorization_RequestDenied`. Role propagation takes ~5-10 min after assignment.

### 4.3 Azure resources

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-itsm-pilot` | australiaeast, MPN sub |
| Key Vault (RBAC) | `kv-itsm-demo` | Catherine = Key Vault Secrets Officer |
| Secrets stored | `SP-IT-Identity-ClientSecret` | 1-year, expires 2027-05-01 |

### 4.4 Power Automate connections (pre-existing in env)

| Connection | id | Used by |
|---|---|---|
| shared_sharepointonline | `f1550c57e913479793d6de83b61fa1b0` | All flows |
| shared_keyvault | `3902492e65ec448ea29a4c6752190756` | Identity-Executor |
| shared_microsoftcopilotstudio | `shared-microsoftcopi-00000000-0000-4000-8000-000000000041` | Triage-Orchestrator |

---

## 5. Implementation order

Build in dependency order. Each phase is verifiable before moving to the next.

### Phase 1 — Tenant + tooling prereqs (~30 min)

1. Create the SharePoint site `https://{tenant}.sharepoint.com/sites/ITSM` (Team site, no M365 group).
2. Install all tools listed in §3.
3. Confirm Az login: `az account show` — switch to MPN sub: `az account set --subscription <id>`.
4. Confirm Power Platform env access in https://make.powerautomate.com.

### Phase 2 — SP-IT-Provisioning Entra app (~10 min)

Used by all PnP cert-auth scripts.

```powershell
# Catherine ran this once. Persisted in Entra.
$app = az ad app create --display-name "SP-IT-Provisioning" --sign-in-audience AzureADMyOrg | ConvertFrom-Json
az ad sp create --id $app.appId
# Generate self-signed cert, upload to app, save cert locally for PnP
# Add Sites.FullControl.All Application permission, admin-consent
```

### Phase 3 — SharePoint list provisioning (~15 min)

```powershell
cd "c:/Users/ninih/GitHub/Copilot Studio/infra/sharepoint"
./provision-lists.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/ITSM" `
    -AppId "00000000-0000-4000-8000-000000000020" `
    -CertificatePath "<local-cert-path>"
```

Provisions 17 lists from `infra/sharepoint/lists/*.ps1` (License Costs is created separately by `ensure-license-costs-sync-schema.ps1` — 18 solution lists total). Idempotent — safe to re-run.

**Then seed:**

```powershell
./seed-priority-matrix.ps1     -SiteUrl ... -AppId ... -CertificatePath ...
./seed-approval-policies.ps1   -SiteUrl ... -AppId ... -CertificatePath ...
./seed-job-types.ps1           -SiteUrl ... -AppId ... -CertificatePath ...
./seed-config.ps1              -SiteUrl ... -AppId ... -CertificatePath ...   # KillSwitch=false
```

**Verify:** open `/sites/ITSM` in browser → Site Contents → all 18 solution lists exist with rows in Priority Matrix (9), Approval Policies (6), JobTypes (10+), Config (1).

### Phase 4 — Triage Agent + Orchestrator (~45 min)

Build order:
1. In Copilot Studio portal (https://copilotstudio.microsoft.com), in Flow Studio Demo env, create agent **"Helpdesk Triage Agent"**. Note assigned schemaName.
2. Clone agent locally: `/copilot-studio:clone-agent`
3. Edit topics, knowledge sources, instructions per `agents/triage/SPEC.md`. **Set `aiSettings.useModelKnowledge: true`** (needed for the agent to compose PJ proposals from its own reasoning — see memory `reference_mcs_useModelKnowledge_blocks_pure_instruction_generation.md`).
4. Push: `/copilot-studio:manage-agent` push.
5. **Publish** (not just save-draft — MCS connector requires published agent — see memory `reference_mcs_connector_requires_published_agent.md`).
6. Build the orchestrator flow per `flows/triage-orchestrator/SPEC.md` — Until-wraps-agent-call pattern with Switch on terminal outcome AFTER Until (per memory `feedback_failure_handler_pattern_for_agent_loops.md`).
7. Deploy via FlowStudio MCP `add_live_flow_to_solution` after creating the flow shell. If the flow is already only in Default/Active solution containers, use Dataverse `AddSolutionComponent` to add the workflow component to a named unmanaged solution before Copilot Studio binding.

**Verify:** create a Tickets row via PnP. Wait 3 min. Check orchestrator flow run. Check the agent's response in `OrchestratorReply` field of the Tickets row.

### Phase 5 — SP-IT-Identity Entra app (~15 min)

```powershell
az account set --subscription "00000000-0000-4000-8000-000000000037"

# Create app + SP
$app = az ad app create --display-name "SP-IT-Identity" --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$sp = az ad sp create --id $app.appId | ConvertFrom-Json

# Add Graph permissions
$graphResourceId = "00000003-0000-0000-c000-000000000000"
$userReadWriteAllId = "00000000-0000-4000-8000-000000000026"
$userAuthMethodId  = "00000000-0000-4000-8000-000000000019"
az ad app permission add --id $app.appId --api $graphResourceId `
    --api-permissions "$userReadWriteAllId=Role" "$userAuthMethodId=Role"
az ad app permission admin-consent --id $app.appId

# Generate 1-year client secret
$secretJson = az ad app credential reset --id $app.appId --display-name "pilot-secret" --years 1 | ConvertFrom-Json
# Save $secretJson.password somewhere safe — needed for KV upload next
```

### Phase 6 — Assign Password Administrator role to SP-IT-Identity

The script that gets this right is documented in memory `reference_graph_password_reset_needs_directory_role.md`. Summary:

```powershell
Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory"

# Activate Password Administrator role from template (idempotent)
$tplId = "00000000-0000-4000-8000-000000000032"  # Password Administrator template
$role = Get-MgDirectoryRole -Filter "RoleTemplateId eq '$tplId'" -ErrorAction SilentlyContinue
if (-not $role) {
    $role = New-MgDirectoryRole -BodyParameter @{ roleTemplateId = $tplId }
}

# Assign SP to role
$spObjectId = "<SP-IT-Identity SP object id>"
New-MgDirectoryRoleMemberByRef -DirectoryRoleId $role.Id -BodyParameter @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$spObjectId"
}
```

**Wait 5-10 min for propagation.** Smoke-test:

```powershell
$body = @{
    grant_type    = "client_credentials"
    client_id     = "00000000-0000-4000-8000-000000000014"
    client_secret = "<the-secret>"
    scope         = "https://graph.microsoft.com/.default"
}
$tokenResp = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/26e65220-.../oauth2/v2.0/token" -Body $body
# Decode the JWT, verify roles claim contains User.ReadWrite.All AND UserAuthenticationMethod.ReadWrite.All
```

### Phase 7 — Azure Key Vault (~10 min)

```bash
az group create --name rg-itsm-pilot --location australiaeast
az keyvault create --name kv-itsm-demo-XXXX --resource-group rg-itsm-pilot --location australiaeast --enable-rbac-authorization true --sku standard

# Grant Catherine Secrets Officer
az role assignment create --assignee-object-id <catherine-obj-id> --assignee-principal-type User \
    --role "Key Vault Secrets Officer" \
    --scope "/subscriptions/<sub>/resourceGroups/rg-itsm-pilot/providers/Microsoft.KeyVault/vaults/<kv-name>"

# Wait 15s for RBAC propagation, then upload secret
az keyvault secret set --vault-name <kv-name> --name "SP-IT-Identity-ClientSecret" --value "<the-secret-from-phase-5>"
```

### Phase 8 — Power Automate Key Vault connection (manual, 1 min, Catherine)

OAuth-based PA connections require interactive consent. There is no programmatic path.

1. Open https://make.powerautomate.com → Flow Studio Demo env → Connections → New connection.
2. Search "Azure Key Vault" → click.
3. **Auth type:** Default Microsoft Entra ID application for OAuth.
4. **Vault name:** `kv-itsm-demo-XXXX` (the one from Phase 7).
5. Sign in with Catherine's account → Create.

Note the connection id (e.g. `3902492e65ec448ea29a4c6752190756`) for use in flow definitions.

### Phase 9 — Identity Executor flow (~30 min)

The flow shell + definition is in `flows/executors/identity/definition.json`. Deploy via PA REST API (FlowStudio MCP rejects nested-object definitions when called from Claude Code — see memory `reference_flowstudio_mcp_definition_string_rejection.md`).

```powershell
$paToken = az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv
$envName = "00000000-0000-4000-8000-000000000045"
$defJson = Get-Content "flows/executors/identity/definition.json" -Raw
$def = $defJson | ConvertFrom-Json -Depth 50

$body = @{
    properties = @{
        displayName = "ITSM-Identity-Executor"
        definition = $def
        connectionReferences = @{
            shared_sharepointonline = @{
                connectionName = "f1550c57e913479793d6de83b61fa1b0"
                id = "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
            }
            shared_keyvault = @{
                connectionName = "<kv-connection-id-from-phase-8>"
                id = "/providers/Microsoft.PowerApps/apis/shared_keyvault"
            }
        }
    }
} | ConvertTo-Json -Depth 50 -Compress

$h = @{ Authorization = "Bearer $paToken"; 'Content-Type' = "application/json" }
$resp = Invoke-RestMethod -Method POST -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envName/flows`?api-version=2016-11-01" -Headers $h -Body $body
Write-Host "Created flow: $($resp.name)"
```

**Verify:** create a PJ row via Graph API (NOT PnP — see Critical Gotchas) with `JobStatus=Dispatched`, `JobType=identity.resetPassword`, `TargetJson={"type":"user","upn":"<test-user>"}`. Wait 3 min. Check executor run. Verify PJ row → Succeeded with GraphRequestId + ResultJson populated. Verify the test user's password was actually reset (sign-in attempt forces password change).

### Phase 10 — Dispatcher flow (~30 min)

Same deploy pattern as Phase 9. Definition in `flows/dispatcher/definition/definition.json`. HTTP POST trigger.

After deploy, get the trigger URL via `mcp__flowstudio__get_live_flow_trigger_url` — record it for the Approval-Bridge to call.

**Verify (manual smoke test):**

```powershell
$dispatcherUrl = "<trigger-url>"
# Create a PJ row in Proposed state via Graph API
# POST to dispatcher with the PJ id
$body = @{
    pjId = <pj-id>
    idempotencyKey = "<guid>"
    callerUpn = "catherine.han@flowstudio.app"
    approverUpn = "catherine.han@flowstudio.app"
    approvalSessionId = "<guid>"
    jobType = "identity.resetPassword"
    correlationId = "<guid>"
} | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri $dispatcherUrl -Body $body -ContentType "application/json"
# Expect 202 with { idempotent: false, pjId, status: "Dispatched", ... }
```

### Phase 11 — Approval-Bridge flow (~20 min)

Same deploy pattern. Definition in `flows/approval/definition.json`. SP polling trigger on Approvals list.

**The dispatcher trigger URL is hardcoded in the bridge's `Call_Dispatcher` action.** Update before deploy.

**Verify E2E (the closing-the-loop demo):**

```powershell
# 1. Insert a Tickets row (via Graph API, Editor=Catherine) — INC2605...
# 2. Insert a Provisioning Jobs row in AwaitingApproval state (via Graph API) — references the ticket
# 3. Insert an Approvals row (via Graph API), SessionState=Approved, LinkedJobId=<JobId>
# 4. Wait 3-6 min for bridge to poll
# 5. Verify chain:
#    - Bridge run Succeeded
#    - Dispatcher run Succeeded (202)
#    - PJ row JobStatus=Dispatched
#    - Executor run Succeeded
#    - PJ row JobStatus=Succeeded with GraphRequestId + ResultJson
#    - Approvals row CompletedAt populated
#    - Test user's password reset live in Entra
```

---

## 6. Critical gotchas (must read before testing)

| # | Gotcha | Symptom | Fix | Memory ref |
|---|---|---|---|---|
| 1 | **PA SP triggers filter App-identity edits** | Bridge / Executor / Orchestrator never fire on PnP-cert-inserted test rows | Use Graph API with USER token to insert/update test rows, or PnP `-Interactive` | `reference_pa_sp_trigger_filters_app_identity.md` |
| 2 | **Graph perms ≠ data-plane authorization for password reset** | 403 `Authorization_RequestDenied` from Graph despite `User.ReadWrite.All` | Assign Password Administrator directory role to the SP | `reference_graph_password_reset_needs_directory_role.md` |
| 3 | **PA secureData allowlist per action type** | "InvalidSecureDataConfiguration" on Compose/ParseJson | Compose/ParseJson accept only `["inputs"]`; HTTP/OpenApiConnection accept both | `reference_pa_securedata_per_action_type.md` |
| 4 | **FlowStudio MCP `update_live_flow` rejects nested-object definitions** when called from Claude Code | "definition must be a JSON object, not a string" | Bypass with PA REST API direct POST | `reference_flowstudio_mcp_definition_string_rejection.md` |
| 5 | **PA flow create uses POST, not PUT** | 404 on PUT to `/flows/{guid}` | POST to `/flows` (no guid) | `reference_pa_rest_api_create_flow.md` |
| 6 | **Catherine has Owner only on MPN sub** | "AuthorizationFailed" creating RG in PAYG sub | Switch to MPN sub `a45a0c43-...` | `reference_az_subscription_rights_contoso.md` |
| 7 | **PatchItem requires ALL SP-required fields** | Validation error during flow design or runtime | Ferry every required field through from trigger output, even if not changing | `reference_patchitem_requires_all_required_fields.md` |
| 8 | **MCS connector requires PUBLISHED agent** | "Agent is not published" | Hit Publish in Copilot Studio portal; push-to-draft is not enough | `reference_mcs_connector_requires_published_agent.md` |
| 9 | **MCS GenerativeAIRecognizer needs natural-language trigger phrases** | Bracketed tokens like `[TRIAGE_REQUEST]` fall to Fallback | Use natural English phrases for triggers | `reference_mcs_intent_recognition_natural_language.md` |
| 10 | **`aiSettings.useModelKnowledge=false` blocks pure-instruction generation** | Agent can't emit JSON-from-instructions; falls to Fallback | Set true if you need composition without grounding | `reference_mcs_useModelKnowledge_blocks_pure_instruction_generation.md` |
| 11 | **Copilot Studio Power Fx braces gotcha** | `{placeholder}` in agent instructions parses as Power Fx → compile fail | Use `()` or `<>` for placeholder text | `feedback_copilot_studio_powerfx_braces.md` |
| 12 | **clone-agent overwrites local topics** | Local topics deleted after pull | Push BEFORE pull; treat clone/pull as destructive | `reference_clone_agent_overwrites_local.md` |
| 13 | **SP Lookup field syntax in PA** | "field not found" or wrong row updated | Use `item/<Field>/Id` with integer SP id; not `LookupId` or `Id` suffix | `reference_pa_sp_lookup_field_syntax.md` |
| 14 | **PnP user-field syntax** | Cryptic "user not found" with integer ID | Pass email string (`'user@domain.com'`), not `LookupId` integer | `reference_pnp_addlistitem_user_field_email_string.md` |
| 15 | **PA Until > Switch > OpenApiConnection nesting** | Validation rejects `authentication`, demands `connectionReferenceName` | Make flow solution-aware OR restructure to flatten | `reference_pa_until_switch_openapi_nesting_constraint.md` |
| 16 | **Triage agent needs explicit tenant identity grounding** | Agent mis-classifies internal sites as cross-tenant | Hardcode `ORG CONTEXT` block in instructions; long-term: CMDB seed | `reference_agent_needs_tenant_identity_grounding.md` |
| 17 | **JobTypes registry uses camelCase** | Mis-cased payload returns 200 with status Rejected | Use `identity.resetPassword`, not `identity.reset_password` | `reference_jobtypes_camelcase.md` |
| 18 | **Copilot Studio flow actions need named solution membership** | Agent publish fails; `InvokeFlowAction` / `InvokeFlowTaskAction` diagnostics show `CloudFlow ... not found` | Add the cloud-flow workflow component to a named unmanaged solution; Default/Active/Common solution membership is not enough | See details below |

### Gotcha 18 detail: Copilot Studio flow binding needs a named solution

Copilot Studio can reject a Power Automate flow action even when the flow exists, is started, and is visible in Power Automate if the flow is only present in platform default solution containers.

Symptom:

- Copilot Studio publish fails after adding an `InvokeFlowAction` or `InvokeFlowTaskAction`.
- Publish diagnostics show `InvalidReferenceError` for `referenceType: CloudFlow`.
- The error can look like `CloudFlow with id '<flow id>' not found`.

Root cause:

- The flow is not in a named unmanaged solution.
- Membership in only `Active Solution`, `Default Solution`, or `Common Data Services Default Solution` is not enough.
- `ITSM-ProposeAction` initially existed as a started Dataverse workflow, but solution membership showed only `Active`, `Default`, and `Cr15280` (`Common Data Services Default Solution`), so Copilot Studio could not resolve it as a bindable cloud-flow tool.

Fix:

- Add the existing workflow component to a named unmanaged solution such as `FS Demo`, or the same named solution used to manage the Copilot Studio agent.
- If the flow is not solution-aware at all, use Flow Studio MCP `add_live_flow_to_solution`.
- If Flow Studio MCP returns `AlreadyInSolution`, the flow is probably already only in Default/Active solution containers. Add the existing Dataverse workflow component to the named solution with Dataverse `AddSolutionComponent`.
- Cloud flows are Dataverse solution component type `29`.

Verification:

- Query Dataverse `solutioncomponents` for the workflow ID.
- Resolve `_solutionid_value` against `solutions`.
- Confirm at least one membership points to a named unmanaged solution, not only `Active`, `Default`, or `Cr15280`.
- For `ITSM-ProposeAction`: Power Automate flow ID `00000000-0000-4000-8000-000000000048`, Dataverse workflow ID `00000000-0000-4000-8000-000000000036`, named solution `FSDemo` / `FS Demo`, solution component ID `00000000-0000-4000-8000-000000000006`.

---

## 7. Test procedures

### 7.1 Smoke test — Identity-Executor (after Phase 9)

```powershell
# Insert PJ row directly in Dispatched state (via Graph API as user — NOT PnP cert!)
$gToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
$siteId = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/ITSM" -Headers @{Authorization="Bearer $gToken"}).id
$listId = ((Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$filter=displayName eq 'Provisioning Jobs'" -Headers @{Authorization="Bearer $gToken"}).value)[0].id

$body = @{
    fields = @{
        Title = "PJ-SMOKE-$(Get-Date -Format 'yyMMddHHmmss')"
        JobId = "PJ-SMOKE-$(Get-Date -Format 'yyMMddHHmmss')"
        JobType = "identity.resetPassword"
        ParentTicketLookupId = <existing-ticket-id>
        JobStatusValue = "Dispatched"
        CallerUpn = "catherine.han@flowstudio.app"
        TargetJson = '{"type":"user","upn":"arwen@contoso.onmicrosoft.com"}'
        IdempotencyKey = [guid]::NewGuid().ToString()
        CorrelationId = [guid]::NewGuid().ToString()
        ProposedAt = (Get-Date -AsUTC).ToString("o")
    }
} | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items" -Headers @{Authorization="Bearer $gToken"; 'Content-Type'='application/json'} -Body $body
```

Wait 3 min. Use FlowStudio MCP `get_live_flow_runs` then `get_live_flow_run_action_outputs` to verify Patch_Graph_User succeeded with HTTP 204.

### 7.2 E2E demo — Approval → Dispatch → Execute (after Phase 11)

See Phase 11 verification block above. The Approvals row MUST be edited by a USER identity (Graph API with user token), not PnP cert.

### 7.3 Replay protection

Re-fire the dispatcher with the same `idempotencyKey`:
- Expected: 200 with `{ idempotent: true, originalPjId: <previous>, ... }`
- Verify no second Graph PATCH call.

### 7.4 Kill switch

```powershell
# Set Config!KillSwitch = "true" via Graph (user identity)
# POST to dispatcher
# Expected: 503 with { error: "kill_switch", ... }
# Reset Config!KillSwitch = "false" after testing
```

---

## 8. Deployed artifact glossary

### 8.1 Power Automate flows (Flow Studio Demo env `d0897dde-...`)

| Flow | id | Purpose |
|---|---|---|
| ITSM-Triage-Orchestrator | `00000000-0000-4000-8000-000000000030` | Tickets row → calls Triage Agent → records reply |
| ITSM-Identity-Executor | `00000000-0000-4000-8000-000000000043` | PJ Dispatched → Graph password reset |
| ITSM-Dispatcher | `00000000-0000-4000-8000-000000000033` | HTTP POST → validates + patches PJ to Dispatched |
| ITSM-Approval-Bridge | `00000000-0000-4000-8000-000000000001` | Approvals row state change → calls Dispatcher |

### 8.2 SharePoint lists (`/sites/ITSM`)

18 solution lists provisioned (17 via `provision-lists.ps1` + License Costs). Schema in `sharepoint-itsm-schema.xlsx` and `infra/sharepoint/lists/*.ps1`. Critical ones:

| List | Role |
|---|---|
| Tickets | The ticket (Incident / Request / Problem / Change), including ticket-type validation state |
| Provisioning Jobs | Audit row per privileged write (the executor's source of truth) |
| Approvals | Approval session per PJ |
| ApprovalStages | Per-stage decisions (provisioned, not used in pilot) |
| ApprovalPolicies | Multi-stage approval policy definitions (seeded, not used in pilot) |
| JobTypes | Registry of valid jobType values (must be `active`) |
| PriorityMatrix | Impact × Urgency → Priority lookup |
| Knowledge Base | KB articles (empty in pilot — Phase 2 seeding) |
| Configuration Items | CMDB (empty in pilot — Phase 2 seeding) |
| Categories | Ticket taxonomy |
| Service Catalog | Request types |
| Config | KillSwitch + global toggles |
| Request Items | RITM rows for catalog requests |
| Tickets-Archive | Closed > 12 months (archival pending) |
| Categories-Routing | Auto-assignment rules |
| Watchers | User subscriptions to tickets |

### 8.3 Copilot Studio agents

| Agent | schemaName | Purpose |
|---|---|---|
| Helpdesk Triage Agent | `cr1c2_helpdesktriage` (placeholder; replace with real) | Classifies tickets, attempts deflection, proposes actions |
| Self-Service Resolver | (deferred) | Pure KB Q&A; build when KB has 30+ articles |

---

## 9. Phase 2 backlog (production hardening)

What's deliberately deferred. Each is independently addable per the migration paths in `decisions/0001-dispatcher-host.md` and `flows/dispatcher/contract.md`.

1. **Azure Functions `jwt-sign` + `jwt-validate`** — needed when dispatcher accepts non-PA callers
2. **HSM-backed JWT signing key** in Key Vault (`kv-itsm-prod` separate from pilot KV)
3. **Azure Table Storage `IdempotencyKeys` + `JwtReplay`** — replaces SP race-vulnerable check
4. **Service Bus `provisioning-jobs` topic + 6 per-executor subscriptions** — Graph throttling smoothing
5. **Application Insights `appi-itsm-prod`** — replaces PA run history (28-day cap) as primary audit
6. **6 separate executor SPs + matching directory roles** — Identity / Groups / Licensing / Exchange / SharePoint / Teams
7. **Multi-stage Approval flow** — replaces `ITSM-Approval-Bridge` with full policy engine
8. **`dlq-monitor` flow** — scans Service Bus DLQ for failures
9. **Cert-based auth** — replaces 1-year client secrets; sets up rotation calendar
10. **App Insights structured events** — `dispatcher.received`, `dispatcher.completed`, `dispatcher.rejected`, `executor.started`, `executor.completed`, `executor.failed`
11. **CMDB seed** — Intune export + business services manual entries
12. **KB seed** — 30-50 articles minimum before deflection rate is meaningful
13. **SharePoint groups + permission split** — IT-ITSM-Admins, IT-Approvers-Backup, Change-Advisory-Board, HR-Confirmation-Approvers, ITSM-Agent-Users
14. **Adaptive Cards wired** — 6 templates exist (`notifications/cards/`); wire to flow notification actions
15. **SLA timer flow** (Week 6) — 75% warning + 100% breach
16. **Archival flow** (Week 6) — Closed > 12 months → Tickets-Archive
17. **Major Incident detector** (Week 6) — webhook cluster detection
18. **Power BI reporting** — SLA attainment, agent accuracy, top categories, top failures
19. **Backup human custodian** for SP certs and KV (recommended: John Liu)
20. **Rotation reminder flow** — fires 14/7/1 days before any cert/secret expiry
21. **Ticket type validation gate** — portal Incident/Request confirmation plus `ITSM-Ticket-Type-Validator` flow and downstream trigger guards

---

## 9b. Phase 3 backlog (functional coverage to ready-to-market)

Surfaced 2026-05-02 after gap analysis against `servicenow-itsm-ticketing-report.md` §4.1. Phase 2 covers production hardening. Phase 3 covers the functional + UX surface needed to call the product marketable to a paying customer.

| # | Item | Why it matters | Status |
|---|---|---|---|
| 21 | **Category + subcategory taxonomy to research parity** — 12 top-level categories with ~50 subcategories + cascade lookup | Today: 13 cats, 0 subcats, free-text Subcategory. Research baseline §4.1 has structured 12+50 taxonomy with category→subcategory cascade | ✅ Phase 3 deliverable 1 — see `infra/sharepoint/lists/01b-subcategories.ps1` + `seed-subcategories.ps1` (2026-05-02) |
| 22 | **Service Catalog with 5-10 seeded items + RITM/SCTASK working** | Today: empty Service Catalog list, no RITM-generator flow, no SCTASK orchestration. Research §2.4 — Catalog is half of any ITSM product | ✅ Phase 3 deliverable 2 — see `agents/service-catalog/seed-catalog-items.ps1` + `flows/ritm-generator/` + `flows/sctask-orchestrator/` (2026-05-02) |
| 23 | **5 more executors + JobTypes** (groups / licensing / exchange / sharepoint / teams) | Today: only identity executor running. Other 11 JobTypes have no executor wired. Without these, "automation" is just password reset | ✅ Phase 3 deliverable 3 — see `infra/azure/provision-5-executors.ps1` + `flows/executors/` (2026-05-02) |
| 24 | **Multi-tenant installer / template package** | Today: hardcoded to contoso. KV name, Entra app IDs, site URL, connection IDs all per-tenant constants. Customer onboarding requires hand-rolled SP+KV+Entra app provisioning per tenant | Backlog |
| 25 | **End-user surface** — at minimum a Power Apps form (or Teams app or Employee Center equivalent) | Today: end users insert SP rows directly. No structured intake UX, no catalog browse, no "my open tickets" view | Backlog |
| 26 | **Email-to-ticket ingestion** (most common intake channel in real shops) | Today: SP form is canonical intake per `feedback_tickets_must_be_structured_input.md`. Real customers also need email | Backlog |
| 27 | **Power BI reporting pack** — SLA attainment, MTTR, agent accuracy, top categories, top failures, deflection rate | Today: no dashboards. "Reporting & Analytics" is also a missing category in our seed | Phase 2 #18 (consolidate) |
| 28 | **Problem Management module + Change Management proper records** | Today: TicketType has Choice value `Problem` and `Change` but no PRB-specific fields (root cause, known errors), no CHG fields (risk, plans, CAB). Research §2.2 + §2.3 | Backlog |
| 29 | **SLA engine** — `task_sla` per-ticket timer rows + breach detection flow | Today: hours stored on Priority Matrix, never consumed. Phase 2 #15 names a flow but no design yet | Phase 2 #15 (consolidate) |
| 30 | **Service Catalog Order Guides + Standard Change Catalog** | Today: not modeled. Research §2.4 — "New Hire" bundles laptop + phone + access + software via Order Guide; Standard Change Catalog is pre-approved repeatable changes (e.g., "Restart IIS pool") | Backlog |

### Phase 3 deliverable rationale (why these 3 first)

Per Catherine 2026-05-02: items 21, 22, 23 are the minimum to demo as a real ITSM product, not just a password-reset bot. Categories + Service Catalog give the customer-visible surface; 5 more executors give automation depth beyond the single demo path. Items 24-26 (multi-tenant, end-user UX, email intake) are the *next* gate — without them you cannot install at a customer.

---

## 10. Cross-references

### Living docs (kept current)
- `IMPLEMENTATION-PLAYBOOK.md` (this file) — single playbook for fresh agents
- `flows/CURRENT-STATUS.md` — authoritative current deployment status, Day 4 task counts, blockers, and evidence pointers
- `DEPLOYMENT.md` — runbook with phase-by-phase status
- `README.md` — project overview + repo layout
- `USER_GUIDE.md` — end-user, approver, and Level 1 support guide
- `ADMIN_GUIDE.md` — day-to-day admin operations guide
- `TROUBLESHOOTING_GUIDE.md` — Day 2 troubleshooting and re-drive guide
- `DEPLOYMENT.md` — active deployment runbook after consolidation

### Design memos (canonical, with pilot annotations)
- `itsm-design-memo.md` — full design intent (was .docx, now Markdown)
- `decisions/0001-dispatcher-host.md` — ADR with 4 hardening items + status
- `flows/dispatcher/contract.md` — full dispatcher API contract + pilot deviations
- `flows/executors/contract.md` — symmetric executor contract
- `flows/approval/spec.md` — full Approval flow spec + pilot bridge deviations
- `agents/triage/SPEC.md` — Triage Agent spec
- `infra/sharepoint/README.md` — SharePoint provisioning runbook

### Visual artifacts
- `itsm-ai-workflow-flowchart.pdf` / `.png` — original 6-stage design diagram (NOT updated for pilot deviations; see §2.2 above for pilot mermaid)
- `sharepoint-itsm-schema.xlsx` — 16-list SharePoint schema (canonical)
- `servicenow-itsm-ticketing-report.md` — research baseline for ServiceNow modules being mirrored

### Memory (auto-loaded)
- Memory index: `~/.claude/projects/c--Users-ninih-GitHub-Copilot-Studio/memory/MEMORY.md`
- Every gotcha in §6 above has a corresponding memory file with full context + reproduction steps

---

## 11. Authoring credit

- Architecture and system design: Catherine Han (2026-04-29)
- Pilot implementation Week 1-2 (overnight build + closeout): autonomous build per Catherine's directive (2026-04-29 to 2026-05-01)
- Playbook author: Claude Code (from this session's accumulated state)
