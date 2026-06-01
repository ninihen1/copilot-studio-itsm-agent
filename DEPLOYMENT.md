# Deployment Runbook

Step-by-step manual setup for the M365 ITSM build, in dependency order. Some steps are unavoidable manual portal clicks; others are scripted. Each step's owner is named.

**Target environment for pilot:** Flow Studio Demo (Power Platform environment, per Catherine 2026-04-29). Env id: `00000000-0000-4000-8000-000000000045`.

---

## Deployment phases

| Phase | Status | Notes |
|---|---|---|
| 0 Prerequisites | ✅ done | contoso tenant, `/sites/ITSM` provisioned, PnP/Az/Graph modules installed |
| 1 Entra apps | ⏳ partial | **SP-IT-Identity** (`<app-id>`) registered + admin-consented + **Password Administrator** directory role assigned. Other 5 SPs deferred to Week 5+ when their executors are built. SP-IT-Provisioning (cert auth, used by PnP scripts) `<app-id>` already in place. |
| 2 Azure infra | ⏳ minimal | **Key Vault `kv-itsm-demo`** (RG `rg-itsm-pilot`, MPN sub `a45a0c43-...`, australiaeast). Storage Account / Service Bus / App Insights / jwt-sign Function NOT deployed — see "Pilot deviations" below. |
| 3 SharePoint provisioning | ✅ done | All 18 solution lists provisioned (17 via provision-lists.ps1 + License Costs) + seed scripts run (Priority Matrix, Approval Policies, JobTypes, Config-KillSwitch) |
| 4 SharePoint groups | ❌ pending | Catherine is sole admin today; pilot uses single approver. Groups still need to be created + populated |
| 5 Power Automate flows | ⏳ partial | **Deployed:** `ITSM-Identity-Executor` (`c06e63bf-...`), `ITSM-Dispatcher` (`97a4c109-...`), `ITSM-Approval-Bridge` (`05b00ed2-...`), `ITSM-Triage-Orchestrator` (`8214cc66-...`). **Pending:** other executors (Week 5), archival/SLA/MI flows (Week 6) |
| 6 Copilot Studio agents | ✅ Triage Agent live | Self-Service Resolver deferred until KB matures |
| 7 Channels | ⏳ partial | Triage Agent in Teams; production channel rollout pending |
| 8 Verification | ✅ identity.resetPassword E2E proven | PJ 13 / 14 / 16 all reset `arwen@contoso.onmicrosoft.com` via real Graph PATCH 204 |
| 9 Operations | ⏳ partial | Kill switch deployed + tested; cert rotation calendar + DLQ monitor pending |

### Pilot deviations from §3-7 of the design memo

To prove the loop end-to-end without standing up four Azure resources Catherine doesn't need yet, the pilot simplifies in these specific ways. Each is reversible per the migration paths in `decisions/0001-dispatcher-host.md`:

