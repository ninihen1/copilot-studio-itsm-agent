#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$TopicPath = 'agents/triage/Helpdesk Triage Agent/topics/OnError.mcs.yml',
    [string]$EvidencePath = 'prompts/task22_onerror_diagnostic_component_push_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) {
    throw 'Unable to acquire Dataverse token from Azure CLI.'
}

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
    'If-Match' = '*'
}

function Get-ComponentData {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    return ($text -split "`r?`n", 4)[3]
}

$schemaName = 'cre79_agent.topic.OnError'
$filter = [System.Uri]::EscapeDataString("schemaname eq '$schemaName' and _parentbotid_value eq $BotId")
$url = "$OrgUrl/api/data/v9.2/botcomponents?`$select=botcomponentid,name,schemaname,modifiedon,data&`$filter=$filter"
$existing = @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]
if (-not $existing) {
    throw "Component not found: $schemaName"
}

$data = Get-ComponentData -Path $TopicPath
$payload = @{
    name = 'On Error'
    schemaname = $schemaName
    componenttype = 9
    data = $data
    description = 'Triggered when the agent encounters an error. Temporarily exposes System.Error.Message for Task 22 diagnostics.'
    language = 1033
}

Invoke-RestMethod `
    -Method Patch `
    -Uri "$OrgUrl/api/data/v9.2/botcomponents($($existing.botcomponentid))" `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body ($payload | ConvertTo-Json -Depth 30) |
    Out-Null

$updated = @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    BotId = $BotId
    SchemaName = $updated.schemaname
    BotComponentId = $updated.botcomponentid
    ModifiedOn = $updated.modifiedon
    ContainsDiagnosticExposure = ($updated.data -like '*Diagnostic error exposed temporarily*' -and $updated.data -like '*System.Error.Message*')
    Verdict = 'PUSHED_ONERROR_DIAGNOSTIC_TOPIC'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 10
