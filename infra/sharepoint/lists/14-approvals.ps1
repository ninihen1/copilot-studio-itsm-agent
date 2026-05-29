#Requires -Version 7.0

# Approvals list — top-level approval audit row per ticket / RITM (one row per approval session).
# Source: sharepoint-itsm-schema.xlsx, sheet "9. Approvals"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ApprovalsList {
    param([string]$ListTitle = 'Approvals')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Top-level approval session per Ticket / Request Item. Detail rows live in ApprovalStages.' `
        -EnableVersioning $true -MajorVersionLimit 50 | Out-Null

    # Phase B dedupe: ApprovalSessionId column dropped — Title now carries the session id.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Approval Session ID' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentTicket'; DisplayName='Ticket'; Type='Lookup'; LookupList='Tickets'; LookupField='TicketNumber'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentRitm'; DisplayName='Request Item'; Type='Lookup'; LookupList='Request Items'; LookupField='RitmNumber' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='LinkedJobId'; DisplayName='Job ID'; Type='Text'; Indexed=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PolicyApplied'; DisplayName='Policy'; Type='Lookup'; LookupList='Approval Policies'; LookupField='Title'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PolicyVersionUsed'; DisplayName='Policy Version'; Type='Number'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='SessionState'; DisplayName='State'; Type='Choice'; Choices=@('InProgress','Approved','Rejected','Timeout','Revoked','Cancelled'); Required=$true; Indexed=$true }

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CompletedAt'; DisplayName='Completed At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DurationMinutes'; DisplayName='Duration (min)'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='IssuedJti'; DisplayName='Issued JWT ID'; Type='Text'; MaxLength=64; Description='JWT replay-protection ID minted on Approved' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RejectionReason'; DisplayName='Rejection Reason'; Type='Note'; RichText=$false }
}