| Production design | Pilot shortcut | Why acceptable for pilot |
|---|---|---|
| **JWT signed by Approval flow, validated by Dispatcher** | Dispatcher trusts the SAS URL on its HTTP trigger. No JWT. | Pilot has one approver path (Catherine), low blast radius. JWT becomes critical when the Dispatcher accepts calls from outside PA. |
| **Azure Table Storage `IdempotencyKeys` with `If-None-Match: *`** | Dispatcher queries SP `Provisioning Jobs` for duplicate `IdempotencyKey` field | SP eventual-consistency means two truly-simultaneous dispatches could both pass. Race-vulnerable but acceptable single-tenant pilot. Production: Table Storage. |
| **Service Bus topic + 6 per-executor subscriptions** | Executor flow polls the `Provisioning Jobs` SP list directly with a 3-min trigger | Removes Graph-throttling smoothing and FIFO-per-ticket session ordering. Acceptable at pilot volumes; visible in audit row regardless. |
| **Six dedicated executor SPs** (one per Graph scope family) | Pilot has only **SP-IT-Identity** for `identity.*` JobTypes | Each new executor adds ~30 min: copy the Identity executor pattern + new SP + matching directory role. |
| **Cert in HSM-backed Key Vault** | Pilot uses 1-year client secret in standard KV | Cert rotation runbook is a separate work-item; secret in KV beats secret-in-flow-body. |
| **App Insights primary audit + structured custom events** | PA run history (28-day cap) + SP audit row in `Provisioning Jobs` | Sufficient for first-quarter spot-checks. Production must add App Insights before SOC 2 timeline starts. |
| **DLQ + scheduled re-driver flow** | Failed runs sit in `JobStatus=Failed` with `ErrorJson`; manual re-drive only | At pilot volumes, manual re-drive is fine. Production needs the `dlq-monitor` per `flows/dispatcher/contract.md` §5.4. |
| **Approval flow with policy stages (Manager / IT-Owner / CAB)** | `ITSM-Approval-Bridge` listens to `Approvals` SP list state changes — single approver flips the row to `Approved` | Pilot has no multi-stage policy; ApprovalStages list is provisioned but empty. Production needs the approval-policy engine per `flows/approval/spec.md`. |

### Critical gotchas discovered during build (read before testing)

1. **PA `GetOnUpdatedItems` SP triggers silently filter out App-identity edits.** Any test row inserted via PnP-cert will NOT trigger the bridge or executor. Use Graph API with a user token, or PnP `-Interactive`. See memory `reference_pa_sp_trigger_filters_app_identity.md`.
2. **Graph `User.ReadWrite.All` Application permission alone does NOT permit password resets.** SP must also be assigned the `Password Administrator` (or higher) directory role. Returns 403 `Authorization_RequestDenied` until role propagates (~5-10 min). See memory `reference_graph_password_reset_needs_directory_role.md`.
3. **PA `Compose` and `ParseJson` actions reject `["inputs", "outputs"]` in `runtimeConfiguration.secureData.properties`.** Only `["inputs"]` is valid. Use HTTP or OpenApiConnection actions for secret-handling that needs both redacted. See memory `reference_pa_securedata_per_action_type.md`.
4. **FlowStudio MCP `update_live_flow` tool rejects `definition` parameter as a string when called from Claude Code.** Bypass with PA REST API direct POST. See memory `reference_flowstudio_mcp_definition_string_rejection.md`.
5. **Catherine has Owner rights only on the MPN subscription** (`a45a0c43-...`) in contoso tenant. Use that sub for any `az` resource creation. See memory `reference_az_subscription_rights_contoso.md`.

---

## Phase 0 — Prerequisites (~30 min)

### 0.1 Decide tenant URL

You'll see `https://contoso.sharepoint.com/sites/ITSM` in dozens of files. After deciding, run:

```powershell
# From repo root
$tenant = 'YOUR_TENANT'
Get-ChildItem -Recurse -Include *.json,*.yml,*.yaml,*.md,*.ps1 | ForEach-Object {
    (Get-Content $_.FullName -Raw) -replace 'CHANGE_ME\.sharepoint\.com', "$tenant.sharepoint.com" |
        Set-Content $_.FullName
}
```

Caveat: this also updates documentation. Review the diff before committing.

### 0.2 Install required local tooling

- PowerShell 7+
- `Install-Module PnP.PowerShell -MinimumVersion 2.4.0`
- `Install-Module Az.Accounts, Az.KeyVault`
- `Install-Module Microsoft.Graph.Sites, Microsoft.Graph.Authentication`
- VS Code Copilot Studio extension (latest)

### 0.3 Create the SharePoint site

1. SharePoint Admin Center -> Sites -> Create -> **Team site (no Microsoft 365 group)**
2. Name: `ITSM`
3. URL: `/sites/ITSM`
4. Owner: Catherine Han
5. Save and wait for provisioning (~1 min)

