#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')

function Set-ListRoles {
    param(
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][hashtable]$Assignments
    )

    Write-Host "`n=== $ListTitle permissions ===" -ForegroundColor Cyan
    Set-PnPList -Identity $ListTitle -BreakRoleInheritance -CopyRoleAssignments:$false -ClearSubscopes:$true | Out-Null

    foreach ($principal in $Assignments.Keys) {
        foreach ($role in @($Assignments[$principal])) {
            Set-PnPListPermission -Identity $ListTitle -Group $principal -AddRole $role | Out-Null
            Write-Host "  $principal -> $role" -ForegroundColor Green
        }
    }
}

Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId

try {
    Set-ListRoles -ListTitle 'Tickets-Archive' -Assignments @{
        'ITSM Owners' = @('Full Control')
        'ITSM Admins' = @('Full Control')
        'ITSM Agents' = @('Read')
    }

    Set-ListRoles -ListTitle 'Config' -Assignments @{
        'ITSM Owners' = @('Full Control')
        'ITSM Admins' = @('Full Control')
        'ITSM Agents' = @('Read')
    }

    Set-ListRoles -ListTitle 'Priority Matrix' -Assignments @{
        'ITSM Owners' = @('Full Control')
        'ITSM Admins' = @('Full Control')
        'ITSM Agents' = @('Read')
        'ITSM Approvers' = @('Read')
        'ITSM Users' = @('Read')
    }

    Set-ListRoles -ListTitle 'Approval Policies' -Assignments @{
        'ITSM Owners' = @('Full Control')
        'ITSM Admins' = @('Full Control')
        'ITSM Agents' = @('Read')
        'ITSM Approvers' = @('Read')
    }
} finally {
    Disconnect-PnPOnline
}
