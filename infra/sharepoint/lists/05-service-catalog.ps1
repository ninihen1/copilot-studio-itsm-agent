#Requires -Version 7.0

# Service Catalog list — orderable items.
# Source: sharepoint-itsm-schema.xlsx, sheet "4. Service Catalog"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ServiceCatalogList {
    param([string]$ListTitle = 'Service Catalog')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Orderable items. Each catalog item maps to a JobType and an Approval Policy. Multi-task items use TaskTemplates JSON array.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    # Phase B / Phase 3 dedupe convention: Title carries the catalog item identifier (e.g., CAT-PWD-RESET).
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Item Code' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ItemName'; DisplayName='Item Name'; Type='Text'; Required=$true; Indexed=$true; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Category'; DisplayName='Category'; Type='Lookup'; LookupList='Categories'; LookupField='Title'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ItemStatus'; DisplayName='Status'; Type='Choice'; Choices=@('active','inactive','deprecated'); Required=$true; Indexed=$true; DefaultValue='active' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='JobType'; DisplayName='Job Type'; Type='Text'; MaxLength=64; Description='Maps to JobTypes registry entry. Empty = human-fulfilled only.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApprovalPolicy'; DisplayName='Approval Policy'; Type='Lookup'; LookupList='Approval Policies'; LookupField='Title'; Description='Overrides Category default.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Cost'; DisplayName='Cost'; Type='Currency' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='SlaDays'; DisplayName='SLA Days'; Type='Number'; Description='Target fulfillment time' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='InputSchema'; DisplayName='Input Schema'; Type='Note'; RichText=$false; Description='JSON Schema for the order form variables' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ImageUrl'; DisplayName='Image URL'; Type='Text'; MaxLength=500 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OwningTeam'; DisplayName='Owning Team'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Visibility'; DisplayName='Visibility'; Type='Choice'; Choices=@('All Employees','IT Staff Only','Managers Only','Restricted'); Required=$true; DefaultValue='All Employees' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Keywords'; DisplayName='Keywords'; Type='Text'; MaxLength=500 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApproverContext'; DisplayName='Approver Context'; Type='Note'; RichText=$false; Description='Approver-facing context surfaced on the approval card for this catalog item.' }

    # Phase 3 — multi-task RITM support. If empty, RITM Generator creates a single SCTASK using the
    # item's JobType. If populated, must be a JSON array of { shortDescription, jobType, sortOrder, assignmentGroup? }.
    # Used by Onboarding/Offboarding Order Guides where one user request spawns 3-5 tasks.
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='TaskTemplates'; DisplayName='Task Templates (JSON)'; Type='Note'; RichText=$false
        Description='Optional JSON array of Catalog Task templates. Empty = single-task Request Item using item JobType. Populated = multi-task; one Catalog Task per array entry. Schema: [{shortDescription, jobType, sortOrder, assignmentGroup}]'
    }

    # Phase 3 — Subcategory hint so the RITM Generator can match catalog items by Tickets.Subcategory
    # when the user did not pick the catalog item explicitly.
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='SubcategoryHint'; DisplayName='Subcategory Hint'; Type='Lookup'
        LookupList='Subcategories'; LookupField='Title'
        Description='Optional. If user filed a Request without picking a catalog item, Request Item Generator matches by Subcategory.'
    }
}