The provisioning scripts won't create the site — only its lists.

---

## Phase 1 — Entra app registrations

Seven app registrations target. All admin-consented. **Each executor SP also needs a Directory Role** in addition to its Graph permissions (added 2026-05-01 — Graph perms alone do NOT authorize privileged writes).

| App | Permissions | Directory role | Pilot status | AppId |
|---|---|---|---|---|
| `SP-IT-Provisioning` | `Sites.FullControl.All` (Application) | n/a | ✅ done | `<app-id>` (cert-auth, used by all PnP scripts) |
| `SP-IT-Identity` | `User.ReadWrite.All`, `UserAuthenticationMethod.ReadWrite.All` (Application) | **Password Administrator** | ✅ done 2026-05-01 | `00000000-0000-4000-8000-000000000014` |
| `SP-IT-Groups` | `Group.ReadWrite.All`, `GroupMember.ReadWrite.All` (Application) | **Groups Administrator** | ❌ pending Week 5 | — |
| `SP-IT-Licensing` | `User.ReadWrite.All`, `Organization.Read.All` (Application) | **License Administrator** | ❌ pending Week 5 | — |
| `SP-IT-Exchange` | `Mail.ReadWrite`, `MailboxSettings.ReadWrite`, `User.Read.All` (Application) | **Exchange Administrator** | ❌ Phase 2 (needs EXO PowerShell wrapper) | — |
| `SP-IT-SharePoint` | `Sites.Selected` (NOT FullControl) | **SharePoint Administrator** | ❌ pending Week 5 | — |
| `SP-IT-Teams` | `TeamMember.ReadWrite.All`, `Channel.Create`, `DeviceManagementManagedDevices.ReadWrite.All` | **Teams Administrator** | ❌ Phase 2 | — |

For each new SP, follow the `reference_graph_password_reset_needs_directory_role.md` memory script to activate the matching directory role from template + assign the SP. Role propagation takes ~5-10 min.

**Pilot uses 1-year client secrets stored in Key Vault** (see Phase 2.2). Production should switch to certs in HSM-backed KV.

---

## Phase 2 — Azure infrastructure

### Pilot scope deployed (2026-05-01)

```
Subscription:   Microsoft Partner Network (00000000-0000-4000-8000-000000000037)  ◄ Catherine has Owner only on MPN
Resource group: rg-itsm-pilot (australiaeast)
Key Vault:      kv-itsm-demo (RBAC mode)
Secrets:        SP-IT-Identity-ClientSecret  (1-year, expires 2027-05-01)
RBAC:           Catherine = Key Vault Secrets Officer
```

The PA Key Vault connection runs as Catherine's identity (oauthDefault auth type). Connection ID `<connection-id>` in env `<env-id>`.

### Phase 2 deferrals

The following are scoped for Phase 2 hardening, NOT pilot:

| Resource | Why deferred | When needed |
|---|---|---|
| Storage Account `stitsmidempotency` + `IdempotencyKeys` + `JwtReplay` tables | Pilot uses SP `IdempotencyKey` field query | First contracted customer / SOC 2 timeline |
| Service Bus `sb-itsm-dev` + `provisioning-jobs` topic + 6 subscriptions | Pilot executor polls PJ list directly | Sustained > 5,000 jobs/week or multi-executor fan-out |
| Application Insights `appi-itsm-dev` | Pilot uses PA run history + SP audit row | SOC 2 timeline (28-day cap on PA history is the trigger) |
| Azure Functions `jwt-sign` and `jwt-validate` | Pilot dispatcher trusts SAS URL | First non-PA caller of dispatcher |
| HSM-backed JWT signing key | Same as above | First non-PA caller of dispatcher |
| Cert-based auth (vs. client secret) for executor SPs | Pilot uses 1-year secret in standard KV | Annual cert rotation calendar in production |

### Original spec (production target)

