#Requires -Version 7.0

<#
.SYNOPSIS
One-shot silent runner for ALL remaining SharePoint setup after lists are provisioned:
seed Priority Matrix + Approval Policies + JobTypes, create the 5 SP groups, and stamp
list-level permissions. Uses cert-based app-only auth (Connect-ItsmTenantPilot) — no
device-code prompts.

.PARAMETER SiteUrl
ITSM site URL.

.EXAMPLE
./complete-sharepoint-setup.ps1
#>

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')

# ============================================================================
# Connect once
# ============================================================================
Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId

try {
    # ========================================================================
    # PRIORITY MATRIX  (9 rows: Impact x Urgency)
    # ========================================================================
    Write-Host "`n=== Seed: Priority Matrix ===" -ForegroundColor Cyan
    $matrix = @(
        @{ Key='1-1'; Impact='1 - High';   Urgency='1 - High';   Priority='1 - Critical';  ResponseHours=1;  ResolutionHours=4   },
        @{ Key='1-2'; Impact='1 - High';   Urgency='2 - Medium'; Priority='2 - High';      ResponseHours=2;  ResolutionHours=8   },
        @{ Key='1-3'; Impact='1 - High';   Urgency='3 - Low';    Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
        @{ Key='2-1'; Impact='2 - Medium'; Urgency='1 - High';   Priority='2 - High';      ResponseHours=2;  ResolutionHours=8   },
        @{ Key='2-2'; Impact='2 - Medium'; Urgency='2 - Medium'; Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
        @{ Key='2-3'; Impact='2 - Medium'; Urgency='3 - Low';    Priority='4 - Low';       ResponseHours=8;  ResolutionHours=48  },
        @{ Key='3-1'; Impact='3 - Low';    Urgency='1 - High';   Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
        @{ Key='3-2'; Impact='3 - Low';    Urgency='2 - Medium'; Priority='4 - Low';       ResponseHours=8;  ResolutionHours=48  },
        @{ Key='3-3'; Impact='3 - Low';    Urgency='3 - Low';    Priority='5 - Planning';  ResponseHours=24; ResolutionHours=120 }
    )
    foreach ($row in $matrix) {
        $existing = Get-PnPListItem -List 'Priority Matrix' -Query "<View><Query><Where><Eq><FieldRef Name='Key'/><Value Type='Text'>$($row.Key)</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-StateLine -State 'NO-CHANGE' -Object "PriorityMatrix.$($row.Key)" -Detail "(exists)"
        } else {
            Add-PnPListItem -List 'Priority Matrix' -Values @{
                Title=$row.Key; Key=$row.Key; Impact=$row.Impact; Urgency=$row.Urgency
                Priority=$row.Priority; ResponseHours=$row.ResponseHours; ResolutionHours=$row.ResolutionHours
            } | Out-Null
            Write-StateLine -State CREATED -Object "PriorityMatrix.$($row.Key)" -Detail "$($row.Priority) (resp=$($row.ResponseHours)h, res=$($row.ResolutionHours)h)"
        }
    }

    # ========================================================================
    # APPROVAL POLICIES  (6 v1 policies — no auto-approve)
    # ========================================================================
    Write-Host "`n=== Seed: Approval Policies ===" -ForegroundColor Cyan
    $policies = @(
        @{ PolicyId='AP-LOW-RISK-V1'; DisplayName='Low-Risk Approval';   Description='Default for low-risk job types. Single-stage manager approval.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_target","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":24,"onTimeout":"escalate"}]
'@ },
        @{ PolicyId='AP-MED-RISK-V1'; DisplayName='Medium-Risk Approval'; Description='Default for medium-risk job types. Manager + IT Owner.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_target","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":24,"onTimeout":"escalate"},{"name":"it_owner","approverResolver":{"type":"ci_owner","fallback":{"type":"group","value":"IT-ITSM-Admins"}},"rule":"any","timeoutHours":12,"onTimeout":"escalate"}]
'@ },
        @{ PolicyId='AP-HIGH-RISK-V1'; DisplayName='High-Risk Approval'; Description='Default for high-risk and Change Management. Manager + IT Owner + CAB majority.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_target","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":24,"onTimeout":"escalate"},{"name":"it_owner","approverResolver":{"type":"ci_owner","fallback":{"type":"group","value":"IT-ITSM-Admins"}},"rule":"any","timeoutHours":12,"onTimeout":"escalate"},{"name":"cab","approverResolver":{"type":"group","value":"Change-Advisory-Board"},"rule":"majority","timeoutHours":48,"onTimeout":"reject"}]
'@ },
        @{ PolicyId='AP-PWD-RESET-V1'; DisplayName='Password Reset Approval'; Description='identity.resetPassword. Single-stage manager approval, 8h timeout.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_target","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":8,"onTimeout":"escalate"}]
'@ },
        @{ PolicyId='AP-USER-CREATE-V1'; DisplayName='New User Creation Approval'; Description='identity.createUser. Manager + IT Owner + HR Confirmation.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_caller","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":24,"onTimeout":"escalate"},{"name":"it_owner","approverResolver":{"type":"group","value":"IT-ITSM-Admins"},"rule":"any","timeoutHours":12,"onTimeout":"escalate"},{"name":"hr_confirm","approverResolver":{"type":"group","value":"HR-Confirmation-Approvers"},"rule":"any","timeoutHours":24,"onTimeout":"reject"}]
'@ },
        @{ PolicyId='AP-USER-DISABLE-V1'; DisplayName='User Offboarding Approval'; Description='identity.disableUser. Manager + IT Owner.';
           Stages=@'
[{"name":"manager","approverResolver":{"type":"manager_of_target","fallback":{"type":"group","value":"IT-Approvers-Backup"}},"rule":"any","timeoutHours":24,"onTimeout":"escalate"},{"name":"it_owner","approverResolver":{"type":"group","value":"IT-ITSM-Admins"},"rule":"any","timeoutHours":12,"onTimeout":"escalate"}]
'@ }
    )
    foreach ($p in $policies) {
        $existing = Get-PnPListItem -List 'Approval Policies' -Query "<View><Query><Where><Eq><FieldRef Name='PolicyId'/><Value Type='Text'>$($p.PolicyId)</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-StateLine -State 'NO-CHANGE' -Object "ApprovalPolicy.$($p.PolicyId)" -Detail "(exists)"
        } else {
            Add-PnPListItem -List 'Approval Policies' -Values @{
                Title=$p.PolicyId; PolicyId=$p.PolicyId; DisplayName=$p.DisplayName; Description=$p.Description
                Stages=$p.Stages; PolicyVersion=1; PolicyStatus='active'; EffectiveFrom=(Get-Date).ToUniversalTime()
            } | Out-Null
            Write-StateLine -State CREATED -Object "ApprovalPolicy.$($p.PolicyId)"
        }
    }

    # ========================================================================
    # JOB TYPES  (12 entries) — DefaultPolicy lookup wired in 2nd pass
    # ========================================================================
    Write-Host "`n=== Seed: JobTypes ===" -ForegroundColor Cyan
    $jobTypes = @(
        @{ JobType='identity.resetPassword'; Category='identity'; RiskTier='low';    DefaultPolicy='AP-PWD-RESET-V1';      CompensationJobType=''; Description='Reset a user''s password. User must change on next login.'; InputSchema='{"type":"object","required":["forceChangeOnNextLogin"],"properties":{"forceChangeOnNextLogin":{"type":"boolean","default":true},"notifyUser":{"type":"boolean","default":true}}}'; RequiredScopes="UserAuthenticationMethod.ReadWrite.All`nDirectory.AccessAsUser.All" }
        @{ JobType='identity.disableUser';   Category='identity'; RiskTier='high';   DefaultPolicy='AP-USER-DISABLE-V1';   CompensationJobType='identity.enableUser'; Description='Disable a user account. Reversible within 30 days.'; InputSchema='{"type":"object","required":["reason"],"properties":{"reason":{"type":"string","enum":["offboarding","leave","security_incident","other"]},"transferOneDriveTo":{"type":"string","format":"email"}}}'; RequiredScopes="User.ReadWrite.All`nDirectory.AccessAsUser.All" }
        @{ JobType='identity.enableUser';    Category='identity'; RiskTier='medium'; DefaultPolicy='AP-MED-RISK-V1';       CompensationJobType='identity.disableUser'; Description='Re-enable a previously disabled user account.'; InputSchema='{"type":"object","properties":{"reason":{"type":"string"}}}'; RequiredScopes='User.ReadWrite.All' }
        @{ JobType='identity.createUser';    Category='identity'; RiskTier='high';   DefaultPolicy='AP-USER-CREATE-V1';    CompensationJobType='identity.disableUser'; Description='Create a new user account in Entra ID.'; InputSchema='{"type":"object","required":["displayName","upn","jobTitle","department","managerUpn"],"properties":{"displayName":{"type":"string"},"upn":{"type":"string","format":"email"},"jobTitle":{"type":"string"},"department":{"type":"string"},"managerUpn":{"type":"string","format":"email"},"officeLocation":{"type":"string"},"startDate":{"type":"string","format":"date"}}}'; RequiredScopes="User.ReadWrite.All`nDirectory.AccessAsUser.All" }
        @{ JobType='identity.resetMfa';      Category='identity'; RiskTier='medium'; DefaultPolicy='AP-MED-RISK-V1';       CompensationJobType=''; Description='Clear all MFA methods for a user, forcing re-registration.'; InputSchema='{"type":"object","properties":{"reason":{"type":"string"}}}'; RequiredScopes='UserAuthenticationMethod.ReadWrite.All' }
        @{ JobType='groups.addMember';       Category='groups';   RiskTier='low';    DefaultPolicy='AP-LOW-RISK-V1';       CompensationJobType='groups.removeMember'; Description='Add a user to a security group / M365 group / DL.'; InputSchema='{"type":"object","required":["groupId"],"properties":{"groupId":{"type":"string"},"groupName":{"type":"string"}}}'; RequiredScopes='GroupMember.ReadWrite.All' }
        @{ JobType='groups.removeMember';    Category='groups';   RiskTier='medium'; DefaultPolicy='AP-MED-RISK-V1';       CompensationJobType='groups.addMember'; Description='Remove a user from a group. Verify it''s not the only access path.'; InputSchema='{"type":"object","required":["groupId"],"properties":{"groupId":{"type":"string"},"groupName":{"type":"string"}}}'; RequiredScopes='GroupMember.ReadWrite.All' }
        @{ JobType='licensing.assign';       Category='licensing';RiskTier='low';    DefaultPolicy='AP-LOW-RISK-V1';       CompensationJobType='licensing.revoke'; Description='Assign a license SKU to a user (E3, E5, Power BI Pro, etc.).'; InputSchema='{"type":"object","required":["skuId"],"properties":{"skuId":{"type":"string"},"skuPartNumber":{"type":"string"}}}'; RequiredScopes="Directory.ReadWrite.All`nOrganization.Read.All" }
        @{ JobType='licensing.revoke';       Category='licensing';RiskTier='medium'; DefaultPolicy='AP-MED-RISK-V1';       CompensationJobType='licensing.assign'; Description='Revoke a license SKU. Triggers retention policies for the service.'; InputSchema='{"type":"object","required":["skuId"],"properties":{"skuId":{"type":"string"},"skuPartNumber":{"type":"string"}}}'; RequiredScopes='Directory.ReadWrite.All' }
        @{ JobType='exchange.grantFullAccess'; Category='exchange'; RiskTier='medium'; DefaultPolicy='AP-MED-RISK-V1';      CompensationJobType='exchange.revokeFullAccess'; Description='Grant Full Access on a mailbox.'; InputSchema='{"type":"object","required":["mailboxUpn"],"properties":{"mailboxUpn":{"type":"string","format":"email"},"automapping":{"type":"boolean","default":true}}}'; RequiredScopes="Mail.ReadWrite`nMailboxSettings.ReadWrite" }
        @{ JobType='exchange.revokeFullAccess'; Category='exchange'; RiskTier='low'; DefaultPolicy='AP-LOW-RISK-V1';        CompensationJobType='exchange.grantFullAccess'; Description='Revoke Full Access from a mailbox.'; InputSchema='{"type":"object","required":["mailboxUpn"],"properties":{"mailboxUpn":{"type":"string","format":"email"}}}'; RequiredScopes='Mail.ReadWrite' }
        @{ JobType='sharepoint.restoreFile'; Category='sharepoint';RiskTier='low';    DefaultPolicy='AP-LOW-RISK-V1';       CompensationJobType=''; Description='Restore a file from the SharePoint recycle bin within sites/ITSM.'; InputSchema='{"type":"object","required":["siteUrl","fileServerRelativeUrl"],"properties":{"siteUrl":{"type":"string"},"fileServerRelativeUrl":{"type":"string"}}}'; RequiredScopes='Sites.Selected (sites/ITSM, fullcontrol)' }
    )
    foreach ($jt in $jobTypes) {
        $existing = Get-PnPListItem -List 'JobTypes' -Query "<View><Query><Where><Eq><FieldRef Name='JobType'/><Value Type='Text'>$($jt.JobType)</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-StateLine -State 'NO-CHANGE' -Object "JobType.$($jt.JobType)" -Detail "(exists)"
        } else {
            Add-PnPListItem -List 'JobTypes' -Values @{
                Title=$jt.JobType; JobType=$jt.JobType; Category=$jt.Category; RiskTier=$jt.RiskTier
                InputSchema=$jt.InputSchema; RequiredScopes=$jt.RequiredScopes; CompensationJobType=$jt.CompensationJobType
                JobStatus='active'; Description=$jt.Description
            } | Out-Null
            Write-StateLine -State CREATED -Object "JobType.$($jt.JobType)" -Detail "$($jt.Category) $($jt.RiskTier)"
        }
    }
    # 2nd pass — DefaultPolicy lookup
    Write-Host "  --- linking DefaultPolicy lookups ---" -ForegroundColor DarkCyan
    foreach ($jt in $jobTypes) {
        $row = Get-PnPListItem -List 'JobTypes' -Query "<View><Query><Where><Eq><FieldRef Name='JobType'/><Value Type='Text'>$($jt.JobType)</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue
        if ($row) {
            $policyRow = Get-PnPListItem -List 'Approval Policies' -Query "<View><Query><Where><Eq><FieldRef Name='PolicyId'/><Value Type='Text'>$($jt.DefaultPolicy)</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue
            if ($policyRow) {
                $current = $row['DefaultPolicy']
                if (-not $current -or $current.LookupId -ne $policyRow.Id) {
                    Set-PnPListItem -List 'JobTypes' -Identity $row.Id -Values @{ DefaultPolicy = $policyRow.Id } | Out-Null
                    Write-StateLine -State UPDATED -Object "JobType.$($jt.JobType).DefaultPolicy" -Detail "-> $($jt.DefaultPolicy)"
                }
            }
        }
    }

    # ========================================================================
    # SHAREPOINT GROUPS  (5 groups — created empty; Catherine adds members later)
    # ========================================================================
    Write-Host "`n=== Create SharePoint groups ===" -ForegroundColor Cyan
    $groups = @(
        @{ Name='IT-ITSM-Admins';          Description='Admins of the ITSM solution. Members can edit any list item, manage Config (kill switch), and break inheritance.' }
        @{ Name='IT-Approvers-Backup';      Description='Fallback approvers when manager-of-target cannot be resolved.' }
        @{ Name='Change-Advisory-Board';    Description='Members of the CAB. Approve high-risk and Change Management tickets.' }
        @{ Name='HR-Confirmation-Approvers'; Description='HR partners who confirm new hires for identity.createUser approvals.' }
        @{ Name='ITSM-Agent-Users';         Description='All employees authorised to use the Triage Agent. Read on Tickets / KB / CMDB / Categories / Service Catalog.' }
    )
    foreach ($g in $groups) {
        $existing = Get-PnPGroup -Identity $g.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-StateLine -State 'NO-CHANGE' -Object "SPGroup.$($g.Name)" -Detail "(exists)"
        } else {
            New-PnPGroup -Title $g.Name -Description $g.Description | Out-Null
            Write-StateLine -State CREATED -Object "SPGroup.$($g.Name)"
        }
    }

    Write-Host "`n========== SETUP COMPLETE ==========" -ForegroundColor Green
    Write-Host "Lists provisioned + seeded + groups created. Membership and per-list permissions are still TODO (manual)." -ForegroundColor Gray

} finally {
    Disconnect-PnPOnline
}
