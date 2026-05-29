#Requires -Version 7.0

<#
.SYNOPSIS
Phase 3 deliverable 2 — seeds the Service Catalog list with 8 catalog items spanning
single-task and multi-task (Order Guide) patterns. Each item maps to existing JobType(s)
in the JobTypes registry and an approval policy.

Idempotent — re-runs are no-ops if the same Title (item code) already exists.

Source: servicenow-itsm-ticketing-report.md §2.4 (Service Request fulfillment) and §4.2 (variables).

Coverage:
  - 6 single-task items (Password Reset, License Request, Add to Group, etc.)
  - 2 multi-task Order Guides (Onboarding, Offboarding)

The multi-task pattern uses TaskTemplates JSON. The RITM Generator flow reads it and creates
one SCTASK per array entry, ordered by sortOrder.
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

# Resolve foreign keys (Categories, Subcategories, Approval Policies) up-front
Write-Host "`n=== Resolving foreign keys ===" -ForegroundColor Cyan
$catIdMap = @{}
foreach ($c in (Get-PnPListItem -List 'Categories')) { $catIdMap[$c.FieldValues['Title']] = $c.Id }
$subIdMap = @{}
foreach ($s in (Get-PnPListItem -List 'Subcategories')) { $subIdMap["$($s.FieldValues['ParentCategory'].LookupValue)/$($s.FieldValues['Title'])"] = $s.Id }
$polIdMap = @{}
foreach ($p in (Get-PnPListItem -List 'Approval Policies')) { $polIdMap[$p.FieldValues['Title']] = $p.Id }