```bash
# Resource group
az group create --name rg-itsm-prod --location australiaeast

# Key Vault (RBAC; HSM-backed)
az keyvault create --name kv-itsm-prod --resource-group rg-itsm-prod --enable-rbac-authorization true

# Upload 7 SP certificates (one per app)
# Generate HSM-backed signing key for JWTs:
az keyvault key create --vault-name kv-itsm-prod --name itsm-approval-signing-prod --kty RSA-HSM --size 2048
```

### 2.3 Storage account for idempotency  *(Phase 2 — not deployed for pilot)*

```bash
az storage account create --name stitsmidempotency --resource-group rg-itsm-dev --sku Standard_LRS
az storage table create --account-name stitsmidempotency --name IdempotencyKeys
az storage table create --account-name stitsmidempotency --name JwtReplay
```

### 2.4 Service Bus  *(Phase 2 — not deployed for pilot)*

```bash
az servicebus namespace create --resource-group rg-itsm-dev --name sb-itsm-dev --sku Standard

az servicebus topic create --resource-group rg-itsm-dev --namespace-name sb-itsm-dev --name provisioning-jobs \
  --enable-duplicate-detection true --duplicate-detection-history-time-window PT10M --enable-partitioning true

# 6 subscriptions, one per executor SP, with SQL filter on Subject
for sub in sub-identity sub-groups sub-licensing sub-exchange sub-sharepoint sub-teams; do
  az servicebus topic subscription create --resource-group rg-itsm-dev --namespace-name sb-itsm-dev --topic-name provisioning-jobs --name $sub
done

az servicebus topic subscription rule create --resource-group rg-itsm-dev --namespace-name sb-itsm-dev --topic-name provisioning-jobs --subscription-name sub-identity --name identity-filter --filter-sql-expression "sys.Subject LIKE 'identity.%'"
# Repeat the rule create for each prefix: groups.%, licensing.%, exchange.%, sharepoint.%, teams.% OR endpoint.%
```

### 2.5 Application Insights  *(Phase 2 — not deployed for pilot)*

```bash
az monitor app-insights component create --app appi-itsm-dev --location australiaeast --resource-group rg-itsm-dev
```

Note the **Instrumentation Key**.

### 2.6 Azure Functions: jwt-sign and jwt-validate  *(Phase 2 — not deployed for pilot)*

These don't exist yet — Catherine to write or scaffold from a starter. Spec:

- **jwt-sign** — input: claims object. Output: JWT string. Uses Key Vault signing key `itsm-approval-signing-dev` via Managed Identity. Pilot Week 2 deliverable.
- **jwt-validate** — input: JWT string + JWKS URL. Output: parsed claims or error. Pure compute, no secrets needed.

Until both Functions exist, Approval flow's `Sign_JWT_And_Dispatch` action and Dispatcher's `Validate_JWT` action are stubs. Acceptable for Week 2 dev environment; **must be deployed before Week 4**.

---

## Phase 3 — SharePoint provisioning (~15 min, Catherine)

```powershell
cd "c:/Users/ninih/GitHub/Copilot Studio/infra/sharepoint"

./provision-lists.ps1 `
    -SiteUrl "https://YOUR_TENANT.sharepoint.com/sites/ITSM" `
    -AppId "<SP-IT-Provisioning client ID>" `
    -KeyVaultName "kv-itsm-dev" `
    -CertificateName "SP-IT-Provisioning" `
    -Verbose
```

Output should report 17 lists either CREATED or NO-CHANGE (re-runs safe). License Costs is provisioned separately by `ensure-license-costs-sync-schema.ps1`.

Then Sites.Selected grant for SP-IT-SharePoint:

```powershell
./grant-sites-selected.ps1 `
    -SiteUrl "https://YOUR_TENANT.sharepoint.com/sites/ITSM" `
    -AppId "<SP-IT-SharePoint client ID>" `
    -AppDisplayName "SP-IT-SharePoint" `
    -Role "fullcontrol"
