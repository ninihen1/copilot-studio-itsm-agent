#Requires -Version 7.0

# Config list — kill switch + per-environment toggles. Referenced by dispatcher §7.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ConfigList {
    param([string]$ListTitle = 'Config')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'System-level configuration. Kill switch + per-environment toggles. Item-level perms restrict edit to IT-ITSM-Admins SP group.' `
        -EnableVersioning $true -MajorVersionLimit 100 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Key'; DisplayName='Key'; Type='Text'; Required=$true; Indexed=$true; MaxLength=128 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Value'; DisplayName='Value'; Type='Note'; RichText=$false; Required=$true; Description='String value. Booleans stored as "true"/"false". JSON allowed.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ChangedBy'; DisplayName='Changed By'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ChangedAt'; DisplayName='Changed At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ChangeReason'; DisplayName='Change Reason'; Type='Note'; RichText=$false; Required=$true; Description='Mandatory rationale for any change. Audit critical.' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Environment'; DisplayName='Environment'; Type='Choice'; Choices=@('all','dev','staging','prod'); Required=$true; DefaultValue='all'; Indexed=$true }

    Write-Host "  TODO (manual): break inheritance and grant Edit to IT-ITSM-Admins SP group only; everyone else Read." -ForegroundColor DarkYellow
}

