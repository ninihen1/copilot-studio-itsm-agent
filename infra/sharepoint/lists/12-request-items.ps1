#Requires -Version 7.0

# Request Items list — RITM children of Request tickets.
# Source: sharepoint-itsm-schema.xlsx, sheet "2. Request Items"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-RequestItemsList {
    param([string]$ListTitle = 'Request Items')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Children of Request tickets. One row per ordered Service Catalog item.' `
        -EnableVersioning $true -MajorVersionLimit 25 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RitmNumber'; DisplayName='Request Item Number'; Type='Text'; Required=$true; Indexed=$true; MaxLength=32; Description='Request Item unique ID (RITM-prefix)' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentTicket'; DisplayName='Parent Ticket'; Type='Lookup'; LookupList='Tickets'; LookupField='TicketNumber'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CatalogItem'; DisplayName='Catalog Item'; Type='Lookup'; LookupList='Service Catalog'; LookupField='Title'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RequestedFor'; DisplayName='Requested For'; Type='User'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RitmState'; DisplayName='Status'; Type='Choice'; Choices=@('Pending Validation','Pending Approval','On Hold','Approved','In Progress','Closed Complete','Closed Incomplete','Closed Skipped','Cancelled'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Variables'; DisplayName='Variables (JSON)'; Type='Note'; RichText=$false; Description='User-supplied form variables for the catalog item' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssignedTo'; DisplayName='Assigned To'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssignmentGroup'; DisplayName='Assignment Group'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Cost'; DisplayName='Cost'; Type='Currency' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='SlaDue'; DisplayName='SLA Due'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OpenedDate'; DisplayName='Opened'; Type='DateTime'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ClosedDate'; DisplayName='Closed'; Type='DateTime'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CloseCode'; DisplayName='Close Code'; Type='Choice'; Choices=@('Fulfilled','Cancelled','Rejected','Duplicate') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CloseNotes'; DisplayName='Close Notes'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='WorkNotes'; DisplayName='Work Notes'; Type='Note'; RichText=$false; AppendOnly=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ConfidentialityLevel'; DisplayName='Confidentiality'; Type='Choice'; Choices=@('Public','Restricted','Confidential'); Required=$true; DefaultValue='Public' }
}

