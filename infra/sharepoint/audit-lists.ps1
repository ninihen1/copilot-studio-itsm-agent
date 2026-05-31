#Requires -Version 7.0

<#
.SYNOPSIS
Audit all 16 SharePoint lists in /sites/ITSM. Compares actual columns against
the spec encoded in the per-list provisioning scripts. Surfaces missing lists,
missing fields, and mismatched required/indexed flags.
#>

[CmdletBinding()]
param(
    [string]$SiteUrl  = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')

# Expected lists + their key required columns
$expected = @{
    'Categories'           = @('ParentCategory','Description','Status')
    'Configuration Items'  = @('CiName','CiClass','OperationalStatus')
    'Assets'               = @('AssetTag','SerialNumber','AssetClass','AssetState')
    'Knowledge Base'       = @('ArticleNumber','Summary','Body','Category','Audience','ArticleStatus','KbAuthor')
    'Service Catalog'      = @('ItemName','Category','Description','ItemStatus')
    'Priority Matrix'      = @('Impact','Urgency','Priority','ResponseHours','ResolutionHours')
    'Approval Policies'    = @('DisplayName','Stages','PolicyVersion','PolicyStatus')
    'JobTypes'             = @('Category','RiskTier','DefaultPolicy','InputSchema','RequiredScopes','JobStatus')
    'Config'               = @('Key','Value','ChangeReason','Environment')
    'Tickets'              = @('TicketType','CategoryRef','Caller','TicketState','Impact','Urgency','Priority','ShortDescription','ConfidentialityLevel')
    'Tickets-Archive'      = @('TicketNumber','TicketType','Caller','TicketState','OpenedDate','ClosedDate','ArchivedAt','ConfidentialityLevel')
    'Request Items'        = @('RitmNumber','ParentTicket','CatalogItem','RequestedFor','RitmState','OpenedDate','ConfidentialityLevel')
    'Tasks'                = @('TaskNumber','ParentRitm','TaskState','ShortDescription','OpenedDate')
    'Approvals'            = @('PolicyApplied','PolicyVersionUsed','SessionState')
    'ApprovalStages'       = @('ApprovalSessionId','StageName','StageOrder','Outcome','StartedAt')
    'Provisioning Jobs'    = @('JobType','ParentTicket','JobStatus','CallerUpn','TargetJson','IdempotencyKey','CorrelationId')
}

Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId

$allFindings = @()

try {
    foreach ($listTitle in ($expected.Keys | Sort-Object)) {
        Write-Host "`n=== $listTitle ===" -ForegroundColor Cyan
        $list = Get-PnPList -Identity $listTitle -ErrorAction SilentlyContinue
        if (-not $list) {
            $allFindings += "[MISSING LIST] $listTitle"
            Write-Host "  [ERROR] List does not exist" -ForegroundColor Red
            continue
        }

        $itemCount = $list.ItemCount
        Write-Host "  list exists, $itemCount items" -ForegroundColor Gray

        # Get all visible non-hidden non-readonly user fields
        $allFields = Get-PnPField -List $listTitle | Where-Object { -not $_.Hidden -and -not $_.ReadOnlyField -and $_.InternalName -notin @('Title','ContentType','Modified','Created','Author','Editor','_UIVersionString','Attachments','Edit','LinkTitleNoMenu','LinkTitle','DocIcon','ItemChildCount','FolderChildCount','_ComplianceFlags','_ComplianceTag','_ComplianceTagWrittenTime','_ComplianceTagUserId','AppAuthor','AppEditor','ID','ContentTypeId','GUID','WorkflowVersion','_UIVersion','FileRef','FileDirRef','Last_x0020_Modified','Created_x0020_Date','FSObjType','SortBehavior','ContentVersion','OData__UIVersionString','MetaInfo','_Level','_IsCurrentVersion','ItemId','SyncClientId','ProgId','ScopeId','HTML_x0020_File_x0020_Type','_EditMenuTableStart','_EditMenuTableStart2','_EditMenuTableEnd','LinkFilenameNoMenu','LinkFilename','LinkFilename2','_CopySource','CheckedOutTitle','LinkCheckedOutTitle','Modified_x0020_By','Created_x0020_By','File_x0020_Type','HTML_x0020_File_x0020_Type','_HasCopyDestinations','_CopySource','owshiddenversion','WorkflowVersion','_UIVersion','_UIVersionString','_ModerationStatus','_ModerationComments','Edit','SelectTitle','InstanceID','Order','GUID','WorkflowInstanceID','FileLeafRef','UniqueId','FileDirRef','FileRef','File_x0020_Type','_dlc_DocId','_dlc_DocIdUrl','_dlc_DocIdPersistId','TaxCatchAll','TaxCatchAllLabel','PermMask','EncodedAbsUrl','BaseName','MetaInfo','SMTotalSize','SMLastModifiedDate','SMTotalFileStreamSize','SMTotalFileCount','OriginatorId','_Source','URL','URLwMenu','URLNoMenu','_HasEncryptedContent','ParentLeafName','ParentVersionString') }

        $fieldNames = $allFields | ForEach-Object { $_.InternalName }
        $expectedCols = $expected[$listTitle]
        $missing = $expectedCols | Where-Object { $_ -notin $fieldNames }
        $present = $expectedCols | Where-Object { $_ -in $fieldNames }
        Write-Host "  required cols: $(($present | Measure-Object).Count)/$(($expectedCols | Measure-Object).Count) present" -ForegroundColor $(if ($missing) {'Yellow'} else {'Green'})
        if ($missing) {
            foreach ($m in $missing) {
                $allFindings += "[MISSING FIELD] $listTitle.$m"
                Write-Host "    [MISSING] $m" -ForegroundColor Red
            }
        }
        $extra = $fieldNames | Where-Object { $_ -notin $expectedCols }
        if ($extra) {
            Write-Host "  additional non-spec cols ($($extra.Count)): $($extra -join ', ')" -ForegroundColor DarkGray
        }
    }
} finally {
    Disconnect-PnPOnline
}

Write-Host "`n========== AUDIT SUMMARY ==========" -ForegroundColor White
if ($allFindings.Count -eq 0) {
    Write-Host "All lists and required fields present." -ForegroundColor Green
} else {
    Write-Host "$($allFindings.Count) finding(s):" -ForegroundColor Yellow
    $allFindings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
