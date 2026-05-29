#Requires -Version 7.0

<#
.SYNOPSIS
Seeds the JobTypes list with the initial v1 registry.
Idempotent — re-runs are no-ops if the same JobType already exists.

Initial set: 12 job types covering the 6 executor categories.
Pilot Week 2 starts with identity.resetPassword only.
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

$jobTypes = @(
    # ===== Identity =====
    @{
        JobType = 'identity.resetPassword'
        Category = 'identity'
        RiskTier = 'low'
        DefaultPolicy = 'AP-PWD-RESET-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["forceChangeOnNextLogin"],
  "properties": {
    "forceChangeOnNextLogin": { "type": "boolean", "default": true },
    "notifyUser": { "type": "boolean", "default": true }
  }
}
"@
        RequiredScopes = "UserAuthenticationMethod.ReadWrite.All`nDirectory.AccessAsUser.All"
        CompensationJobType = ''
        Description = 'Reset a user''s password. User must change on next login. Used for forgotten passwords or post-incident resets.'
    },
    @{
        JobType = 'identity.disableUser'
        Category = 'identity'
        RiskTier = 'high'
        DefaultPolicy = 'AP-USER-DISABLE-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["reason"],
  "properties": {
    "reason": { "type": "string", "enum": ["offboarding","leave","security_incident","other"] },
    "transferOneDriveTo": { "type": "string", "format": "email" }
  }
}
"@
        RequiredScopes = "User.ReadWrite.All`nDirectory.AccessAsUser.All"
        CompensationJobType = 'identity.enableUser'
        Description = 'Disable a user account. Sets accountEnabled=false. Reversible within 30 days. Use for offboarding, extended leave, or security incidents.'
    },
    @{
        JobType = 'identity.enableUser'
        Category = 'identity'
        RiskTier = 'medium'
        DefaultPolicy = 'AP-MED-RISK-V1'
        InputSchema = @"
{ "type": "object", "properties": { "reason": { "type": "string" } } }
"@
        RequiredScopes = "User.ReadWrite.All"
        CompensationJobType = 'identity.disableUser'
        Description = 'Re-enable a previously disabled user account.'
    },
    @{
        JobType = 'identity.createUser'
        Category = 'identity'
        RiskTier = 'high'
        DefaultPolicy = 'AP-USER-CREATE-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["displayName","upn","jobTitle","department","managerUpn"],
  "properties": {
    "displayName": { "type": "string" },
    "upn": { "type": "string", "format": "email" },
    "jobTitle": { "type": "string" },
    "department": { "type": "string" },
    "managerUpn": { "type": "string", "format": "email" },
    "officeLocation": { "type": "string" },
    "startDate": { "type": "string", "format": "date" }
  }
}
"@
        RequiredScopes = "User.ReadWrite.All`nDirectory.AccessAsUser.All"
        CompensationJobType = 'identity.disableUser'
        Description = 'Create a new user account in Entra ID. Triggered by HR-confirmed onboarding.'
    },
    @{
        JobType = 'identity.clearMfa'
        Category = 'identity'
        RiskTier = 'medium'
        DefaultPolicy = 'AP-MED-RISK-V1'
        InputSchema = @"
{ "type": "object", "properties": { "reason": { "type": "string" } } }
"@
        RequiredScopes = "UserAuthenticationMethod.ReadWrite.All"
        CompensationJobType = ''
        Description = 'Clear all MFA methods for a user, forcing re-registration on next sign-in. Use when user lost a phone or token.'
    },
    # ===== Groups =====
    @{
        JobType = 'groups.addMember'
        Category = 'groups'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["groupId"],
  "properties": {
    "groupId": { "type": "string" },
    "groupName": { "type": "string" }
  }
}
"@
        RequiredScopes = "GroupMember.ReadWrite.All"
        CompensationJobType = 'groups.removeMember'
        Description = 'Add a user to a security group, M365 group, or distribution list.'
    },
    @{
        JobType = 'groups.removeMember'
        Category = 'groups'
        RiskTier = 'medium'
        DefaultPolicy = 'AP-MED-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["groupId"],
  "properties": {
    "groupId": { "type": "string" },
    "groupName": { "type": "string" }
  }
}
"@
        RequiredScopes = "GroupMember.ReadWrite.All"
        CompensationJobType = 'groups.addMember'
        Description = 'Remove a user from a group. Higher risk than add — verify the group is not the user''s only access path to a system.'
    },
    # ===== Licensing =====
    @{
        JobType = 'licensing.assign'
        Category = 'licensing'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["skuId"],
  "properties": {
    "skuId": { "type": "string", "description": "SkuId GUID from /subscribedSkus" },
    "skuPartNumber": { "type": "string" }
  }
}
"@
        RequiredScopes = "Directory.ReadWrite.All`nOrganization.Read.All"
        CompensationJobType = 'licensing.revoke'
        Description = 'Assign a license SKU to a user. E.g., E3, E5, Power BI Pro.'
    },
    @{
        JobType = 'licensing.revoke'
        Category = 'licensing'
        RiskTier = 'medium'
        DefaultPolicy = 'AP-MED-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["skuId"],
  "properties": {
    "skuId": { "type": "string" },
    "skuPartNumber": { "type": "string" }
  }
}
"@
        RequiredScopes = "Directory.ReadWrite.All"
        CompensationJobType = 'licensing.assign'
        Description = 'Revoke a license SKU from a user. Triggers data retention policies for the affected service.'
    },
    # ===== Exchange =====
    @{
        JobType = 'exchange.grantFullAccess'
        Category = 'exchange'
        RiskTier = 'medium'
        DefaultPolicy = 'AP-MED-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["mailboxUpn"],
  "properties": {
    "mailboxUpn": { "type": "string", "format": "email" },
    "automapping": { "type": "boolean", "default": true }
  }
}
"@
        RequiredScopes = "Mail.ReadWrite`nMailboxSettings.ReadWrite"
        CompensationJobType = 'exchange.revokeFullAccess'
        Description = 'Grant Full Access permission to a user on another mailbox. Use for shared mailboxes and absences.'
    },
    @{
        JobType = 'exchange.revokeFullAccess'
        Category = 'exchange'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["mailboxUpn"],
  "properties": {
    "mailboxUpn": { "type": "string", "format": "email" }
  }
}
"@
        RequiredScopes = "Mail.ReadWrite"
        CompensationJobType = 'exchange.grantFullAccess'
        Description = 'Revoke Full Access permission from a user on a mailbox.'
    },
    # ===== SharePoint =====
    @{
        JobType = 'sharepoint.restoreFile'
        Category = 'sharepoint'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["siteUrl","fileServerRelativeUrl"],
  "properties": {
    "siteUrl": { "type": "string" },
    "fileServerRelativeUrl": { "type": "string" }
  }
}
"@
        RequiredScopes = "Sites.Selected (sites/ITSM, fullcontrol)"
        CompensationJobType = ''
        Description = 'Restore a file from the SharePoint recycle bin within sites/ITSM.'
    },
    # ===== Teams (Phase 3.1 — added 2026-05-02 to match SP-IT-Teams executor scope) =====
    @{
        JobType = 'teams.createChannel'
        Category = 'teams'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["channelName"],
  "properties": {
    "channelName": { "type": "string", "maxLength": 50 },
    "description": { "type": "string", "maxLength": 1024 },
    "membershipType": { "type": "string", "enum": ["standard", "private", "shared"], "default": "standard" }
  }
}
"@
        RequiredScopes = "Channel.Create`nGroup.ReadWrite.All"
        CompensationJobType = ''
        Description = 'Create a new channel under an existing Microsoft Teams team. Target.id is the team id.'
    },
    @{
        JobType = 'teams.addChannelMember'
        Category = 'teams'
        RiskTier = 'low'
        DefaultPolicy = 'AP-LOW-RISK-V1'
        InputSchema = @"
{
  "type": "object",
  "required": ["channelId"],
  "properties": {
    "channelId": { "type": "string", "description": "Channel id within the team" },
    "roles": { "type": "array", "items": { "type": "string", "enum": ["owner"] }, "default": [] }
  }
}
"@
        RequiredScopes = "ChannelMember.ReadWrite.All`nGroup.ReadWrite.All"
        CompensationJobType = ''
        Description = 'Add a user as a member (or owner) of a Teams channel. Target.upn is the user being added; Target.id is the team id.'
    }
)

