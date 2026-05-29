#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$LogicalName = 'cre79_agent.shared_sharepointonline.f1550c57e913479793d6de83b61fa1b0',
    [string]$DisplayName = 'cre79_agent.shared_sharepointonline.f1550c57e913479793d6de83b61fa1b0',
    [string]$ConnectionId = 'f1550c57e913479793d6de83b61fa1b0',
    [string]$ConnectorId = '/providers/Microsoft.PowerApps/apis/shared_sharepointonline',
    [string]$OutputPath = 'prompts/task22_triage_sharepoint_connection_reference_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
    'If-Match' = '*'
}
$postHeaders = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$filter = [System.Uri]::EscapeDataString("connectionreferencelogicalname eq '$LogicalName'")
$select = 'connectionreferenceid,connectionreferencedisplayname,connectionreferencelogicalname,connectorid,connectionid,statecode,statuscode,createdon,modifiedon'
$url = "$OrgUrl/api/data/v9.2/connectionreferences?`$select=$select&`$filter=$filter"
$existing = @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]

$payload = @{
    connectionreferencedisplayname = $DisplayName
    connectionreferencelogicalname = $LogicalName
    connectorid = $ConnectorId
    connectionid = $ConnectionId
}

if ($existing) {
    Invoke-RestMethod -Method Patch -Uri "$OrgUrl/api/data/v9.2/connectionreferences($($existing.connectionreferenceid))" -Headers $headers -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 10) | Out-Null
    $action = 'PATCH'
}
else {
    Invoke-RestMethod -Method Post -Uri "$OrgUrl/api/data/v9.2/connectionreferences" -Headers $postHeaders -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 10) | Out-Null
    $action = 'POST'
}

$updated = @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]
$result = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    Action = $action
    ConnectionReference = $updated
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 20
