#Requires -Version 7.0
#Requires -Modules @{ ModuleName='PnP.PowerShell'; ModuleVersion='2.4.0' }

<#
.SYNOPSIS
Master orchestrator for ITSM SharePoint list provisioning.

.DESCRIPTION
Provisions all 17 lists in dependency order. Idempotent — re-runnable.
Reads cert from Azure Key Vault and connects via app-only auth (SP-IT-Provisioning).

.PARAMETER SiteUrl
Full URL of the ITSM site, e.g. https://contoso.sharepoint.com/sites/ITSM

.PARAMETER AppId
Client ID of the SP-IT-Provisioning Entra app registration.

.PARAMETER KeyVaultName
Azure Key Vault name holding the SP-IT-Provisioning certificate.

.PARAMETER CertificateName
Name of the certificate in Key Vault.

.PARAMETER ListsToProvision
Optional. Comma-separated list of script numbers (e.g., "10,11,16") to provision only specific lists.
Default: all lists in dependency order.

.EXAMPLE
./provision-lists.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/ITSM" `
    -AppId "<guid>" -KeyVaultName "kv-itsm-dev" -CertificateName "SP-IT-Provisioning"

.NOTES
Prerequisites:
  - SharePoint site /sites/ITSM exists (create via SP Admin Center, Team site no M365 group)
  - SP-IT-Provisioning app registration with Sites.FullControl.All admin-consented
  - Cert public key uploaded to app, private key in Key Vault
  - Az.Accounts + Az.KeyVault PowerShell modules installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [Parameter(Mandatory)][string]$CertificateName,
    [string]$ListsToProvision = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$listsDir = Join-Path $scriptRoot 'lists'

# Load helpers
. (Join-Path $listsDir '_helpers.ps1')

# Connect once
Connect-ItsmTenant -SiteUrl $SiteUrl -AppId $AppId -KeyVaultName $KeyVaultName -CertificateName $CertificateName

# Provisioning order — list numbers correspond to filename prefixes
# Lower numbers must complete before higher ones (lookup dependencies)
$provisioningOrder = @(
    @{ Num = '01'; Title = 'Categories';                File = '01-categories.ps1';            Function = 'Provision-CategoriesList' }
    @{ Num = '01b';Title = 'Subcategories';             File = '01b-subcategories.ps1';        Function = 'Provision-SubcategoriesList' }
    @{ Num = '02'; Title = 'Configuration Items';       File = '02-configuration-items.ps1';   Function = 'Provision-ConfigurationItemsList' }
    @{ Num = '03'; Title = 'Assets';                    File = '03-assets.ps1';                Function = 'Provision-AssetsList' }
    @{ Num = '04'; Title = 'Knowledge Base';            File = '04-knowledge-base.ps1';        Function = 'Provision-KnowledgeBaseList' }
    @{ Num = '05'; Title = 'Service Catalog';           File = '05-service-catalog.ps1';       Function = 'Provision-ServiceCatalogList' }
    @{ Num = '06'; Title = 'Priority Matrix';           File = '06-priority-matrix.ps1';       Function = 'Provision-PriorityMatrixList' }
    @{ Num = '07'; Title = 'Approval Policies';         File = '07-approval-policies.ps1';     Function = 'Provision-ApprovalPoliciesList' }
    @{ Num = '08'; Title = 'JobTypes';                  File = '08-job-types.ps1';             Function = 'Provision-JobTypesList' }
    @{ Num = '09'; Title = 'Config';                    File = '09-config.ps1';                Function = 'Provision-ConfigList' }
    @{ Num = '10'; Title = 'Tickets';                   File = '10-tickets.ps1';               Function = 'Provision-TicketsList' }
    @{ Num = '11'; Title = 'Tickets-Archive';           File = '11-tickets-archive.ps1';       Function = 'Provision-TicketsArchiveList' }
    @{ Num = '12'; Title = 'Request Items';             File = '12-request-items.ps1';         Function = 'Provision-RequestItemsList' }
    @{ Num = '13'; Title = 'Tasks';                     File = '13-tasks.ps1';                 Function = 'Provision-TasksList' }
    @{ Num = '14'; Title = 'Approvals';                 File = '14-approvals.ps1';             Function = 'Provision-ApprovalsList' }
    @{ Num = '15'; Title = 'Approval Stages';           File = '15-approval-stages.ps1';       Function = 'Provision-ApprovalStagesList' }
    @{ Num = '16'; Title = 'Provisioning Jobs';         File = '16-provisioning-jobs.ps1';     Function = 'Provision-ProvisioningJobsList' }
    @{ Num = '17'; Title = 'License Costs';             File = '17-license-costs.ps1';         Function = 'Provision-LicenseCostsList' }
)

# Filter by user-supplied list numbers if any
if ($ListsToProvision) {
    $wanted = $ListsToProvision -split ',' | ForEach-Object { $_.Trim() }
    $provisioningOrder = $provisioningOrder | Where-Object { $_.Num -in $wanted }
    Write-Host "Filtered to lists: $($wanted -join ', ')" -ForegroundColor Cyan
}

# Run each
$summary = @()
foreach ($entry in $provisioningOrder) {
    $scriptPath = Join-Path $listsDir $entry.File
    if (-not (Test-Path $scriptPath)) {
        Write-StateLine -State SKIPPED -Object "List: $($entry.Title)" -Detail "(script $($entry.File) not found — pending implementation)"
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

# Print summary
Write-Host "`n`n========== PROVISIONING SUMMARY ==========" -ForegroundColor White
$summary | Format-Table -AutoSize

# Disconnect
Disconnect-PnPOnline

# Exit code reflects errors
$errorCount = ($summary | Where-Object Status -eq 'Error').Count
if ($errorCount -gt 0) {
    Write-Host "`n$errorCount list(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll requested lists provisioned successfully." -ForegroundColor Green
    exit 0
}