$items = @(
    @{
        Title='CAT-PWD-RESET'; ItemName='Password Reset'
        Category='Account & Access'; Subcategory='Password Reset'
        Description='Reset your forgotten or expired password. Receive a temporary password by SMS that you must change on next sign-in.'
        JobType='identity.resetPassword'; ApprovalPolicy='AP-PWD-RESET-V1'
        Cost=0; SlaDays=1; Visibility='All Employees'; Keywords='password,reset,forgot,locked,unlock'
        InputSchema='{"type":"object","properties":{"reason":{"type":"string","enum":["forgotten","expired","compromised","other"]}},"required":["reason"]}'
        TaskTemplates=$null  # single-task → uses JobType directly
    },
    @{
        Title='CAT-LIC-REQUEST'; ItemName='License Request'
        Category='Licensing'; Subcategory='Assign License'
        Description='Request an M365 or third-party software license. Manager approval required.'
        JobType='licensing.assign'; ApprovalPolicy='AP-LOW-RISK-V1'
        Cost=15; SlaDays=1; Visibility='All Employees'; Keywords='license,m365,e3,e5,visio,project,power bi'
        InputSchema='{"type":"object","properties":{"skuId":{"type":"string","description":"SKU GUID"},"skuPartNumber":{"type":"string","description":"e.g., POWER_BI_PRO"},"businessJustification":{"type":"string"}},"required":["skuId","businessJustification"]}'
        TaskTemplates=$null
    },
    @{
        Title='CAT-GROUP-ADD'; ItemName='Add to Group'
        Category='Groups & Permissions'; Subcategory='Add to Group'
        Description='Request membership to a security group, M365 group, or distribution list.'
        JobType='groups.addMember'; ApprovalPolicy='AP-LOW-RISK-V1'
        Cost=0; SlaDays=1; Visibility='All Employees'; Keywords='group,membership,access,security group,distribution list'
        InputSchema='{"type":"object","properties":{"groupId":{"type":"string"},"groupName":{"type":"string"},"justification":{"type":"string"}},"required":["groupId","justification"]}'
        TaskTemplates=$null
    },
    @{
        Title='CAT-MBX-ACCESS'; ItemName='Shared Mailbox Access'
        Category='Email & Messaging'; Subcategory='Calendar Permission'
        Description='Request Full Access to a shared mailbox. Time-bounded access available.'
        JobType='exchange.grantFullAccess'; ApprovalPolicy='AP-MED-RISK-V1'
        Cost=0; SlaDays=2; Visibility='All Employees'; Keywords='mailbox,shared,full access,delegate'
        InputSchema='{"type":"object","properties":{"mailboxUpn":{"type":"string","format":"email"},"durationDays":{"type":"integer","default":30},"justification":{"type":"string"}},"required":["mailboxUpn","justification"]}'
        TaskTemplates=$null
    },
    @{
        Title='CAT-SP-RESTORE'; ItemName='Restore SharePoint File'
        Category='SharePoint & Files'; Subcategory='File Restore'
        Description='Restore a deleted file from SharePoint recycle bin. Site collection scope.'
        JobType='sharepoint.restoreFile'; ApprovalPolicy='AP-LOW-RISK-V1'
        Cost=0; SlaDays=1; Visibility='All Employees'; Keywords='sharepoint,onedrive,restore,recycle bin,deleted'
        InputSchema='{"type":"object","properties":{"siteUrl":{"type":"string"},"itemId":{"type":"string"},"reason":{"type":"string"}},"required":["siteUrl","itemId"]}'
        TaskTemplates=$null
    },
    @{
        Title='CAT-SOFT-INSTALL'; ItemName='Software Install Request'
        Category='Software'; Subcategory='Software Install'
        Description='Request installation of an application on your corporate device. May require license purchase.'
        JobType=''; ApprovalPolicy='AP-LOW-RISK-V1'  # human-fulfilled
        Cost=0; SlaDays=3; Visibility='All Employees'; Keywords='install,software,application,app'
        InputSchema='{"type":"object","properties":{"softwareName":{"type":"string"},"version":{"type":"string"},"businessJustification":{"type":"string"}},"required":["softwareName","businessJustification"]}'
        TaskTemplates=$null  # single-task; manual fulfillment by IT
    },
    @{
        Title='CAT-ONBOARD'; ItemName='New Hire Onboarding'
        Category='HR Cross-Over'; Subcategory='Onboarding'
        Description='Order Guide: orchestrates new user account creation, default group assignment, license, and device procurement for a new hire.'
        JobType=''; ApprovalPolicy='AP-USER-CREATE-V1'  # multi-task — JobType empty; uses TaskTemplates
        Cost=200; SlaDays=5; Visibility='Managers Only'; Keywords='onboarding,new hire,start,welcome'
        InputSchema='{"type":"object","properties":{"displayName":{"type":"string"},"upn":{"type":"string","format":"email"},"jobTitle":{"type":"string"},"department":{"type":"string"},"managerUpn":{"type":"string","format":"email"},"officeLocation":{"type":"string"},"startDate":{"type":"string","format":"date"},"defaultGroups":{"type":"array","items":{"type":"string"}},"licenseSkuId":{"type":"string"},"deviceModel":{"type":"string","enum":["Standard 14","Engineering 16","MacBook Pro 14"]}},"required":["displayName","upn","jobTitle","department","managerUpn","startDate"]}'
        TaskTemplates = @"
[
  { "sortOrder": 10, "jobType": "identity.createUser",   "shortDescription": "Create Entra ID user account",         "assignmentGroup": "" },
  { "sortOrder": 20, "jobType": "groups.addMember",      "shortDescription": "Add to default groups (per dept)",     "assignmentGroup": "" },
  { "sortOrder": 30, "jobType": "licensing.assign",      "shortDescription": "Assign baseline license SKU",          "assignmentGroup": "" },
  { "sortOrder": 40, "jobType": "",                      "shortDescription": "Procure laptop and ship",              "assignmentGroup": "IT-Hardware" },
  { "sortOrder": 50, "jobType": "",                      "shortDescription": "Welcome email + first-day checklist",  "assignmentGroup": "IT-Service-Desk" }
]
"@
    },
    @{
        Title='CAT-OFFBOARD'; ItemName='User Offboarding'
        Category='HR Cross-Over'; Subcategory='Offboarding'
        Description='Order Guide: orchestrates user account disable, license revocation, group removal, and mailbox handover for a departing employee.'
        JobType=''; ApprovalPolicy='AP-USER-DISABLE-V1'
        Cost=0; SlaDays=1; Visibility='Managers Only'; Keywords='offboarding,leaving,departure,exit,terminate'
        InputSchema='{"type":"object","properties":{"upn":{"type":"string","format":"email"},"reason":{"type":"string","enum":["resignation","termination","leave","retirement"]},"lastDay":{"type":"string","format":"date"},"transferOneDriveTo":{"type":"string","format":"email"},"forwardEmailTo":{"type":"string","format":"email"}},"required":["upn","reason","lastDay"]}'
        TaskTemplates = @"
[
  { "sortOrder": 10, "jobType": "identity.disableUser",  "shortDescription": "Disable Entra ID user account",         "assignmentGroup": "" },
  { "sortOrder": 20, "jobType": "licensing.revoke",      "shortDescription": "Revoke all assigned license SKUs",      "assignmentGroup": "" },
  { "sortOrder": 30, "jobType": "groups.removeMember",   "shortDescription": "Remove from all groups",                "assignmentGroup": "" },
  { "sortOrder": 40, "jobType": "",                      "shortDescription": "Backup mailbox + transfer OneDrive",    "assignmentGroup": "IT-Service-Desk" },
  { "sortOrder": 50, "jobType": "",                      "shortDescription": "Collect device and decommission",       "assignmentGroup": "IT-Hardware" }
]
"@
    }
)

