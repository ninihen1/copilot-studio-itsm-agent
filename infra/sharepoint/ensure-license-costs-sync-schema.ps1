#Requires -Version 7.0

<#
.SYNOPSIS
Adds metadata columns required by the License Costs scheduled sync flow.

.DESCRIPTION
The License Costs list already stores tenant-facing display names and cost data.
These columns let the scheduled sync store Microsoft's current official product
name and skuId without overwriting tenant-specific display names, notes, or
pricing overrides.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$ClientId,
    [string]$Tenant = 'contoso.onmicrosoft.com',
    [string]$CertificatePath,
    [SecureString]$CertificatePassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')

Connect-ItsmTenantPilot `
    -SiteUrl $SiteUrl `
    -ClientId $ClientId `
    -Tenant $Tenant `
    -CertificatePath $CertificatePath `
    -CertificatePassword $CertificatePassword

$listTitle = 'License Costs'

Write-Host "`n=== $listTitle sync metadata ===" -ForegroundColor Cyan

Ensure-PnPField -ListTitle $listTitle -Spec @{
    InternalName = 'OfficialProductName'
    DisplayName  = 'Official Product Name'
    Type         = 'Text'
    MaxLength    = 255
    Description  = 'Current Microsoft product name from the official SKU reference CSV. Do not use for tenant overrides.'
}

Ensure-PnPField -ListTitle $listTitle -Spec @{
    InternalName = 'SkuId'
    DisplayName  = 'SKU ID'
    Type         = 'Text'
    MaxLength    = 64
    Indexed      = $true
    Description  = 'GUID from the Microsoft SKU reference and Graph subscribedSku.skuId.'
}

Ensure-PnPField -ListTitle $listTitle -Spec @{
    InternalName = 'SkuPartNumber'
    DisplayName  = 'SKU Part Number'
    Type         = 'Text'
    MaxLength    = 128
    Required     = $true
    Indexed      = $true
    Description  = 'Microsoft String_Id from the official SKU reference and Graph subscribedSku.skuPartNumber.'
}
