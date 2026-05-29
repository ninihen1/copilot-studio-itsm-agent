#Requires -Version 7.0
#Requires -Modules @{ ModuleName='PnP.PowerShell'; ModuleVersion='2.4.0' }

<#
.SYNOPSIS
Pilot-mode provisioner. Connects to SharePoint as the signed-in user via PnP interactive
auth (no cert, no Key Vault, no app registration) and provisions all 16 lists in the
correct dependency order.

.DESCRIPTION
Use this for first-time setup of /sites/ITSM. Once the SP-IT-Provisioning app reg + cert
+ Key Vault are in place, switch to provision-lists.ps1 (cert-based) for any future runs
that need to be unattended / scheduled.

.PARAMETER SiteUrl
Full URL of the ITSM site, e.g. https://contoso.sharepoint.com/sites/ITSM

.PARAMETER ListsToProvision
Optional. Comma-separated list of list names (or numbers) to provision a subset.

.EXAMPLE
./provision-lists-interactive.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/ITSM"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$ListsToProvision = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$listsDir = Join-Path $scriptRoot 'lists'

# Load the helper functions (Ensure-PnPList, Ensure-PnPField, Write-StateLine)
. (Join-Path $listsDir '_helpers.ps1')

# ---- Connect via device-code flow ----
Write-Host "`nConnecting to $SiteUrl via device code..." -ForegroundColor Cyan
Write-Host "A code will print below. Paste it at https://microsoft.com/devicelogin in any browser already signed in to contoso." -ForegroundColor DarkGray

# Per-tenant SP-IT-Provisioning app (created via Register-PnPEntraIDAppForInteractiveLogin on 2026-04-30).
# The PnP multi-tenant Management Shell app was retired 2024-09-09.
$itsmProvisioningClientId = '00000000-0000-4000-8000-000000000042'

# Derive tenant from site URL (e.g. contoso.sharepoint.com -> contoso.onmicrosoft.com)
$tenantHost = ([System.Uri]$SiteUrl).Host
$tenantPrefix = ($tenantHost -split '\.')[0]
$tenantDomain = "$tenantPrefix.onmicrosoft.com"

try {
    Connect-PnPOnline -Url $SiteUrl -DeviceLogin -ClientId $itsmProvisioningClientId -Tenant $tenantDomain -ErrorAction Stop
    Write-Host "Connected." -ForegroundColor Green
} catch {
    Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nIf this is the first time using PnP in your tenant, you may need to grant admin consent for the PnP Management Shell app:" -ForegroundColor Yellow
    Write-Host "  Register-PnPManagementShellAccess -TenantUrl 'https://contoso-admin.sharepoint.com'" -ForegroundColor Yellow
    exit 1
}

# Show context
$ctx = Get-PnPContext
Write-Host "Site: $($ctx.Url)" -ForegroundColor Gray
Write-Host "User: $((Get-PnPProperty -ClientObject $ctx.Web -Property CurrentUser -ErrorAction SilentlyContinue).LoginName)" -ForegroundColor Gray

# ---- Dependency-correct provisioning order ----
# Lookup fan-in:
#   Categories          <- nothing
#   Configuration Items <- self
#   Assets              <- Configuration Items
#   Knowledge Base      <- Categories, self
#   Priority Matrix     <- nothing
#   Approval Policies   <- nothing
#   JobTypes            <- Approval Policies
#   Config              <- nothing
#   Service Catalog     <- Categories, Approval Policies   (HAD TO MOVE LATER)
#   Tickets             <- Categories, Configuration Items, Knowledge Base, self
#   Tickets-Archive     <- nothing (de-normalised)
#   Request Items       <- Tickets, Service Catalog
#   Tasks               <- Request Items
#   Approvals           <- Tickets, Request Items, Approval Policies
#   Approval Stages     <- nothing
#   Provisioning Jobs   <- Tickets, Request Items

