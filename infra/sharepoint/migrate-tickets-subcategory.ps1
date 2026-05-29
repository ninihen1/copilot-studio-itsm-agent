#Requires -Version 7.0

<#
.SYNOPSIS
Phase 3.1 fix — migrates Tickets.Subcategory from Text → Lookup → Subcategories list.

PnP Set-PnPField (and Ensure-PnPField) cannot change a column's underlying type. The only safe
path is to delete the existing column and let the updated provisioning script re-create it as
the new Lookup type.

.DESCRIPTION
This is destructive — it deletes the Subcategory column from the Tickets list. Pilot tickets
have no Subcategory data so the loss is zero, but production data WILL be wiped. Verify with
the dry-run guard before running with -Confirm.

The script will:
  1. Probe Tickets.Subcategory and report its current type
  2. Count any non-empty Subcategory values across the list (warning if > 0)
  3. If user passes -Confirm, delete the column
  4. Re-run the Tickets list provisioner (which now defines Subcategory as Lookup)
  5. Verify the new column exists and is a Lookup → Subcategories

Pre-requisites: Subcategories list must already be provisioned and seeded
(run `provision-lists.ps1 -ListsToProvision 01b` and `seed-subcategories.ps1` first).

.PARAMETER Confirm
Required to actually perform the deletion. Without this, the script does a dry-run and reports.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [Parameter(Mandatory)][string]$CertificateName,
    [switch]$Confirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$listsDir = Join-Path $PSScriptRoot 'lists'
. (Join-Path $listsDir '_helpers.ps1')
Connect-ItsmTenant -SiteUrl $SiteUrl -AppId $AppId -KeyVaultName $KeyVaultName -CertificateName $CertificateName

$listTitle = 'Tickets'
$fieldName = 'Subcategory'

# === Step 1: probe current column type ===
Write-Host "`n=== Step 1: probing current Tickets.Subcategory column ===" -ForegroundColor Cyan
$current = Get-PnPField -List $listTitle -Identity $fieldName -ErrorAction SilentlyContinue
if (-not $current) {
    Write-Host "  Column 'Subcategory' does not exist on Tickets. Likely already migrated or never created." -ForegroundColor Yellow
    Write-Host "  Will re-run Tickets provisioning now to ensure Lookup is created." -ForegroundColor Yellow
} else {
    Write-Host "  Current type: $($current.TypeAsString)" -ForegroundColor White
    if ($current.TypeAsString -eq 'Lookup') {
        Write-Host "  Already a Lookup — no migration needed. Verifying target..." -ForegroundColor Green
        if ($current.SchemaXml -notmatch 'Subcategories') {
            Write-Host "  WARNING: Lookup target is not 'Subcategories'. Manual fix needed." -ForegroundColor Red
        }
        Disconnect-PnPOnline
        return
    }
}

# === Step 2: count rows that will lose their Subcategory value ===
$rowsWithValue = 0
if ($current) {
    Write-Host "`n=== Step 2: counting rows with Subcategory data ===" -ForegroundColor Cyan
    $allTickets = Get-PnPListItem -List $listTitle -PageSize 500
    foreach ($row in $allTickets) {
        $val = $row.FieldValues[$fieldName]
        if ($val -and $val.ToString().Trim()) { $rowsWithValue++ }
    }
    Write-Host "  Rows with non-empty Subcategory: $rowsWithValue" -ForegroundColor $(if ($rowsWithValue -gt 0) { 'Yellow' } else { 'DarkGray' })
    if ($rowsWithValue -gt 0) {
        Write-Host "  WARNING: deleting the column WILL discard these values. Recommended: export the list to CSV first." -ForegroundColor Yellow
        Write-Host "  Snapshot suggestion:" -ForegroundColor DarkYellow
        Write-Host "    Get-PnPListItem -List Tickets -PageSize 500 | Select Id,@{n='Subcategory';e={`$_.FieldValues.Subcategory}} | Export-Csv -Path tickets-subcategory-backup.csv -NoTypeInformation" -ForegroundColor DarkYellow
    }
}

# === Step 3: confirm gate ===
if (-not $Confirm) {
    Write-Host "`n=== DRY RUN — not deleting anything ===" -ForegroundColor Cyan
    Write-Host "  To proceed: re-run with -Confirm" -ForegroundColor White
    Disconnect-PnPOnline
    return
}

# === Step 4: delete the existing column ===
if ($current) {
    Write-Host "`n=== Step 4: deleting Tickets.Subcategory ($($current.TypeAsString)) ===" -ForegroundColor Cyan
    Remove-PnPField -List $listTitle -Identity $fieldName -Force
    Write-Host "  ✓ deleted." -ForegroundColor Green
}

# === Step 5: re-run Tickets provisioner to recreate as Lookup ===
Write-Host "`n=== Step 5: re-running Provision-TicketsList ===" -ForegroundColor Cyan
. (Join-Path $listsDir '10-tickets.ps1')
Provision-TicketsList -ListTitle $listTitle

# === Step 6: verify ===
Write-Host "`n=== Step 6: verifying ===" -ForegroundColor Cyan
$after = Get-PnPField -List $listTitle -Identity $fieldName -ErrorAction SilentlyContinue
if (-not $after) {
    Write-Host "  ✗ Column not present after re-provisioning. Provisioning script may need a fix." -ForegroundColor Red
    Disconnect-PnPOnline
    throw "Subcategory column missing post-migration."
}
if ($after.TypeAsString -ne 'Lookup') {
    Write-Host "  ✗ Column is type '$($after.TypeAsString)', expected 'Lookup'." -ForegroundColor Red
    Disconnect-PnPOnline
    throw "Subcategory column is wrong type post-migration."
}
if ($after.SchemaXml -notmatch 'Subcategories') {
    Write-Host "  ✗ Lookup target is not 'Subcategories'." -ForegroundColor Red
    Disconnect-PnPOnline
    throw "Subcategory Lookup is not pointing to Subcategories list."
}
Write-Host "  ✓ Subcategory is now Lookup → Subcategories." -ForegroundColor Green

Write-Host "`n=== Migration complete ===" -ForegroundColor Cyan
Write-Host "  Discarded values: $rowsWithValue (rows still exist; only the Subcategory cell is empty)" -ForegroundColor White
Write-Host "  Next: any flow that PATCHes Tickets.Subcategory must now send the SP int Id (e.g., item/Subcategory/Id) — not a free-text string." -ForegroundColor White

Disconnect-PnPOnline