```

Then seed data:

```powershell
./seed-categories.ps1          -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
./seed-subcategories.ps1       -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
./seed-priority-matrix.ps1     -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
./seed-approval-policies.ps1   -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
./seed-job-types.ps1           -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
./seed-catalog-items.ps1       -SiteUrl ... -AppId ... -KeyVaultName ... -CertificateName SP-IT-Provisioning
```

Note: `seed-job-types.ps1` does two passes. First pass creates rows; second pass links DefaultPolicy lookups. Re-run after `seed-approval-policies.ps1` if it ran out of order.

For Phase 3/3.1 schema updates:

```powershell
# If upgrading an existing pilot where Tickets.Subcategory was text, run dry-run first.
./migrate-tickets-subcategory.ps1 ...
./migrate-tickets-subcategory.ps1 ... -Confirm

# Re-run Tasks provisioning to add Tasks.JobType.
./provision-lists.ps1 ... -ListsToProvision "13"
```

The taxonomy, Service Catalog, RITM/SCTASK, and executor pieces ship as the provisioning scripts in `infra/sharepoint/` and the flow definitions under `flows/`.

---

## Phase 4 — SharePoint groups (~10 min, Catherine, manual)

In `/sites/ITSM`, Site Settings -> People and Groups, create:

| Group | Members |
|---|---|
| `IT-ITSM-Admins` | Catherine + named backup |
| `IT-Approvers-Backup` | IT helpdesk leads (use as fallback approvers) |
| `Change-Advisory-Board` | Senior IT staff and architects (3-5 people) |
| `HR-Confirmation-Approvers` | HR partners who can confirm new hires |
| `ITSM-Agent-Users` | All employees (or a pilot subset). This group has Read on Tickets / KB / CMDB / Categories / Service Catalog. |

Manually adjust permissions on the lists:
- Tickets: ITSM-Agent-Users Read; IT-ITSM-Admins Full Control
- Knowledge Base: ITSM-Agent-Users Read; KB authors Edit
- Configuration Items: ITSM-Agent-Users Read; IT-ITSM-Admins Full Control
- Categories: ITSM-Agent-Users Read; IT-ITSM-Admins Edit
- Service Catalog: ITSM-Agent-Users Read; IT-ITSM-Admins Edit
- Provisioning Jobs: IT-ITSM-Admins Edit only (not visible to general users)
- ApprovalStages: IT-ITSM-Admins Read only
- JobTypes: ITSM-Agent-Users Read; IT-ITSM-Admins Edit
- Config: IT-ITSM-Admins Edit only — break inheritance, very tight perms

---

## Phase 5 — Power Automate flows (~60 min, Catherine)

### 5.1 Create connection references

In Flow Studio Demo environment (https://make.powerautomate.com -> environment switch):

| Connector | Purpose | Sign-in identity |
|---|---|---|
| SharePoint | Generic SP read/write for tickets, JobTypes, Approvals, etc. | Service account in IT-ITSM-Admins |
| Service Bus | Dispatcher publish + executor consume | Managed Identity OR connection string from Key Vault |
| Microsoft Graph (HTTP with Azure AD auth) | Executors — one connection per service principal | One per SP (cert-based) |
| Approvals | Approval cards in Teams | Service account |
| Microsoft Teams | SLA + MI alerts | Service account |
| Office 365 Outlook | Email fallback for approvals | Service account |

### 5.2 Import flow definitions

Pilot order (matches the 6-week plan):

**Week 1 — done:**
- ✅ `flows/triage-orchestrator/` → flow `00000000-0000-4000-8000-000000000030` (deployed)
- ⏳ `flows/permsync/definition.json` (authored, not deployed — pilot uses default SP perms)

**Week 2 — done:**
- ✖ `ProposeAction` — retired 2026-05-30. The agent-callable HTTP intake was superseded by flow-drives-agent (the Triage Orchestrator calls the agent server-side). See ADR 0002.
- ⏳ `flows/loghumanticket/definition.json` (authored, not yet wired)
- ✅ `flows/dispatcher/definition/definition.json` → flow `00000000-0000-4000-8000-000000000033` (deployed; pilot scope per "Pilot deviations" above)
- ✅ `flows/executors/identity/definition.json` → flow `00000000-0000-4000-8000-000000000043` (deployed; identity.resetPassword case proven E2E)
- ✅ `flows/approval/definition.json` → flow `00000000-0000-4000-8000-000000000001` (`ITSM-Approval-Bridge`; pilot replacement for full Approval flow)

**Week 4 — pilot replacement deployed; full version deferred to Phase 2:**
- ⏳ `flows/approval/definition/` (full multi-stage Approval flow with JWT minting — Phase 2)

**Week 5 — pending:**
- 🔜 `flows/executors/groups/definition.json` (clone Identity-Executor, swap Switch case + Graph endpoint, new SP)
- 🔜 `flows/executors/licensing/definition.json` (same pattern)

**Week 6 — pending:**
- 🔜 `flows/archival/definition.json` (test with synthetic data)
- 🔜 `flows/sla-timer/definition.json`
- 🔜 `flows/major-incident/definition.json`

**Phase 3 / 3.1 functional coverage:**
- `flows/ritm-generator/definition.json` — creates Request Items from Request tickets matched to Service Catalog items.
- `flows/ritm-approval/definition.json` — holds RITMs in Pending Approval, sends manager approval, and creates SCTASKs only after approval.
- `flows/sctask-pj-bridge/definition.json` — creates a Provisioning Job for each SCTASK with a non-empty `JobType`.
- `flows/sctask-orchestrator/definition.json` — closes RITMs when all SCTASKs close, then resolves the parent Ticket when all RITMs close.
- `flows/executors/groups/definition.json` — handles `groups.*` jobs after SP-IT-Groups is provisioned.
- `flows/executors/licensing/definition.json` — handles `licensing.*` jobs after SP-IT-Licensing is provisioned.
- `flows/executors/exchange/definition.json` — handles Exchange mailbox permission jobs through the EXO Function wrapper.
- `flows/executors/sharepoint/definition.json` — handles `sharepoint.*` jobs.
- `flows/executors/teams/definition.json` — handles `teams.*` jobs.
- `flows/sla-timer/definition.json` — updates SLA warning and breach state during business hours.
- `flows/archival/definition.json` — copies older closed/resolved tickets to Tickets-Archive and marks originals archived.
- `flows/major-incident/definition.json` — detects related incident clusters and creates Major Incident parent tickets.

Recommended deployment order for Phase 3/3.1 additions:

1. Provision and seed Categories, Subcategories, Service Catalog, JobTypes, and Tasks.JobType.
2. Provision the ticket-type validation columns on Tickets: `TicketTypeValidated`, `TicketTypeValidationStatus`, `TicketTypeValidationReason`, `SuggestedTicketType`, and optionally `TypeOverrideConfirmed`.
3. Deploy `ITSM-Ticket-Type-Validator`.
4. Add validation-complete trigger guards to RITM Generator, Triage Orchestrator, and Major Incident Detector.
5. Deploy or update RITM Generator.
6. Deploy RITM Approval.
7. Deploy SCTASK -> PJ Bridge.
8. Deploy SCTASK Orchestrator.
9. Provision additional executor SPs and Key Vault secrets.
10. Replace executor AppId placeholders and deploy executor flows.
11. Deploy SLA Timer, Archival, and Major Incident Detector.
12. Run the final validation checklist in Phase 8.

**Phase 2 (after pilot):**
- `flows/executors/exchange/definition.json` (requires EXO PowerShell Function)
- `flows/executors/sharepoint/definition.json`
- `flows/executors/teams/definition.json`
- `flows/dlq-monitor/definition.json` (DLQ scanner for failed runs)

### 5.3 Wire each flow's parameters

Per flow:
- `ItsmSiteUrl` → real tenant URL
- `AppInsightsInstrumentationKey` → from Key Vault
- Service Bus parameters → real namespace + topic names
- Connection references → bind to the service-account connections from 5.1

Power Automate import wizard will prompt for connection bindings. Don't sign in as Catherine — use the dedicated service account.

---

## Phase 6 — Copilot Studio agents (~30 min, Catherine)

### 6.1 Helpdesk Triage Agent

1. Power Apps Maker -> switch to Flow Studio Demo
2. Copilot Studio -> New agent -> name **"Helpdesk Triage Agent"** -> Save
3. Note assigned schemaName (e.g., `crXXX_helpdesktriage`)
4. VS Code Copilot Studio extension -> Clone this agent into a temp folder
5. Run a find-and-replace across `agents/triage/Helpdesk Triage Agent/`:
   - `cr1c2_helpdesktriage` -> the real schemaName from step 3
   - `https://contoso.sharepoint.com` -> real tenant URL