$provisioningOrder = @(
    @{ Num = '01'; Title = 'Categories';                File = '01-categories.ps1';            Function = 'Provision-CategoriesList' }
    @{ Num = '02'; Title = 'Configuration Items';       File = '02-configuration-items.ps1';   Function = 'Provision-ConfigurationItemsList' }
    @{ Num = '03'; Title = 'Assets';                    File = '03-assets.ps1';                Function = 'Provision-AssetsList' }
    @{ Num = '04'; Title = 'Knowledge Base';            File = '04-knowledge-base.ps1';        Function = 'Provision-KnowledgeBaseList' }
    @{ Num = '06'; Title = 'Priority Matrix';           File = '06-priority-matrix.ps1';       Function = 'Provision-PriorityMatrixList' }
    @{ Num = '07'; Title = 'Approval Policies';         File = '07-approval-policies.ps1';     Function = 'Provision-ApprovalPoliciesList' }
    @{ Num = '08'; Title = 'JobTypes';                  File = '08-job-types.ps1';             Function = 'Provision-JobTypesList' }
    @{ Num = '09'; Title = 'Config';                    File = '09-config.ps1';                Function = 'Provision-ConfigList' }
    @{ Num = '05'; Title = 'Service Catalog';           File = '05-service-catalog.ps1';       Function = 'Provision-ServiceCatalogList' }
    @{ Num = '10'; Title = 'Tickets';                   File = '10-tickets.ps1';               Function = 'Provision-TicketsList' }
    @{ Num = '11'; Title = 'Tickets-Archive';           File = '11-tickets-archive.ps1';       Function = 'Provision-TicketsArchiveList' }
    @{ Num = '12'; Title = 'Request Items';             File = '12-request-items.ps1';         Function = 'Provision-RequestItemsList' }
    @{ Num = '13'; Title = 'Tasks';                     File = '13-tasks.ps1';                 Function = 'Provision-TasksList' }
    @{ Num = '14'; Title = 'Approvals';                 File = '14-approvals.ps1';             Function = 'Provision-ApprovalsList' }
    @{ Num = '15'; Title = 'Approval Stages';           File = '15-approval-stages.ps1';       Function = 'Provision-ApprovalStagesList' }
    @{ Num = '16'; Title = 'Provisioning Jobs';         File = '16-provisioning-jobs.ps1';     Function = 'Provision-ProvisioningJobsList' }
)

# Filter
if ($ListsToProvision) {
    $wanted = $ListsToProvision -split ',' | ForEach-Object { $_.Trim() }
    $provisioningOrder = $provisioningOrder | Where-Object { $_.Num -in $wanted -or $_.Title -in $wanted }
    Write-Host "Filtered to: $($wanted -join ', ')" -ForegroundColor Cyan
}

# Run
$summary = @()
foreach ($entry in $provisioningOrder) {
    $scriptPath = Join-Path $listsDir $entry.File
    if (-not (Test-Path $scriptPath)) {
        Write-StateLine -State SKIPPED -Object "List: $($entry.Title)" -Detail "(script $($entry.File) not found)"
        $summary += [PSCustomObject]@{ Num=$entry.Num; List=$entry.Title; Status='Pending'; Detail='script missing' }
        continue
    }
    try {
        Write-Host "`n--- $($entry.Num): $($entry.Title) ---" -ForegroundColor Cyan
        . $scriptPath
        & $entry.Function
        $summary += [PSCustomObject]@{ Num=$entry.Num; List=$entry.Title; Status='OK'; Detail='' }
    } catch {
        Write-StateLine -State ERROR -Object "List: $($entry.Title)" -Detail $_.Exception.Message
        $summary += [PSCustomObject]@{ Num=$entry.Num; List=$entry.Title; Status='Error'; Detail=$_.Exception.Message }
    }
}

# Summary
Write-Host "`n`n========== PROVISIONING SUMMARY ==========" -ForegroundColor White
$summary | Format-Table -AutoSize

Disconnect-PnPOnline

$errorCount = ($summary | Where-Object Status -eq 'Error').Count
if ($errorCount -gt 0) {
    Write-Host "`n$errorCount list(s) failed. See errors above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll requested lists provisioned successfully." -ForegroundColor Green
    exit 0
}
