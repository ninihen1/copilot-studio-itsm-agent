#Requires -Version 7.0

<#
.SYNOPSIS
Captures live Day 4 validation evidence for the ITSM pilot.

.DESCRIPTION
This is intentionally read-only. It checks seed/list counts and the most important
Day 4 wiring dependencies that the Kanban uses as completion evidence.
#>

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020',
    [string]$OutputPath = 'prompts/day4_live_state_audit.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../infra/sharepoint/lists/_helpers.ps1')

Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId

try {
    $listNames = @(
        'Categories',
        'Subcategories',
        'Service Catalog',
        'JobTypes',
        'Priority Matrix',
        'Approval Policies',
        'Config',
        'Knowledge Base',
        'License Costs',
        'Tickets',
        'Tickets-Archive',
        'Request Items',
        'Tasks',
        'Approvals',
        'ApprovalStages',
        'Provisioning Jobs'
    )

    $counts = foreach ($name in $listNames) {
        $list = Get-PnPList -Identity $name
        [pscustomobject]@{
            List = $name
            ItemCount = $list.ItemCount
        }
    }

    $serviceCatalog = Get-PnPListItem -List 'Service Catalog' -PageSize 1000 -Fields 'Title','ItemStatus','JobType','ApprovalPolicy'
    $jobTypes = Get-PnPListItem -List 'JobTypes' -PageSize 1000 -Fields 'Title','JobStatus','InputSchema','DefaultPolicy'
    $priorityRows = Get-PnPListItem -List 'Priority Matrix' -PageSize 1000 -Fields 'Title','Impact','Urgency','Priority'
    $policies = Get-PnPListItem -List 'Approval Policies' -PageSize 1000 -Fields 'Title','PolicyStatus','Stages'
    $configRows = Get-PnPListItem -List 'Config' -PageSize 1000 -Fields 'Title','Value','Environment'
    $kbRows = Get-PnPListItem -List 'Knowledge Base' -PageSize 1000 -Fields 'ArticleNumber','ArticleStatus'
    $ticketFields = Get-PnPField -List 'Tickets' | Select-Object -ExpandProperty InternalName
    $pjFields = Get-PnPField -List 'Provisioning Jobs' | Select-Object -ExpandProperty InternalName

    $evidence = [pscustomobject]@{
        CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
        SiteUrl = $SiteUrl
        Lists = $counts
        SeedValidation = [pscustomobject]@{
            Categories = ($counts | Where-Object List -eq 'Categories').ItemCount
            Subcategories = ($counts | Where-Object List -eq 'Subcategories').ItemCount
            ActiveServiceCatalogItems = @($serviceCatalog | Where-Object { $_['ItemStatus'] -eq 'Active' }).Count
            ActiveJobTypes = @($jobTypes | Where-Object { $_['JobStatus'] -eq 'active' }).Count
            PriorityMatrixRows = @($priorityRows).Count
            ActiveApprovalPolicies = @($policies | Where-Object { $_['PolicyStatus'] -eq 'active' }).Count
            ConfigRows = @($configRows).Count
            PublishedKnowledgeArticles = @($kbRows | Where-Object { $_['ArticleStatus'] -eq 'Published' }).Count
        }
        ProposeActionDependencies = [pscustomobject]@{
            TicketsFieldsPresent = @('TicketSource','CategoryRef','Subcategory','Caller','TicketState','ShortDescription') | ForEach-Object {
                [pscustomobject]@{ Field = $_; Present = $_ -in $ticketFields }
            }
            ProvisioningJobFieldsPresent = @('JobType','ParentTicket','JobStatus','CallerUpn','TargetJson','ArgsJson','IdempotencyKey','CorrelationId','Risk','Rationale') | ForEach-Object {
                [pscustomobject]@{ Field = $_; Present = $_ -in $pjFields }
            }
            CatalogJobTypes = @($serviceCatalog | Where-Object { -not [string]::IsNullOrWhiteSpace($_['JobType']) } | ForEach-Object { $_['JobType'] } | Sort-Object -Unique)
            JobTypeRegistry = @($jobTypes | ForEach-Object { $_['Title'] } | Sort-Object -Unique)
        }
        Verdict = 'PASS'
    }

    $missing = @(
        $evidence.ProposeActionDependencies.TicketsFieldsPresent | Where-Object { -not $_.Present }
        $evidence.ProposeActionDependencies.ProvisioningJobFieldsPresent | Where-Object { -not $_.Present }
    )

    if ($missing.Count -gt 0) {
        $evidence.Verdict = 'FAIL'
    }

    $out = Join-Path (Get-Location) $OutputPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $out -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 20
} finally {
    Disconnect-PnPOnline
}
