#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$OutputPath = 'prompts/task22_agent_connection_references_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$select = 'connectionreferenceid,connectionreferencedisplayname,connectionreferencelogicalname,connectorid,connectionid,statecode,statuscode,createdon,modifiedon'
$url = "$OrgUrl/api/data/v9.2/connectionreferences?`$select=$select"
$refs = (Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value |
    Where-Object { $_.connectionreferencelogicalname -like 'cre79_agent.*' -or $_.connectorid -like '*sharepointonline*' } |
    Sort-Object connectionreferencelogicalname

$result = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    ConnectionReferences = @($refs)
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 20