6. Wire the LogHumanTicket action to its Power Automate flow. The action's `connectionReference:` field updates automatically when you select the flow in the agent designer. (ProposeAction was retired — the agent no longer calls a write flow; the Triage Orchestrator drives intake.)
7. Add the 6 knowledge sources via the Copilot Studio designer (UI is easier than YAML for SharePoint sources — point each one at the live SP list URL).
8. Confirm `aiSettings.useModelKnowledge: true` when the agent must compose proposal JSON from its own instructions rather than only grounded list data.
9. Use natural-language trigger phrases. Avoid bracket-only trigger tokens.
10. Sync push via the VS Code extension.
11. Publish the agent. Saving or pushing draft is not enough for the Microsoft Copilot Studio connector.
12. Validate with `/copilot-studio:validate`.
13. Test in the Test pane with a sample request: "I forgot my password".

### 6.2 Self-Service Resolver (optional, Week 6+)

Same procedure but skip if KB has < 50 articles. The hand-off target schemaName must match the Triage Agent's (`cr1c2_helpdesktriage` placeholder -> real value).

---

## Phase 7 — Channels (~15 min, Catherine)

Per agent:
1. Channels -> Microsoft Teams -> Enable
2. Channels -> Microsoft 365 Copilot -> Enable
3. Publish (this exposes the agent to Teams users)

