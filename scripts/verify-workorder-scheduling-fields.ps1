#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$GraphResource = 'https://graph.microsoft.com',
    [string]$SharePointHost = 'contoso.sharepoint.com',
    [string]$SitePath = '/sites/MCPDemo',
    [string]$WorkbookItemId = '01UZVN4FZ65IXJJCW2MRGKG66H4SZVN2DY',
    [string]$TableName = 'WorkOrder_WorkOrders',
    [string]$EvidencePath = 'prompts/workorder_scheduling_fields_verify_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $GraphResource --query accessToken -o tsv
if (-not $token) {
    throw 'Unable to acquire Graph token.'
}

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
    'Content-Type' = 'application/json'
}

$site = Invoke-RestMethod -Method Get -Uri "$GraphResource/v1.0/sites/$SharePointHost`:$SitePath" -Headers $headers
$base = "$GraphResource/v1.0/sites/$($site.id)/drive/items/$WorkbookItemId/workbook/tables/$TableName"
$columns = (Invoke-RestMethod -Method Get -Uri "$base/columns" -Headers $headers).value
$rows = (Invoke-RestMethod -Method Get -Uri "$base/rows" -Headers $headers).value

$headersRow = @($columns.name)
$recentRows = @($rows | Select-Object -Last 5 | ForEach-Object {
    $values = @($_.values[0])
    $obj = [ordered]@{}
    for ($i = 0; $i -lt $headersRow.Count; $i++) {
        $obj[$headersRow[$i]] = if ($i -lt $values.Count) { $values[$i] } else { $null }
    }
    [pscustomobject]$obj
})

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    SiteId = $site.id
    WorkbookItemId = $WorkbookItemId
    TableName = $TableName
    ColumnCount = $headersRow.Count
    RowCount = @($rows).Count
    HasJobDate = ($headersRow -contains 'JobDate')
    HasJobStartTime = ($headersRow -contains 'JobStartTime')
    HasJobDuration = ($headersRow -contains 'JobDuration')
    RecentRows = $recentRows
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 30
