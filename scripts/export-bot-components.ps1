#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$OutputPath = 'prompts/live_bot_components.json'
)

$ErrorActionPreference = 'Stop'
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$select = 'botcomponentid,name,schemaname,componenttype,content,data,description,statecode,statuscode'
$filter = "_parentbotid_value eq $BotId"
$url = "$OrgUrl/api/data/v9.2/botcomponents?`$select=$select&`$filter=$filter"
$rows = (Invoke-RestMethod -Uri $url -Headers $headers).value

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$rows | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$rows | Select-Object botcomponentid,name,schemaname,componenttype,statecode,statuscode | ConvertTo-Json -Depth 5
