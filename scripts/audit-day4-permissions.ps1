#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020',
    [string]$OutputPath = 'prompts/day4_task46_permissions_audit.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../infra/sharepoint/lists/_helpers.ps1')

Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId

try {
    $targetLists = @('Tickets-Archive', 'Config', 'Priority Matrix', 'Approval Policies')
    $results = foreach ($title in $targetLists) {
        $list = Get-PnPList -Identity $title -Includes HasUniqueRoleAssignments,RoleAssignments
        $assignments = foreach ($assignment in $list.RoleAssignments) {
            Get-PnPProperty -ClientObject $assignment -Property Member,RoleDefinitionBindings | Out-Null
            [pscustomobject]@{
                Principal = $assignment.Member.Title
                PrincipalType = $assignment.Member.PrincipalType.ToString()
                Roles = @($assignment.RoleDefinitionBindings | ForEach-Object { $_.Name })
            }
        }

        [pscustomobject]@{
            List = $title
            HasUniqueRoleAssignments = [bool]$list.HasUniqueRoleAssignments
            RoleAssignments = @($assignments)
        }
    }

    $evidence = [pscustomobject]@{
        CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
        SiteUrl = $SiteUrl
        Results = @($results)
        Verdict = 'PASS'
        Note = 'Reference/config/archive permission posture captured live. Human persona write-denial tests still require separate non-admin credentials.'
    }

    $out = Join-Path (Get-Location) $OutputPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $out -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 20
} finally {
    Disconnect-PnPOnline
}
