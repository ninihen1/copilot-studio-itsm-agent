#Requires -Version 7.0

<#
.SYNOPSIS
Phase 3 deliverable 3a — provisions 5 executor service principals in contoso tenant.

Creates: SP-IT-Groups, SP-IT-Licensing, SP-IT-Exchange, SP-IT-SharePoint, SP-IT-Teams.
Each SP gets its own Entra app, Graph application permissions, admin consent,
client secret stored in Key Vault, and the appropriate directory role assignment.

Pattern follows the SP-IT-Identity provisioning per memory `project_itsm_sp_it_identity_app.md`.
Idempotent — re-runs detect existing apps by displayName and skip recreation.

.DESCRIPTION
Why this pattern (least-privilege per executor):

Per design memo §6, each executor runs as its own SP with the MINIMUM Graph
permissions needed for its JobTypes. This way a compromised SP-IT-Licensing
cannot reset passwords; a compromised SP-IT-SharePoint cannot disable users;
and so on. This is the security boundary that lets us delegate to autonomous
flows without giving the agent god-mode.

Required scopes by executor (synthesized from JobTypes seed § seed-job-types.ps1):

| Executor       | Application Permissions (Graph)                                | Directory Role          |
|----------------|----------------------------------------------------------------|-------------------------|
| SP-IT-Groups   | GroupMember.ReadWrite.All, Group.ReadWrite.All                  | Groups Administrator    |
| SP-IT-Licensing| Directory.ReadWrite.All, Organization.Read.All                  | License Administrator   |
| SP-IT-Exchange | Mail.ReadWrite, MailboxSettings.ReadWrite, User.Read.All        | Exchange Administrator  |
| SP-IT-SharePoint| Sites.ReadWrite.All (pilot — production should be Sites.Selected scoped per-site) | (none)        |
| SP-IT-Teams    | Channel.Create, ChannelMember.ReadWrite.All, TeamSettings.ReadWrite.All | Teams Administrator |

Caveats discovered during scoping:

- **Exchange Full Access permissions are not fully Graph-routable.** The Add-MailboxPermission
  cmdlet via Exchange Online PowerShell remains the canonical path. The pilot SP-IT-Exchange
  app uses Graph Mail.ReadWrite + MailboxSettings.ReadWrite for the *settings* changes; for
  Full Access grants, Phase 3.1 will add an Exchange Online PowerShell wrapper Function.
  See `flows/executors/exchange/README.md` deployment notes.
- **SharePoint Sites.Selected** is preferred but requires a per-site grant via Graph
  /sites/{site-id}/permissions. Pilot uses Sites.ReadWrite.All for simplicity; tighten in
  Phase 3.1 once the file-restore flow is hardened.
- **Teams Administrator** directory role is required for cross-tenant team operations
  (channel ops on teams the SP is not a member of). Cheaper alternative: add the SP as
  owner of every team it touches — not viable beyond ~10 teams.

.PARAMETER TenantId
Entra tenant id (default = contoso).

.PARAMETER KeyVaultName
Existing Key Vault to store client secrets (default = `kv-itsm-demo` per memory `project_itsm_sp_it_identity_app.md`).

.PARAMETER ResourceGroup
RG containing the Key Vault (default = `rg-itsm-pilot`).

.PARAMETER SkipExecutors
Comma-separated executor names to skip if you only want to provision a subset.
e.g., -SkipExecutors "Exchange,Teams"
#>