Write-Host "`n=== Seeding JobTypes registry ===" -ForegroundColor Cyan
foreach ($jt in $jobTypes) {
    $existing = Get-PnPListItem -List 'JobTypes' -Query @"
<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($jt.JobType)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($existing) {
        Write-StateLine -State 'NO-CHANGE' -Object "JobType.$($jt.JobType)" -Detail "(exists)"
    } else {
        Add-PnPListItem -List 'JobTypes' -Values @{
            Title               = $jt.JobType
            Category            = $jt.Category
            RiskTier            = $jt.RiskTier
            InputSchema         = $jt.InputSchema
            RequiredScopes      = $jt.RequiredScopes
            CompensationJobType = $jt.CompensationJobType
            JobStatus           = 'active'
            Description         = $jt.Description
        } | Out-Null
        Write-StateLine -State CREATED -Object "JobType.$($jt.JobType)" -Detail "$($jt.Category) $($jt.RiskTier)"

        # NOTE: DefaultPolicy lookup is set in a second pass after Approval Policies are seeded.
        # Re-run this script after seed-approval-policies.ps1 to populate the lookup; the NO-CHANGE branch handles existing rows.
    }
}

# Second pass — set DefaultPolicy lookup now that Approval Policies should exist.
Write-Host "`n--- Second pass: linking DefaultPolicy lookups ---" -ForegroundColor Cyan
foreach ($jt in $jobTypes) {
    $row = Get-PnPListItem -List 'JobTypes' -Query @"
<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($jt.JobType)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($row) {
        $policyRow = Get-PnPListItem -List 'Approval Policies' -Query @"
<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($jt.DefaultPolicy)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

        if ($policyRow) {
            $currentPolicyId = $row['DefaultPolicy']
            if ($currentPolicyId.LookupId -ne $policyRow.Id) {
                Set-PnPListItem -List 'JobTypes' -Identity $row.Id -Values @{ DefaultPolicy = $policyRow.Id } | Out-Null
                Write-StateLine -State UPDATED -Object "JobType.$($jt.JobType).DefaultPolicy" -Detail "-> $($jt.DefaultPolicy)"
            }
        } else {
            Write-StateLine -State 'SKIPPED' -Object "JobType.$($jt.JobType).DefaultPolicy" -Detail "(policy '$($jt.DefaultPolicy)' not found — run seed-approval-policies.ps1 first)"
        }
    }
}

Disconnect-PnPOnline
Write-Host "`nJobTypes seeded." -ForegroundColor Green