Add the agent to a pilot Teams group:
1. Teams -> Apps -> add the agent
2. Pin to a pilot Teams channel for visibility
3. Invite 5-10 pilot users initially

---

## Phase 8 — Verification (~30 min, Catherine + pilot users)

End-to-end test 1: KB deflection (no write expected)
1. Pilot user opens Triage Agent in Teams
2. Says "How do I reset my password?"
3. Agent should return a KB article (assuming one is seeded with relevant content)
4. User clicks "Yes, that helped"
5. Verify: no Tickets row created, no Provisioning Jobs row, App Insights event `triage.deflected`

End-to-end test 2: Reset Password proposal -> approval -> dispatch -> execute
1. Pilot user says "I actually forgot my password"
2. Agent confirms classification, proposes reset
3. User confirms "yes"
4. Verify Tickets row created (Status = AwaitingApproval) + Provisioning Jobs row (Status = Proposed)
5. Manager (you for testing) gets approval card in Teams
6. Manager approves
7. Verify Provisioning Jobs row -> Dispatched -> Queued -> InProgress -> Succeeded
8. Verify Graph API actually reset the password (try signing in with the temp password)
9. Verify all events in App Insights trace

Final validation checklist:

Provisioning checks:

- All SharePoint lists exist.
- Required seed rows exist for Categories, Subcategories, Priority Matrix, Approval Policies, JobTypes, Config, and Service Catalog.
- `Config` contains `KillSwitch=false`.
- Required SharePoint groups exist and sensitive lists are restricted.

