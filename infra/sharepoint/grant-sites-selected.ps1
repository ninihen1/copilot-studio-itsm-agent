#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Microsoft.Graph.Sites'; ModuleVersion='2.0.0' }

<#
.SYNOPSIS
Grants SP-IT-SharePoint app-only "fullcontrol" role on the sites/ITSM site collection.

.DESCRIPTION
Implements the Sites.Selected permission grant pattern:
1. The SP-IT-SharePoint Entra app must already have Sites.Selected (Application) admin-consented.
2. This script grants that app the "fullcontrol" role on a single specific site.
3. Idempotent — re-runs are no-ops if the same identity-role pair already exists.

Run by the tenant's SP-IT-Provisioning identity (or any caller with Sites.FullControl.All).

.PARAMETER SiteUrl
Full URL of the target site, e.g. https://contoso.sharepoint.com/sites/ITSM

.PARAMETER AppId
Client ID of the SP-IT-SharePoint Entra app registration to grant access to.

.PARAMETER AppDisplayName
Display name of the app (cosmetic — appears in audit logs).

.PARAMETER Role
The role to grant: 'read' | 'write' | 'fullcontrol' | 'owner'.
Default 'fullcontrol' — required for "Grant/revoke site access" and "Add/remove from SP group" jobs.

.EXAMPLE
./grant-sites-selected.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/ITSM" `
    -AppId "<SP-IT-SharePoint client ID>" `
    -AppDisplayName "SP-IT-SharePoint" `
    -Role "fullcontrol"

.NOTES
Prerequisites:
  - SP-IT-SharePoint app reg created in Entra
  - Sites.Selected (Application) added and admin-consented
  - Caller is signed in to Microsoft Graph with Sites.FullControl.All OR is a SharePoint admin
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$AppDisplayName,
    [ValidateSet('read','write','fullcontrol','owner')][string]$Role = 'fullcontrol'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Connect to Graph (interactive — admin running this once per environment)
if (-not (Get-MgContext)) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes 'Sites.FullControl.All' -NoWelcome
}

# Resolve siteId from URL
# Graph site ID format: {hostname},{site-collection-id},{site-id}
Write-Host "Resolving site ID for $SiteUrl..." -ForegroundColor Cyan
$uri = [System.Uri]$SiteUrl
$hostname = $uri.Host
$relativePath = $uri.AbsolutePath  # e.g. /sites/ITSM

$siteResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/${hostname}:${relativePath}"
$siteId = $siteResp.id
Write-Host "  Site ID: $siteId" -ForegroundColor Green

# Check existing permissions for this app
Write-Host "Checking existing permissions for app $AppId..." -ForegroundColor Cyan
$perms = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions"
$existing = $null
if ($perms.value) {
    foreach ($perm in $perms.value) {
        if ($perm.grantedToIdentitiesV2) {
            foreach ($identity in $perm.grantedToIdentitiesV2) {
                if ($identity.application -and $identity.application.id -eq $AppId) {
                    $existing = $perm
                    break
                }
            }
        }
        if ($existing) { break }
    }
}

if ($existing) {
    $currentRoles = $existing.roles -join ','
    if ($existing.roles -contains $Role) {
        Write-Host "  [NO-CHANGE] App already has '$Role' on $SiteUrl (permission ID: $($existing.id))" -ForegroundColor Gray
        return
    } else {
        Write-Host "  [UPDATE] App has roles [$currentRoles], updating to [$Role]" -ForegroundColor Yellow
        $updateBody = @{ roles = @($Role) } | ConvertTo-Json
        $updated = Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions/$($existing.id)" `
            -Body $updateBody -ContentType 'application/json'
        Write-Host "  [UPDATED] Roles set to [$Role]" -ForegroundColor Green
        return
    }
}

# Grant new permission
Write-Host "Granting '$Role' on $SiteUrl to app $AppDisplayName ($AppId)..." -ForegroundColor Cyan
$body = @{
    roles = @($Role)
    grantedToIdentities = @(
        @{
            application = @{
                id          = $AppId
                displayName = $AppDisplayName
            }
        }
    )
} | ConvertTo-Json -Depth 5

$result = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions" `
    -Body $body -ContentType 'application/json'

Write-Host "`n[CREATED] Permission ID: $($result.id)" -ForegroundColor Green
Write-Host "         App $AppDisplayName ($AppId)" -ForegroundColor Green
Write-Host "         Role: $Role" -ForegroundColor Green
Write-Host "         Site: $SiteUrl" -ForegroundColor Green
Write-Host "`nTo verify:" -ForegroundColor Cyan
Write-Host "  GET https://graph.microsoft.com/v1.0/sites/$siteId/permissions" -ForegroundColor DarkGray
Write-Host "`nTo revoke later:" -ForegroundColor Cyan
Write-Host "  DELETE https://graph.microsoft.com/v1.0/sites/$siteId/permissions/$($result.id)" -ForegroundColor DarkGray
