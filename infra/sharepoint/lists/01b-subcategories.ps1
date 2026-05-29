#Requires -Version 7.0

# Subcategories list — child taxonomy under Categories.
# Source: servicenow-itsm-ticketing-report.md §4.1 — research baseline taxonomy.
# Pattern mirrors ServiceNow's category→subcategory cascade (incident.category → incident.subcategory).
# Tickets list points its Subcategory column at this list (Lookup, ShowField=Title) so the form
# can cascade-filter subcategory choices by the selected Category.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-SubcategoriesList {
    param([string]$ListTitle = 'Subcategories')

    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Hierarchical subcategory list. Each row links to a Category via ParentCategory. Used by Tickets.Subcategory lookup with cascade filtering.' `
        -Template GenericList `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    # Phase B dedupe convention: Title carries the subcategory name; no separate SubcategoryName column.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Subcategory Name' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ParentCategory'; DisplayName = 'Parent Category'; Type = 'Lookup'
        LookupList = 'Categories'; LookupField = 'Title'; Required = $true; Indexed = $true
        Description = 'The category this subcategory rolls up to. Drives cascade-filter on Tickets form.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Description'; DisplayName = 'Description'; Type = 'Note'; RichText = $false
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SubcategoryStatus'; DisplayName = 'Status'; Type = 'Choice'
        Choices = @('active','deprecated'); Required = $true; Indexed = $true; DefaultValue = 'active'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SortOrder'; DisplayName = 'Sort Order'; Type = 'Number'
        Description = 'Display ordering within the parent category. 10, 20, 30, ... for easy reordering.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'JobTypeHint'; DisplayName = 'Job Type Hint'; Type = 'Text'; MaxLength = 64
        Description = 'Optional hint for triage agent — if this subcategory is selected, the agent should consider proposing this jobType.'
    }
}
