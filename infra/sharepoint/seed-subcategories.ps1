#Requires -Version 7.0

<#
.SYNOPSIS
Seeds the Subcategories list with ~80 subcategories across all 18 top-level categories.
Idempotent — re-runs are no-ops if the same Title already exists under the same ParentCategory.

Source: servicenow-itsm-ticketing-report.md §4.1 — research baseline taxonomy (50+ subcategories
expanded for our 18 categories vs. ServiceNow's 12 reference categories).

Two-pass execution:
1. Insert the row with Title + Description + Status + SortOrder + JobTypeHint
2. Look up the ParentCategory's SP int Id and PATCH the lookup field via Set-PnPListItem
This avoids the Add-PnPListItem-with-Lookup gotcha where the Lookup column on a brand-new list
sometimes doesn't accept the int Id on the first call.
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

# Subcategory definitions, organized by parent category for review clarity.
# JobTypeHint maps subcategory → suggested jobType for the triage agent (empty = human-fulfilled).
$subcategories = @(
    # ===== Hardware (legacy, sort=2) =====
    @{ Parent='Hardware'; Name='Laptop / Desktop';     Sort=10; Desc='New laptop or desktop request. Replacement, upgrade, or new hire.';     JobTypeHint='' }
    @{ Parent='Hardware'; Name='Monitor';              Sort=20; Desc='External monitor request, replacement, or repair.';                     JobTypeHint='' }
    @{ Parent='Hardware'; Name='Keyboard / Mouse';     Sort=30; Desc='Keyboard, mouse, or other input peripheral request.';                   JobTypeHint='' }
    @{ Parent='Hardware'; Name='Printer';              Sort=40; Desc='Printer setup, replacement, or repair. Includes office and home printers.'; JobTypeHint='' }
    @{ Parent='Hardware'; Name='Headset';              Sort=50; Desc='Headset / audio peripheral request or replacement.';                    JobTypeHint='' }
    @{ Parent='Hardware'; Name='Mobile Device';        Sort=60; Desc='Corporate phone, tablet, or other mobile hardware.';                    JobTypeHint='' }
    @{ Parent='Hardware'; Name='Docking Station';      Sort=70; Desc='USB-C or proprietary docking station request.';                         JobTypeHint='' }
    @{ Parent='Hardware'; Name='Hardware Repair';      Sort=80; Desc='Existing hardware needs repair. Triage may dispatch to vendor.';        JobTypeHint='' }
    @{ Parent='Hardware'; Name='Hardware Return';      Sort=90; Desc='Return of corporate hardware (offboarding, upgrade trade-in).';         JobTypeHint='' }

    # ===== Software (legacy, sort=3) =====
    @{ Parent='Software'; Name='Software Install';     Sort=10; Desc='Install a new application on user device.';                              JobTypeHint='' }
    @{ Parent='Software'; Name='License Request';      Sort=20; Desc='Request a software license seat (Adobe, Visio, etc.).';                  JobTypeHint='licensing.assign' }
    @{ Parent='Software'; Name='Software Upgrade';     Sort=30; Desc='Upgrade an installed application to a new version.';                     JobTypeHint='' }
    @{ Parent='Software'; Name='Software Removal';     Sort=40; Desc='Uninstall a no-longer-needed application.';                              JobTypeHint='' }
    @{ Parent='Software'; Name='Software Bug';         Sort=50; Desc='Report a defect in an installed application.';                           JobTypeHint='' }

    # ===== Account & Access (legacy, sort=1) =====
    @{ Parent='Account & Access'; Name='New Account Creation';     Sort=10; Desc='Create a new user account in Entra ID for a new hire.';     JobTypeHint='identity.createUser' }
    @{ Parent='Account & Access'; Name='Password Reset';           Sort=20; Desc='Reset a forgotten or expired password.';                    JobTypeHint='identity.resetPassword' }
    @{ Parent='Account & Access'; Name='Account Unlock';           Sort=30; Desc='Unlock an account locked due to too many failed sign-ins.'; JobTypeHint='' }
    @{ Parent='Account & Access'; Name='Group / Role Membership';  Sort=40; Desc='Add or remove a user from a security group or role.';       JobTypeHint='groups.addMember' }
    @{ Parent='Account & Access'; Name='MFA Reset';                Sort=50; Desc='Clear all registered MFA methods so user can re-enroll.';   JobTypeHint='identity.clearMfa' }
    @{ Parent='Account & Access'; Name='Shared Mailbox / Folder';  Sort=60; Desc='Grant or revoke access to a shared mailbox or folder.';     JobTypeHint='exchange.grantFullAccess' }
    @{ Parent='Account & Access'; Name='VPN Access';               Sort=70; Desc='Provision VPN access for remote work.';                     JobTypeHint='' }
    @{ Parent='Account & Access'; Name='Privileged Access (RBAC)'; Sort=80; Desc='RBAC role change request. Requires manager + IT approval.'; JobTypeHint='' }

    # ===== Network & Connectivity (legacy, sort=5) =====
    @{ Parent='Network & Connectivity'; Name='Wi-Fi Access';         Sort=10; Desc='Corporate Wi-Fi connection issue or new device enrollment.'; JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='Wired Port Activation';Sort=20; Desc='Activate or troubleshoot a wired Ethernet port.';            JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='VPN Setup';            Sort=30; Desc='Initial VPN client setup or troubleshooting.';              JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='Firewall Rule Change'; Sort=40; Desc='Open / close a firewall rule. Requires Change Management.'; JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='DNS Change';           Sort=50; Desc='DNS record add / change / delete. Requires Change Management.'; JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='Static IP';            Sort=60; Desc='Static IP assignment for a device or service.';             JobTypeHint='' }
    @{ Parent='Network & Connectivity'; Name='Proxy Bypass';         Sort=70; Desc='Bypass corporate proxy for a specific URL / service.';      JobTypeHint='' }

    # ===== Email & Messaging (legacy, sort=4) =====
    @{ Parent='Email & Messaging'; Name='New Mailbox';            Sort=10; Desc='Provision a new mailbox (typically auto with new hire account).'; JobTypeHint='' }
    @{ Parent='Email & Messaging'; Name='Distribution List';      Sort=20; Desc='Create / modify / delete distribution list or M365 group.';   JobTypeHint='' }
    @{ Parent='Email & Messaging'; Name='Mailbox Size Increase';  Sort=30; Desc='Increase mailbox quota beyond default.';                       JobTypeHint='' }
    @{ Parent='Email & Messaging'; Name='Calendar Permission';    Sort=40; Desc='Grant calendar viewer / editor permission to another user.';   JobTypeHint='' }
    @{ Parent='Email & Messaging'; Name='Teams / Slack Channel';  Sort=50; Desc='Create or archive a Teams / Slack channel.';                   JobTypeHint='' }
    @{ Parent='Email & Messaging'; Name='Email Rules';            Sort=60; Desc='Server-side mail flow rule (transport rule) request.';         JobTypeHint='' }

    # ===== Security & Compliance (agent, sort=70) =====
    @{ Parent='Security & Compliance'; Name='Phishing Report';            Sort=10; Desc='User reports a suspicious email. Forward to security team.';  JobTypeHint='' }
    @{ Parent='Security & Compliance'; Name='Suspicious Activity';        Sort=20; Desc='Sign-in from unfamiliar location, unexpected MFA prompt, etc.'; JobTypeHint='' }
    @{ Parent='Security & Compliance'; Name='Certificate Request';        Sort=30; Desc='Internal certificate (TLS, S/MIME, code-signing) request.';   JobTypeHint='' }
    @{ Parent='Security & Compliance'; Name='Privileged Access Request';  Sort=40; Desc='Time-bound elevation request for sensitive operations.';      JobTypeHint='' }
    @{ Parent='Security & Compliance'; Name='Security Exception';         Sort=50; Desc='Request a documented exception to a security policy.';        JobTypeHint='' }

    # ===== Telecom & Mobile (Phase 3 new, sort=80) =====
    @{ Parent='Telecom & Mobile'; Name='Cell Phone Provisioning';  Sort=10; Desc='Corporate cell phone setup or replacement.';                  JobTypeHint='' }
    @{ Parent='Telecom & Mobile'; Name='Number Port';              Sort=20; Desc='Port a number from another carrier.';                         JobTypeHint='' }
    @{ Parent='Telecom & Mobile'; Name='International Access';     Sort=30; Desc='Enable international roaming for travel.';                    JobTypeHint='' }
    @{ Parent='Telecom & Mobile'; Name='Plan Change';              Sort=40; Desc='Upgrade / downgrade voice or data plan.';                     JobTypeHint='' }
    @{ Parent='Telecom & Mobile'; Name='Conference Bridge';        Sort=50; Desc='Provision a dedicated conference bridge / dial-in.';          JobTypeHint='' }
    @{ Parent='Telecom & Mobile'; Name='Desk Phone';               Sort=60; Desc='Desk phone setup, replacement, or troubleshooting.';          JobTypeHint='' }

    # ===== Facilities (Phase 3 new, sort=90) =====
    @{ Parent='Facilities'; Name='Desk Move';              Sort=10; Desc='Move user from one desk to another. Includes hardware relocation.'; JobTypeHint='' }
    @{ Parent='Facilities'; Name='Badge / Physical Access'; Sort=20; Desc='Building access card, floor access change, visitor pass.';         JobTypeHint='' }
    @{ Parent='Facilities'; Name='Parking';                Sort=30; Desc='Parking space assignment, visitor parking, EV charging.';           JobTypeHint='' }

    # ===== HR Cross-Over (Phase 3 new, sort=100) =====
    @{ Parent='HR Cross-Over'; Name='Onboarding';              Sort=10; Desc='New hire onboarding orchestration. Triggers Order Guide.';       JobTypeHint='identity.createUser' }
    @{ Parent='HR Cross-Over'; Name='Offboarding';             Sort=20; Desc='Departing employee offboarding. Disable account, revoke access.'; JobTypeHint='identity.disableUser' }
    @{ Parent='HR Cross-Over'; Name='Name Change';             Sort=30; Desc='Legal name change. Update Entra, mailbox, AD CN, badge.';        JobTypeHint='' }
    @{ Parent='HR Cross-Over'; Name='Address Change';          Sort=40; Desc='Home address change. Update HR + Entra + delivery preferences.'; JobTypeHint='' }
    @{ Parent='HR Cross-Over'; Name='Leave of Absence';        Sort=50; Desc='Extended leave start. Disable or restrict account during leave.'; JobTypeHint='identity.disableUser' }
    @{ Parent='HR Cross-Over'; Name='Benefits Enrollment';     Sort=60; Desc='Annual benefits enrollment system access / question.';          JobTypeHint='' }
    @{ Parent='HR Cross-Over'; Name='Tuition Reimbursement';   Sort=70; Desc='Tuition reimbursement portal access or claim issue.';            JobTypeHint='' }

    # ===== Database & Storage (Phase 3 new, sort=110) =====
    @{ Parent='Database & Storage'; Name='Schema Change';         Sort=10; Desc='DBA review of schema modification. Requires Change Management.'; JobTypeHint='' }
    @{ Parent='Database & Storage'; Name='DB Access Grant';       Sort=20; Desc='Grant a user / app SQL or Cosmos DB access.';                    JobTypeHint='' }
    @{ Parent='Database & Storage'; Name='File Share Quota';      Sort=30; Desc='Increase file share or NAS quota.';                              JobTypeHint='' }
    @{ Parent='Database & Storage'; Name='Restore from Backup';   Sort=40; Desc='Restore database, file share, or VM from backup.';               JobTypeHint='' }

    # ===== Reporting & Analytics (Phase 3 new, sort=120) =====
    @{ Parent='Reporting & Analytics'; Name='New Report';            Sort=10; Desc='Build / publish a new operational or analytics report.';     JobTypeHint='' }
    @{ Parent='Reporting & Analytics'; Name='Power BI Access';       Sort=20; Desc='Power BI workspace access, license, or capacity request.';   JobTypeHint='licensing.assign' }
    @{ Parent='Reporting & Analytics'; Name='Dashboard Share';       Sort=30; Desc='Share an existing dashboard with new users / groups.';       JobTypeHint='' }
    @{ Parent='Reporting & Analytics'; Name='Data Extract';          Sort=40; Desc='One-time data extract from a system of record.';             JobTypeHint='' }

    # ===== Mobile & Endpoint (agent, sort=60) =====
    @{ Parent='Mobile & Endpoint'; Name='Phone Enrollment';            Sort=10; Desc='Enroll personal or corporate device into MDM (Intune).';   JobTypeHint='' }
    @{ Parent='Mobile & Endpoint'; Name='MDM Policy';                  Sort=20; Desc='MDM policy assignment, change, or troubleshooting.';      JobTypeHint='' }
    @{ Parent='Mobile & Endpoint'; Name='Endpoint Wipe / Reset';       Sort=30; Desc='Selective wipe or full reset of a corporate device.';     JobTypeHint='' }
    @{ Parent='Mobile & Endpoint'; Name='BYOD Configuration';          Sort=40; Desc='Bring-Your-Own-Device setup with conditional access.';    JobTypeHint='' }

    # ===== Identity & Access Management (agent, sort=10) — engineer-vocab; agent uses these =====
    @{ Parent='Identity & Access Management'; Name='Password Reset';     Sort=10; Desc='Engineer-vocab counterpart of Account & Access > Password Reset.'; JobTypeHint='identity.resetPassword' }
    @{ Parent='Identity & Access Management'; Name='MFA Reset';          Sort=20; Desc='Clear all MFA methods.';                                JobTypeHint='identity.clearMfa' }
    @{ Parent='Identity & Access Management'; Name='Disable User';       Sort=30; Desc='accountEnabled=false. Reversible within 30 days.';      JobTypeHint='identity.disableUser' }
    @{ Parent='Identity & Access Management'; Name='Enable User';        Sort=40; Desc='accountEnabled=true. Re-enable a disabled account.';   JobTypeHint='identity.enableUser' }
    @{ Parent='Identity & Access Management'; Name='Create New User';    Sort=50; Desc='Provision a new Entra ID user account.';                JobTypeHint='identity.createUser' }

    # ===== Groups & Permissions (agent, sort=20) =====
    @{ Parent='Groups & Permissions'; Name='Add to Group';            Sort=10; Desc='Add user to a security or M365 group.';                    JobTypeHint='groups.addMember' }
    @{ Parent='Groups & Permissions'; Name='Remove from Group';       Sort=20; Desc='Remove user from a security or M365 group.';               JobTypeHint='groups.removeMember' }
    @{ Parent='Groups & Permissions'; Name='Role Assignment';         Sort=30; Desc='Directory role assignment (e.g., User Admin, Reports Reader).'; JobTypeHint='' }

    # ===== Licensing (agent, sort=30) =====
    @{ Parent='Licensing'; Name='Assign License';   Sort=10; Desc='Assign an M365 or other license SKU.';                                       JobTypeHint='licensing.assign' }
    @{ Parent='Licensing'; Name='Revoke License';   Sort=20; Desc='Revoke an M365 or other license SKU.';                                       JobTypeHint='licensing.revoke' }
    @{ Parent='Licensing'; Name='License Audit';    Sort=30; Desc='License usage audit / reclamation request.';                                  JobTypeHint='' }

    # ===== SharePoint & Files (agent, sort=40) =====
    @{ Parent='SharePoint & Files'; Name='File Restore';        Sort=10; Desc='Restore a file from SharePoint recycle bin.';                    JobTypeHint='sharepoint.restoreFile' }
    @{ Parent='SharePoint & Files'; Name='Site Permission';     Sort=20; Desc='Grant / revoke permission on a SharePoint site.';                JobTypeHint='' }
    @{ Parent='SharePoint & Files'; Name='Site Provisioning';   Sort=30; Desc='Provision a new SharePoint site, document library, or list.';    JobTypeHint='' }

    # ===== Teams & Collaboration (agent, sort=50) =====
    @{ Parent='Teams & Collaboration'; Name='Channel Creation';     Sort=10; Desc='Create a new Teams channel under an existing team.';         JobTypeHint='' }
    @{ Parent='Teams & Collaboration'; Name='Team Provisioning';    Sort=20; Desc='Provision a new Teams team. Often paired with M365 group.';  JobTypeHint='' }
    @{ Parent='Teams & Collaboration'; Name='Meeting Issue';        Sort=30; Desc='Teams meeting audio, video, or recording troubleshooting.';  JobTypeHint='' }
    @{ Parent='Teams & Collaboration'; Name='Teams App Issue';      Sort=40; Desc='Issue with a Teams app (custom or third-party).';            JobTypeHint='' }
)

# Build a Title-keyed index of category int Ids for the Lookup field
Write-Host "`n=== Resolving Categories list IDs ===" -ForegroundColor Cyan
$catIdMap = @{}
$cats = Get-PnPListItem -List 'Categories'
foreach ($c in $cats) {
    $catIdMap[$c.FieldValues['Title']] = $c.Id
}
Write-Host "  Indexed $($catIdMap.Count) parent categories." -ForegroundColor DarkGray

Write-Host "`n=== Seeding Subcategories ($($subcategories.Count) total) ===" -ForegroundColor Cyan
$created = 0; $skipped = 0; $missingParent = 0
foreach ($s in $subcategories) {
    if (-not $catIdMap.ContainsKey($s.Parent)) {
        Write-StateLine -State 'SKIPPED' -Object "Subcategory.$($s.Parent)/$($s.Name)" -Detail "(parent category not found — run seed-categories.ps1 first)"
        $missingParent++
        continue
    }
    $parentId = $catIdMap[$s.Parent]

    # Existence check: same Title + same ParentCategory.Id
    $existing = Get-PnPListItem -List 'Subcategories' -Query @"
<View><Query><Where><And>
<Eq><FieldRef Name='Title'/><Value Type='Text'>$($s.Name)</Value></Eq>
<Eq><FieldRef Name='ParentCategory' LookupId='TRUE'/><Value Type='Integer'>$parentId</Value></Eq>
</And></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($existing) {
        Write-StateLine -State 'NO-CHANGE' -Object "Subcategory.$($s.Parent)/$($s.Name)" -Detail "(exists)"
        $skipped++
    } else {
        Add-PnPListItem -List 'Subcategories' -Values @{
            Title             = $s.Name
            ParentCategory    = $parentId
            Description       = $s.Desc
            SubcategoryStatus = 'active'
            SortOrder         = $s.Sort
            JobTypeHint       = $s.JobTypeHint
        } | Out-Null
        Write-StateLine -State CREATED -Object "Subcategory.$($s.Parent)/$($s.Name)" -Detail $(if ($s.JobTypeHint) { "→ $($s.JobTypeHint)" } else { '' })
        $created++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Created:        $created" -ForegroundColor Green
Write-Host "  Already exists: $skipped"  -ForegroundColor DarkGray
Write-Host "  Missing parent: $missingParent" -ForegroundColor $(if ($missingParent -gt 0) { 'Yellow' } else { 'DarkGray' })
Write-Host "  Total defined:  $($subcategories.Count)" -ForegroundColor White

Disconnect-PnPOnline
Write-Host "`nSubcategories seeded." -ForegroundColor Green
