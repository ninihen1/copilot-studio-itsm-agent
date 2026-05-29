#Requires -Version 7.0

# Assets list — physical/licensed inventory.
# Source: sharepoint-itsm-schema.xlsx, sheet "7. Assets"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-AssetsList {
    param([string]$ListTitle = 'Assets')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Physical and licensed asset inventory. Linked to Configuration Items for operational view.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssetTag'; DisplayName='Asset Tag'; Type='Text'; Required=$true; Indexed=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='SerialNumber'; DisplayName='Serial Number'; Type='Text'; Indexed=$true; MaxLength=128 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssetClass'; DisplayName='Asset Class'; Type='Choice'; Choices=@('Laptop','Desktop','Monitor','Mobile Device','Peripheral','Software License','Subscription','Other'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssignedTo'; DisplayName='Assigned To'; Type='User'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssignedDate'; DisplayName='Assigned Date'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssetState'; DisplayName='State'; Type='Choice'; Choices=@('In Stock','In Use','In Maintenance','In Transit','Retired','Disposed','Lost / Stolen'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='LinkedCi'; DisplayName='Linked Configuration Item'; Type='Lookup'; LookupList='Configuration Items'; LookupField='Title' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Vendor'; DisplayName='Vendor'; Type='Text'; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PurchaseDate'; DisplayName='Purchase Date'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='WarrantyExpiry'; DisplayName='Warranty Expiry'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PurchaseCost'; DisplayName='Purchase Cost'; Type='Currency' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Location'; DisplayName='Location'; Type='Text'; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Notes'; DisplayName='Notes'; Type='Note'; RichText=$false; AppendOnly=$true }
}