Write-Host "`n=== Seeding Service Catalog ($($items.Count) items) ===" -ForegroundColor Cyan
$created = 0; $skipped = 0; $failed = 0
foreach ($it in $items) {
    $existing = Get-PnPListItem -List 'Service Catalog' -Query @"
<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($it.Title)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($existing) {
        Write-StateLine -State 'NO-CHANGE' -Object "Catalog.$($it.Title)" -Detail "(exists)"
        $skipped++
        continue
    }

    if (-not $catIdMap.ContainsKey($it.Category)) {
        Write-StateLine -State FAIL -Object "Catalog.$($it.Title)" -Detail "Category '$($it.Category)' not found"
        $failed++
        continue
    }
    $subKey = "$($it.Category)/$($it.Subcategory)"
    $subId = $null
    if ($subIdMap.ContainsKey($subKey)) { $subId = $subIdMap[$subKey] }
    $polId = $null
    if ($it.ApprovalPolicy -and $polIdMap.ContainsKey($it.ApprovalPolicy)) { $polId = $polIdMap[$it.ApprovalPolicy] }

    $values = @{
        Title          = $it.Title
        ItemName       = $it.ItemName
        Category       = $catIdMap[$it.Category]
        Description    = $it.Description
        ItemStatus     = 'active'
        JobType        = $it.JobType
        Cost           = $it.Cost
        SlaDays        = $it.SlaDays
        InputSchema    = $it.InputSchema
        Visibility     = $it.Visibility
        Keywords       = $it.Keywords
    }
    if ($polId)              { $values['ApprovalPolicy']  = $polId }
    if ($subId)              { $values['SubcategoryHint'] = $subId }
    if ($it.TaskTemplates)   { $values['TaskTemplates']   = $it.TaskTemplates }

    Add-PnPListItem -List 'Service Catalog' -Values $values | Out-Null
    $taskCount = if ($it.TaskTemplates) { ($it.TaskTemplates | ConvertFrom-Json).Count } else { 1 }
    Write-StateLine -State CREATED -Object "Catalog.$($it.Title)" -Detail "$($it.Category) | $taskCount task(s) | $($it.SlaDays)d SLA"
    $created++
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Created:   $created"  -ForegroundColor Green
Write-Host "  Existing:  $skipped"  -ForegroundColor DarkGray
Write-Host "  Failed:    $failed"   -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'DarkGray' })

Disconnect-PnPOnline
Write-Host "`nService Catalog seeded." -ForegroundColor Green
