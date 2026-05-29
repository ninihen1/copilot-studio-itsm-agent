#Requires -Version 7.0

# Priority Matrix list — 9-row Impact x Urgency lookup.
# Source: sharepoint-itsm-schema.xlsx, sheet "10. Priority Matrix"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-PriorityMatrixList {
    param([string]$ListTitle = 'Priority Matrix')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description '9-row lookup mapping (Impact, Urgency) -> Priority. Used by priority-calc Power Automate flow.' `
        -EnableVersioning $true -MajorVersionLimit 5 | Out-Null

    # Phase B dedupe: Key column dropped — Title now carries the matrix key (e.g., 1-1, 2-3).
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Key' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Impact'; DisplayName='Impact'; Type='Choice'; Choices=@('1 - High','2 - Medium','3 - Low'); Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Urgency'; DisplayName='Urgency'; Type='Choice'; Choices=@('1 - High','2 - Medium','3 - Low'); Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Priority'; DisplayName='Priority'; Type='Choice'; Choices=@('1 - Critical','2 - High','3 - Moderate','4 - Low','5 - Planning'); Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ResponseHours'; DisplayName='Response Hours'; Type='Number'; Description='SLA: time to first response' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ResolutionHours'; DisplayName='Resolution Hours'; Type='Number'; Description='SLA: time to resolution' }
}