[CmdletBinding()]
param(
    [string]$TenantId = '00000000-0000-4000-8000-000000000009',
    [string]$KeyVaultName = 'kv-itsm-demo',
    [string]$ResourceGroup = 'rg-itsm-pilot',
    [string]$SkipExecutors = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skipList = @($SkipExecutors -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# === Executor catalog ===
# Each entry defines the exact Entra app shape required for one executor.
$executors = @(
    @{
        Name = 'Groups'
        DisplayName = 'SP-IT-Groups'
        Description = 'M365 ITSM Groups Executor — adds/removes group members. PJ-driven. SCOPE: GroupMember.ReadWrite.All + Group.ReadWrite.All.'
        GraphPerms = @(
            'GroupMember.ReadWrite.All'
            'Group.ReadWrite.All'
        )
        DirectoryRole = 'Groups Administrator'
        SecretName = 'SP-IT-Groups-ClientSecret'
    },
    @{
        Name = 'Licensing'
        DisplayName = 'SP-IT-Licensing'
        Description = 'M365 ITSM Licensing Executor — assigns/revokes M365 license SKUs. PJ-driven. SCOPE: Directory.ReadWrite.All + Organization.Read.All.'
        GraphPerms = @(
            'Directory.ReadWrite.All'
            'Organization.Read.All'
        )
        DirectoryRole = 'License Administrator'
        SecretName = 'SP-IT-Licensing-ClientSecret'
    },
    @{
        Name = 'Exchange'
        DisplayName = 'SP-IT-Exchange'
        Description = 'M365 ITSM Exchange Executor — mailbox permission grants + settings. PJ-driven. SCOPE: Mail.ReadWrite + MailboxSettings.ReadWrite + User.Read.All. Full Access grants require EXO PowerShell (Phase 3.1).'
        GraphPerms = @(
            'Mail.ReadWrite'
            'MailboxSettings.ReadWrite'
            'User.Read.All'
        )
        DirectoryRole = 'Exchange Administrator'
        SecretName = 'SP-IT-Exchange-ClientSecret'
    },
    @{
        Name = 'SharePoint'
        DisplayName = 'SP-IT-SharePoint'
        Description = 'M365 ITSM SharePoint Executor — restore-from-recycle-bin + permission grants. PJ-driven. SCOPE: Sites.ReadWrite.All (pilot). Tighten to Sites.Selected per-site in Phase 3.1.'
        GraphPerms = @(
            'Sites.ReadWrite.All'
        )
        DirectoryRole = $null  # SharePoint admin not required for the pilot file-restore use case
        SecretName = 'SP-IT-SharePoint-ClientSecret'
    },
    @{
        Name = 'Teams'
        DisplayName = 'SP-IT-Teams'
        Description = 'M365 ITSM Teams Executor — team/channel ops + member management. PJ-driven. SCOPE: Channel.Create + ChannelMember.ReadWrite.All + TeamSettings.ReadWrite.All + Group.ReadWrite.All.'
        GraphPerms = @(
            'Channel.Create'
            'ChannelMember.ReadWrite.All'
            'TeamSettings.ReadWrite.All'
            'Group.ReadWrite.All'
        )
        DirectoryRole = 'Teams Administrator'
        SecretName = 'SP-IT-Teams-ClientSecret'
    }
)

# Resolve Microsoft Graph SP id (constant per tenant) and its app role catalogue
Write-Host "`n=== Phase 0: resolving Microsoft Graph application permission ids ===" -ForegroundColor Cyan
$graphSpId = (az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv)
if (-not $graphSpId) { throw "Could not resolve Microsoft Graph service principal in tenant $TenantId. Are you signed in to az with the right tenant?" }
Write-Host "  Microsoft Graph SP id: $graphSpId" -ForegroundColor DarkGray

$graphAppRoles = az ad sp show --id $graphSpId --query "appRoles" -o json | ConvertFrom-Json
$graphRoleByValue = @{}
foreach ($role in $graphAppRoles) { $graphRoleByValue[$role.value] = $role.id }

# Resolve directory role definitions (to assign role-by-displayName later)
Write-Host "`n=== Phase 0b: resolving directory role definitions ===" -ForegroundColor Cyan
$gToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $gToken) { throw "Need to be signed in via az to call Graph for role assignment. Run: az login --tenant $TenantId" }
$gh = @{ Authorization = "Bearer $gToken" }
$roleDefs = (Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName' -Headers $gh).value
$roleIdByName = @{}
foreach ($r in $roleDefs) { $roleIdByName[$r.displayName] = $r.id }

$summary = @()
foreach ($exec in $executors) {
    if ($exec.Name -in $skipList) {
        Write-Host "`n=== $($exec.DisplayName) — SKIPPED ===" -ForegroundColor Yellow
        $summary += [pscustomobject]@{ Name = $exec.Name; AppId = '(skipped)'; Status = 'SKIPPED' }
        continue
    }

    Write-Host "`n=== $($exec.DisplayName) ===" -ForegroundColor Cyan

    # 1. Ensure Entra app exists
    $appId = (az ad app list --display-name $exec.DisplayName --query "[0].appId" -o tsv)
    if (-not $appId) {
        Write-Host "  [+] Creating Entra app '$($exec.DisplayName)'..." -ForegroundColor Green
        $appId = (az ad app create --display-name $exec.DisplayName --sign-in-audience AzureADMyOrg --query appId -o tsv)
        # Patch description (az ad app create doesn't accept --description directly)
        $appObjectId = (az ad app show --id $appId --query id -o tsv)
        Invoke-RestMethod -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
            -Headers @{ Authorization = "Bearer $gToken"; 'Content-Type' = 'application/json' } `
            -Body (@{ description = $exec.Description } | ConvertTo-Json) | Out-Null
    } else {
        Write-Host "  [=] Entra app '$($exec.DisplayName)' exists (appId=$appId)" -ForegroundColor DarkGray
    }

    # 2. Ensure Service Principal exists
    $spId = (az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv)
    if (-not $spId) {
        Write-Host "  [+] Creating Service Principal..." -ForegroundColor Green
        $spId = (az ad sp create --id $appId --query id -o tsv)
    } else {
        Write-Host "  [=] Service Principal exists (spId=$spId)" -ForegroundColor DarkGray
    }

    # 3. Add required Graph application permissions to the manifest
    $existingPerms = az ad app show --id $appId --query "requiredResourceAccess[?resourceAppId=='00000003-0000-0000-c000-000000000000'].resourceAccess[].id" -o tsv 2>$null
    $existingPermSet = @{}
    if ($existingPerms) { foreach ($p in $existingPerms -split "`n") { if ($p) { $existingPermSet[$p] = $true } } }

    $resourceAccess = @()
    $needsManifestUpdate = $false
    foreach ($perm in $exec.GraphPerms) {
        if (-not $graphRoleByValue.ContainsKey($perm)) {
            Write-Host "  [!] Graph role value '$perm' not found in app role catalogue" -ForegroundColor Red
            continue
        }
        $roleId = $graphRoleByValue[$perm]
        $resourceAccess += @{ id = $roleId; type = 'Role' }
        if (-not $existingPermSet.ContainsKey($roleId)) { $needsManifestUpdate = $true }
    }

    if ($needsManifestUpdate) {
        Write-Host "  [+] Updating Graph permission manifest..." -ForegroundColor Green
        $manifest = @{
            requiredResourceAccess = @(
                @{
                    resourceAppId = '00000003-0000-0000-c000-000000000000'
                    resourceAccess = $resourceAccess
                }
            )
        }
        $tempFile = New-TemporaryFile
        ($manifest | ConvertTo-Json -Depth 5) | Set-Content $tempFile.FullName
        az ad app update --id $appId --required-resource-accesses "@$($tempFile.FullName)" | Out-Null
        Remove-Item $tempFile.FullName -Force
    } else {
        Write-Host "  [=] Graph permissions already on manifest" -ForegroundColor DarkGray
    }

    # 4. Grant admin consent for each app permission
    foreach ($perm in $exec.GraphPerms) {
        if (-not $graphRoleByValue.ContainsKey($perm)) { continue }
        $roleId = $graphRoleByValue[$perm]
        $existingGrant = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments" -Headers $gh).value | Where-Object { $_.appRoleId -eq $roleId }
        if (-not $existingGrant) {
            Write-Host "  [+] Granting admin consent for $perm..." -ForegroundColor Green
            $body = @{ principalId = $spId; resourceId = $graphSpId; appRoleId = $roleId } | ConvertTo-Json
            try {
                Invoke-RestMethod -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments" `
                    -Headers @{ Authorization = "Bearer $gToken"; 'Content-Type' = 'application/json' } `
                    -Body $body | Out-Null
            } catch {
                Write-Host "  [!] Failed to grant $perm — $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  [=] Admin consent already granted for $perm" -ForegroundColor DarkGray
        }
    }

    # 5. Generate / rotate client secret and store in Key Vault
    $kvSecret = az keyvault secret show --vault-name $KeyVaultName --name $exec.SecretName --query value -o tsv 2>$null
    if (-not $kvSecret) {
        Write-Host "  [+] Generating client secret + storing in KV..." -ForegroundColor Green
        $secretValue = (az ad app credential reset --id $appId --display-name "ITSM-Phase3-Setup" --years 1 --query password -o tsv)
        az keyvault secret set --vault-name $KeyVaultName --name $exec.SecretName --value $secretValue | Out-Null
        Write-Host "  [+] KV secret '$($exec.SecretName)' set (1-year expiry)" -ForegroundColor Green
    } else {
        Write-Host "  [=] KV secret '$($exec.SecretName)' already exists. Skipping rotation. To rotate: az ad app credential reset --id $appId" -ForegroundColor DarkGray
    }

    # 6. Assign directory role (where required)
    if ($exec.DirectoryRole) {
        if (-not $roleIdByName.ContainsKey($exec.DirectoryRole)) {
            Write-Host "  [!] Directory role '$($exec.DirectoryRole)' not found in tenant — assignment skipped" -ForegroundColor Yellow
        } else {
            $roleDefId = $roleIdByName[$exec.DirectoryRole]
            $existingRole = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spId' and roleDefinitionId eq '$roleDefId'" -Headers $gh).value
            if (-not $existingRole) {
                Write-Host "  [+] Assigning directory role '$($exec.DirectoryRole)'..." -ForegroundColor Green
                $assignBody = @{
                    principalId = $spId
                    roleDefinitionId = $roleDefId
                    directoryScopeId = '/'
                } | ConvertTo-Json
                try {
                    Invoke-RestMethod -Method POST `
                        -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' `
                        -Headers @{ Authorization = "Bearer $gToken"; 'Content-Type' = 'application/json' } `
                        -Body $assignBody | Out-Null
                } catch {
                    Write-Host "  [!] Role assignment failed — $_" -ForegroundColor Red
                }
            } else {
                Write-Host "  [=] Directory role '$($exec.DirectoryRole)' already assigned" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "  [=] No directory role required for this executor" -ForegroundColor DarkGray
    }

    $summary += [pscustomobject]@{
        Name = $exec.Name
        AppId = $appId
        SpId = $spId
        SecretName = $exec.SecretName
        DirectoryRole = $(if ($exec.DirectoryRole) { $exec.DirectoryRole } else { '(none)' })
        Status = 'OK'
    }
}

Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "         5-Executor Provisioning Summary"  -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

Write-Host "`n=== Next steps ===" -ForegroundColor Cyan
Write-Host "  1. Update each executor flow definition (flows/executors/{groups,licensing,exchange,sharepoint,teams}/definition.json)"
Write-Host "     with the AppId from the table above (replace placeholder \`<APPID-{NAME}>\`)."
Write-Host "  2. Deploy each flow via PA REST POST or FlowStudio MCP update_live_flow."
Write-Host "  3. Update Dispatcher (flows/dispatcher/definition/definition.json) Switch_OnJobType cases"
Write-Host "     to add 5 new categories (groups.* / licensing.* / exchange.* / sharepoint.* / teams.*)."
Write-Host "  4. Deploy Dispatcher and run E2E test (one PJ per executor) — see flows/executors/README.md."
Write-Host ""
