#Requires -Version 7.0

<#
.SYNOPSIS
Seeds the Approval Policies list with the 6 v1 policies (no auto-approve).
Source: flows/approval/spec.md section 5.
Idempotent — re-runs are no-ops if the same PolicyId already exists.
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

# Stage definitions follow flows/approval/spec.md §6.
# All policies have onTimeout=escalate (max 1 escalation per stage); CAB final stages onTimeout=reject.

$policies = @(
    @{
        PolicyId = 'AP-LOW-RISK-V1'
        DisplayName = 'Low-Risk Approval'
        Description = 'Default for low-risk job types. Single-stage manager approval.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_target", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "escalate"
  }
]
"@
    },
    @{
        PolicyId = 'AP-MED-RISK-V1'
        DisplayName = 'Medium-Risk Approval'
        Description = 'Default for medium-risk job types. Manager + IT Owner.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_target", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "escalate"
  },
  {
    "name": "it_owner",
    "approverResolver": { "type": "ci_owner", "fallback": { "type": "group", "value": "IT-ITSM-Admins" } },
    "rule": "any",
    "timeoutHours": 12,
    "onTimeout": "escalate"
  }
]
"@
    },
    @{
        PolicyId = 'AP-HIGH-RISK-V1'
        DisplayName = 'High-Risk Approval'
        Description = 'Default for high-risk and Change Management. Manager + IT Owner + CAB majority.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_target", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "escalate"
  },
  {
    "name": "it_owner",
    "approverResolver": { "type": "ci_owner", "fallback": { "type": "group", "value": "IT-ITSM-Admins" } },
    "rule": "any",
    "timeoutHours": 12,
    "onTimeout": "escalate"
  },
  {
    "name": "cab",
    "approverResolver": { "type": "group", "value": "Change-Advisory-Board" },
    "rule": "majority",
    "timeoutHours": 48,
    "onTimeout": "reject"
  }
]
"@
    },
    @{
        PolicyId = 'AP-PWD-RESET-V1'
        DisplayName = 'Password Reset Approval'
        Description = 'Specific to identity.resetPassword. Single-stage manager approval — same shape as low-risk but pinned for clarity.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_target", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 8,
    "onTimeout": "escalate"
  }
]
"@
    },
    @{
        PolicyId = 'AP-USER-CREATE-V1'
        DisplayName = 'New User Creation Approval'
        Description = 'identity.createUser. Manager + IT Owner + HR confirmation that the hire is real.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_caller", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "escalate"
  },
  {
    "name": "it_owner",
    "approverResolver": { "type": "group", "value": "IT-ITSM-Admins" },
    "rule": "any",
    "timeoutHours": 12,
    "onTimeout": "escalate"
  },
  {
    "name": "hr_confirm",
    "approverResolver": { "type": "group", "value": "HR-Confirmation-Approvers" },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "reject"
  }
]
"@
    },
    @{
        PolicyId = 'AP-USER-DISABLE-V1'
        DisplayName = 'User Offboarding Approval'
        Description = 'identity.disableUser. Manager + IT Owner.'
        Stages = @"
[
  {
    "name": "manager",
    "approverResolver": { "type": "manager_of_target", "fallback": { "type": "group", "value": "IT-Approvers-Backup" } },
    "rule": "any",
    "timeoutHours": 24,
    "onTimeout": "escalate"
  },
  {
    "name": "it_owner",
    "approverResolver": { "type": "group", "value": "IT-ITSM-Admins" },
    "rule": "any",
    "timeoutHours": 12,
    "onTimeout": "escalate"
  }
]
"@
    }
)

Write-Host "`n=== Seeding Approval Policies (v1: no auto-approve) ===" -ForegroundColor Cyan
$createdOrExistingIds = @{}
foreach ($p in $policies) {
    # Phase B dedupe: PolicyId column was removed; Title now carries the policy id.
    $existing = Get-PnPListItem -List 'Approval Policies' -Query @"
<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($p.PolicyId)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($existing) {
        Write-StateLine -State 'NO-CHANGE' -Object "ApprovalPolicy.$($p.PolicyId)" -Detail "(exists)"
        $createdOrExistingIds[$p.PolicyId] = @{ Id = $existing.Id; DisplayName = $p.DisplayName }
    } else {
        # NOTE: DisplayName is intentionally OMITTED from this Add-PnPListItem call.
        # PnP silently drops the DisplayName field because it collides with SP's
        # built-in user-profile DisplayName identifier. Confirmed empirically
        # 2026-05-01 — Add-PnPListItem succeeds, all other fields populate, but
        # DisplayName remains blank even though Required=true.
        # Workaround: do a 2nd-pass PATCH via Microsoft Graph after creation
        # (see Graph-patch block below). The Graph items API is not affected by
        # the PnP-side collision.
        $created = Add-PnPListItem -List 'Approval Policies' -Values @{
            Title         = $p.PolicyId
            Description   = $p.Description
            Stages        = $p.Stages
            PolicyVersion = 1
            PolicyStatus  = 'active'
        }
        Write-StateLine -State CREATED -Object "ApprovalPolicy.$($p.PolicyId)"
        $createdOrExistingIds[$p.PolicyId] = @{ Id = $created.Id; DisplayName = $p.DisplayName }
    }
}

# === 2nd-pass: patch DisplayName via Graph (PnP collision workaround) ===
Write-Host "`n=== Patching DisplayName via Graph (PnP collision workaround) ===" -ForegroundColor Cyan
$gToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or -not $gToken) {
    Write-Host "  WARN: az CLI not signed in — DisplayName patch skipped. Run: az login" -ForegroundColor Yellow
    Write-Host "  Then re-run: the policies are seeded except DisplayName field." -ForegroundColor Yellow
} else {
    $gh = @{ Authorization = "Bearer $gToken"; 'Content-Type' = 'application/json' }
    $tenantHost = ([uri]$SiteUrl).Host
    $sitePath = ([uri]$SiteUrl).AbsolutePath
    $siteId = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/${tenantHost}:${sitePath}" -Headers $gh).id
    $listId = ((Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$filter=displayName eq 'Approval Policies'" -Headers $gh).value)[0].id
    foreach ($policyId in $createdOrExistingIds.Keys) {
        $entry = $createdOrExistingIds[$policyId]
        $body = @{ fields = @{ DisplayName = $entry.DisplayName } } | ConvertTo-Json
        try {
            Invoke-RestMethod -Method PATCH -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$($entry.Id)" -Headers $gh -Body $body | Out-Null
            Write-StateLine -State PATCHED -Object "ApprovalPolicy.$policyId.DisplayName" -Detail $entry.DisplayName
        } catch {
            Write-StateLine -State FAIL -Object "ApprovalPolicy.$policyId.DisplayName" -Detail $_.Exception.Message
        }
    }
}

Disconnect-PnPOnline
Write-Host "`nApproval Policies seeded." -ForegroundColor Green
Write-Host "Reminder: SP groups 'IT-Approvers-Backup', 'IT-ITSM-Admins', 'Change-Advisory-Board', 'HR-Confirmation-Approvers' must exist in /sites/ITSM with members assigned." -ForegroundColor DarkYellow
