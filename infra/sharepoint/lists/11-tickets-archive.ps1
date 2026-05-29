#Requires -Version 7.0

# Tickets-Archive list — closed tickets > 12 months. Same schema as Tickets so the archival flow is a straight copy.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-TicketsArchiveList {
    param([string]$ListTitle = 'Tickets-Archive')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Archive of closed tickets > 12 months. Mirrors Tickets schema. Receives moved items via the archival flow. Indexed for search but rarely written.' `
        -EnableVersioning $false | Out-Null

    # Mirror the Tickets list schema. Source the columns via the same definitions as 10-tickets.ps1.
    # Including all schema columns inline here to keep this script self-contained for re-runs.

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='TicketNumber'; DisplayName='Ticket Number'; Type='Text'; Required=$true; Indexed=$true; MaxLength=32 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='TicketType'; DisplayName='Type'; Type='Choice'; Choices=@('Incident','Request','Change','Problem'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CategoryRef'; DisplayName='Category'; Type='Text'; MaxLength=200; Description='Stored as text in archive (de-normalised), not lookup, to avoid lookup column limit issues' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Subcategory'; DisplayName='Subcategory'; Type='Text'; MaxLength=100 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CmdbCi'; DisplayName='Configuration Item'; Type='Text'; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Caller'; DisplayName='Caller'; Type='User'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AssignedTo'; DisplayName='Assigned To'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='TicketState'; DisplayName='Status'; Type='Choice'; Choices=@('Closed','Cancelled'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Impact'; DisplayName='Impact'; Type='Choice'; Choices=@('1 - High','2 - Medium','3 - Low') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Urgency'; DisplayName='Urgency'; Type='Choice'; Choices=@('1 - High','2 - Medium','3 - Low') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Priority'; DisplayName='Priority'; Type='Choice'; Choices=@('1 - Critical','2 - High','3 - Moderate','4 - Low','5 - Planning') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ShortDescription'; DisplayName='Short Description'; Type='Text'; MaxLength=255 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='WorkNotes'; DisplayName='Work Notes'; Type='Note'; RichText=$false; Description='Audit trail copied from source ticket' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Comments'; DisplayName='Comments'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CloseCode'; DisplayName='Close Code'; Type='Text'; MaxLength=128 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CloseNotes'; DisplayName='Close Notes'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OpenedDate'; DisplayName='Opened'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ResolvedDate'; DisplayName='Resolved'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ClosedDate'; DisplayName='Closed'; Type='DateTime'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ArchivedAt'; DisplayName='Archived At'; Type='DateTime'; Required=$true; Indexed=$true; Description='When the archival flow moved this row' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OriginalSourceId'; DisplayName='Original Tickets List ID'; Type='Number'; Description='SP ID from the live Tickets list, for traceability' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ArchivedByFlow'; DisplayName='Archived By Flow'; Type='Text'; MaxLength=128; Description='Name/run marker of the archival flow that moved this row.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ConfidentialityLevel'; DisplayName='Confidentiality'; Type='Choice'; Choices=@('Public','Restricted','Confidential'); Required=$true; DefaultValue='Public' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AuthorizedReaders'; DisplayName='Authorized Readers'; Type='UserMulti' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='MadeSla'; DisplayName='Made SLA'; Type='Boolean' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ReopenCount'; DisplayName='Reopen Count'; Type='Number' }
}

