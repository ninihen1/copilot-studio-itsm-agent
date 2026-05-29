#Requires -Version 7.0

# ApprovalStages list — per-stage decision audit. One row per stage attempt incl. timeouts and escalations.
# Source: flows/approval/spec.md section 9
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ApprovalStagesList {
    param([string]$ListTitle = 'ApprovalStages')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Per-stage approval audit. One row per stage attempt incl. escalations and timeouts.' `
        -EnableVersioning $true -MajorVersionLimit 25 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApprovalSessionId'; DisplayName='Approval Session ID'; Type='Text'; Required=$true; Indexed=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='LinkedJobId'; DisplayName='Job ID'; Type='Text'; Indexed=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='StageName'; DisplayName='Stage Name'; Type='Text'; Required=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='StageOrder'; DisplayName='Stage Order'; Type='Number'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApproversResolved'; DisplayName='Approvers Resolved'; Type='Note'; RichText=$false; Description='JSON array of UPNs the resolver chose' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApproversWhoActed'; DisplayName='Approvers Who Acted'; Type='Note'; RichText=$false; Description='JSON array: { upn, decision, time, comment }' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Rule'; DisplayName='Rule'; Type='Choice'; Choices=@('any','all','majority') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Outcome'; DisplayName='Outcome'; Type='Choice'; Choices=@('approved','rejected','timeout','escalated','revoked'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='StartedAt'; DisplayName='Started At'; Type='DateTime'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CompletedAt'; DisplayName='Completed At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DurationMinutes'; DisplayName='Duration (min)'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='EscalatedFrom'; DisplayName='Escalated From'; Type='Text'; MaxLength=128; Description='UPN of original approver if this row is an escalation' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Comments'; DisplayName='Comments'; Type='Note'; RichText=$false; AppendOnly=$true }
}

