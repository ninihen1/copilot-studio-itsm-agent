#Requires -Version 7.0

<#
.SYNOPSIS
Seeds the Categories list with the agent's working vocabulary.
Idempotent — re-runs are no-ops if the same Title already exists.

The agent's classification (during TriageFromFlow's reasoning) emits category strings
from a broader vocabulary than the original 6 ITSM-OOB categories. The orchestrator
does an exact-Title match on this list to populate Tickets.CategoryRef. If the agent's
text doesn't match an existing row, the lookup falls back to "General Inquiry" (id 6).

This seed adds 7 categories aligned with the agent's natural vocabulary AND with the
JobTypes namespace families (identity.* / groups.* / licensing.* / sharepoint.*) so
proposed actions can be routed and reported on by category.

.PARAMETER SiteUrl
ITSM site URL.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [Parameter(Mandatory)][string]$CertificateName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')
Connect-ItsmTenant -SiteUrl $SiteUrl -AppId $AppId -KeyVaultName $KeyVaultName -CertificateName $CertificateName

# Original 6 categories (legacy ITSM OOB) — created before the agent vocabulary was
# aligned. Kept for backwards compatibility with any tickets/CIs already referencing them.
$legacyCategories = @(
    @{ Name='Account & Access';        Desc='Legacy category — see Identity & Access Management for new tickets.';   Sort=1 },
    @{ Name='Hardware';                Desc='Laptops, desktops, peripherals, printers, monitors.';                    Sort=2 },
    @{ Name='Software';                Desc='Application installation, licensing requests, software bugs.';           Sort=3 },
    @{ Name='Email & Messaging';       Desc='Outlook, Exchange Online, mail flow, calendar, distribution lists.';     Sort=4 },
    @{ Name='Network & Connectivity';  Desc='VPN, wifi, internet, DNS, firewall.';                                    Sort=5 },
    @{ Name='General Inquiry';         Desc='Default catch-all — used when category cannot be determined.';           Sort=6 }
)

# Agent-vocabulary categories (added 2026-05-01 after Catherine's column audit found
# the orchestrator's category lookup was always falling back to General Inquiry).
$agentCategories = @(
    @{ Name='Identity & Access Management'; Desc='Passwords, MFA, account lockouts, user creation/disable. Maps to identity.* job types.'; Sort=10 },
    @{ Name='Groups & Permissions';         Desc='Group membership, role assignment, access requests. Maps to groups.* job types.';         Sort=20 },
    @{ Name='Licensing';                     Desc='Microsoft 365 license assignment / removal, license requests. Maps to licensing.* job types.'; Sort=30 },
    @{ Name='SharePoint & Files';            Desc='SharePoint sites, OneDrive, file restoration, document permissions. Maps to sharepoint.* job types.'; Sort=40 },
    @{ Name='Teams & Collaboration';         Desc='Microsoft Teams channels, meetings, Teams app issues, collaboration tooling.';            Sort=50 },
    @{ Name='Mobile & Endpoint';             Desc='Phone enrollment, MDM, endpoint device wipe/reset, BYOD configuration.';                  Sort=60 },
    @{ Name='Security & Compliance';         Desc='Security incidents, suspicious activity, phishing reports, compliance/policy questions.'; Sort=70 }
)

# Phase 3 — research-parity categories (added 2026-05-02 to close coverage gaps vs servicenow-itsm-ticketing-report.md §4.1).
# Five categories were missing or only partially covered: Telecom voice/comms, Facilities, HR cross-over, Database/Storage, and Reporting/Analytics.
$researchCategories = @(
    @{ Name='Telecom & Mobile';        Desc='Cell phones, number ports, international access, plan changes, conference bridges, desk phones. Distinct from Mobile & Endpoint (which covers MDM/device).'; Sort=80 },
    @{ Name='Facilities';              Desc='Desk moves, badge / physical access, parking. Cross-over with HR / facilities team.';                  Sort=90 },
    @{ Name='HR Cross-Over';           Desc='HRSD-style requests that touch IT: onboarding, offboarding, name/address change, leave, benefits, tuition reimbursement.'; Sort=100 },
    @{ Name='Database & Storage';      Desc='Database schema changes, DB access grants, file share quota, restore from backup. Distinct from SharePoint & Files.'; Sort=110 },
    @{ Name='Reporting & Analytics';   Desc='New report requests, Power BI access, dashboard sharing, data extracts.';                              Sort=120 }
)

$all = $legacyCategories + $agentCategories + $researchCategories
$existingTitles = Get-PnPListItem -List Categories | ForEach-Object { $_.FieldValues['Title'] }

Write-Host "`n=== Seeding Categories ($($all.Count) total) ===" -ForegroundColor Cyan
foreach ($c in $all) {
    if ($existingTitles -contains $c.Name) {
        Write-StateLine -State 'NO-CHANGE' -Object "Category.$($c.Name)" -Detail "(exists)"
        continue
    }
    Add-PnPListItem -List Categories -Values @{
        Title        = $c.Name
        Description  = $c.Desc
        Status       = 'active'
        SortOrder    = $c.Sort
    } | Out-Null
    Write-StateLine -State CREATED -Object "Category.$($c.Name)"
}

Disconnect-PnPOnline
Write-Host "`nCategories seeded. The orchestrator's Get_CategoryId lookup will now match the agent's vocabulary." -ForegroundColor Green
