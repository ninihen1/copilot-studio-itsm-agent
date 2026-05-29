#Requires -Version 7.0

# Categories list — hierarchical taxonomy used by Tickets, Catalog, KB.
# Source: sharepoint-itsm-schema.xlsx, sheet "5. Categories"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-CategoriesList {
    param([string]$ListTitle = 'Categories')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Hierarchical taxonomy. Self-referencing via ParentCategory for sub-categories.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    # Phase B dedupe: CategoryName column dropped — Title now carries the category name.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Category Name' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentCategory'; DisplayName='Parent Category'; Type='Lookup'; LookupList='Categories'; LookupField='Title'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DefaultPolicy'; DisplayName='Default Approval Policy'; Type='Lookup'; LookupList='Approval Policies'; LookupField='Title' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Status'; DisplayName='Status'; Type='Choice'; Choices=@('active','deprecated'); Required=$true; Indexed=$true; DefaultValue='active' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='SortOrder'; DisplayName='Sort Order'; Type='Number' }
}