Flow checks:

- Triage Orchestrator runs when a ticket is inserted by a user identity.
- Ticket Type Validator marks valid rows complete, auto-reclassifies only deterministic low-risk mismatches, and sends ambiguous rows to caller or service desk confirmation.
- RITM Generator waits for validation before creating RITMs, except for explicitly allowed `TicketSource=ProposeAction` rows.
- Major Incident Detector only clusters validated Incident tickets.
- Dispatcher returns expected responses: `202` dispatched, `200` idempotent replay, `400` invalid payload or jobType mismatch, `409` invalid job state, and `503` kill switch active.
- Identity Executor can reset a test user's password and writes `GraphRequestId`.
- RITM Generator creates a RITM for a Request with a matching Subcategory.
- RITM Approval holds SCTASK creation until approval.
- SCTASK -> PJ Bridge creates a Provisioning Job for tasks with `JobType`.
- SCTASK Orchestrator closes SCTASK parents in order: task -> RITM -> Ticket.

Negative checks:

- Set `KillSwitch=true` and confirm Dispatcher returns `503`.
- Replay a Dispatcher request with the same idempotency key and confirm no second write occurs.
- Submit an inactive or mis-cased job type and confirm rejection.
- Avoid app-only PnP-created rows for trigger smoke tests unless followed by a user-identity edit.

---

## Phase 9 — Operations (ongoing)

### Monitoring

- Power Automate run history: https://make.powerautomate.com -> flows -> per-flow run history
- App Insights: query `customEvents | where name startswith "dispatcher."` for dispatcher events
- Provisioning Jobs SP list: human-readable view of all writes
- DLQ monitor flow (to be written): scans Service Bus dead-letter subscriptions every 5 min

### Cert rotation calendar

Six SP certs at 90-day rotation = one rotation every 15 days. Catherine custodies all six (and JWT signing key). Backup: John Liu (recommended).

A rotation reminder flow should fire 14 / 7 / 1 days before expiry — not yet built.

### Kill switch

The Config SP list, item with `Key = KillSwitch`, `Value = "true"`. Members of IT-ITSM-Admins can edit. The dispatcher checks on every request and returns 503 if active.

To activate:
```
1. Open /sites/ITSM/Lists/Config
2. Edit the KillSwitch item, set Value = "true", set ChangeReason
3. All in-flight requests stay queued; new requests rejected with 503
```

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `provision-lists.ps1` fails on first lookup column | Lookup target list doesn't exist yet | Re-run; the script processes lists in dependency order, but PnP can occasionally race. Re-run is idempotent. |
| Triage Agent test pane returns "tool not found" | An action wasn't wired to its Power Automate flow | Designer -> Actions -> select the action -> set connection reference to the deployed flow |
| Approval card never arrives in Teams | Service account's Approvals connection requires a license | Either give the service account an M365 E3 license OR use a real user's connection (loses turnover resilience) |
| Dispatcher returns 401 on every request | JWT validation Function not deployed | Either deploy `jwt-validate` Function (pilot Week 4) or set `SKIP_JWT_SIG=true` env var on the dispatcher flow (DEV ONLY, never prod) |
| Service Bus messages dead-lettered with `MaxDeliveryCount` | Executor flow throwing on Graph 4xx | Check executor's `Catch_Failure` scope is correctly catching — 4xx should dead-letter, not abandon |
| Tickets list view error "list view threshold exceeded" | Volume crossed 5,000 with non-indexed filter | Ensure indexes are created on TicketState, AssignedTo, OpenedDate per Performance Notes — re-run `provision-lists.ps1` |

## Related operations docs

- `docs/ADMIN_GUIDE.md` — day-to-day ITSM operations after deployment.
- `docs/TROUBLESHOOTING_GUIDE.md` — symptom-first debugging for failed tickets, approvals, SCTASKs, Provisioning Jobs, and Graph calls.
