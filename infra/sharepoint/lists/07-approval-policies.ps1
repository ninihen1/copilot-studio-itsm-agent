#Requires -Version 7.0

# Approval Policies list — named approval workflows with stages.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ApprovalPoliciesList {
    param([string]$ListTitle = 'Approval Policies')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Reusable approval workflows. Stages stored as JSON. Referenced by JobTypes, Categories, and Service Catalog.' `
        -EnableVersioning $true -MajorVersionLimit 50 | Out-Null

    # Phase B dedupe: PolicyId column dropped — Title now carries the policy id (e.g., AP-LOW-RISK-V1).
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Policy ID' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DisplayName'; DisplayName='Display Name'; Type='Text'; Required=$true; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Stages'; DisplayName='Stages (JSON)'; Type='Note'; RichText=$false; Required=$true; Description='JSON array of approval stages. See flows/approval/spec.md section 6.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PolicyVersion'; DisplayName='Version'; Type='Number'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PolicyStatus'; DisplayName='Status'; Type='Choice'; Choices=@('active','deprecated'); Required=$true; Indexed=$true; DefaultValue='active' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OwningTeam'; DisplayName='Owning Team'; Type='User' }

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='EffectiveUntil'; DisplayName='Effective Until'; Type='DateTime' }
}

