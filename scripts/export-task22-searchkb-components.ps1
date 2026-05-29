#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$LocalActionPath = 'agents/triage/Helpdesk Triage Agent/actions/SearchKnowledgeBase.action.mcs.yml',
    [string]$OutputPath = 'prompts/task22_searchkb_matching_botcomponents_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) {
    throw "Unable to acquire Dataverse token for $OrgUrl."
}

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

function Get-FlowIds {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    return @([regex]::Matches($Text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value } | Select-Object -Unique)
}

function Get-ComponentDataFromFile {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    return ($text -split "`r?`n", 4)[3]
}

$select = 'botcomponentid,name,schemaname,componenttype,componentstate,statecode,statuscode,modifiedon,description,data,content'
$filter = [System.Uri]::EscapeDataString("_parentbotid_value eq $BotId")
$url = "$OrgUrl/api/data/v9.2/botcomponents?`$select=$select&`$filter=$filter"
$components = (Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value

$patterns = @(
    'SearchKnowledgeBase',
    'Search knowledge',
    'Search Knowledge',
    '00000000-0000-4000-8000-000000000053',
    'ITSM-SearchKnowledgeBase',
    'InvokeFlowTaskAction'
)

$matches = foreach ($component in $components) {
    $text = @($component.name, $component.schemaname, $component.description, $component.data, $component.content) -join "`n"
    $matchedPatterns = @($patterns | Where-Object { $text -like "*$_*" })
    if ($matchedPatterns.Count -gt 0) {
        [pscustomobject]@{
            BotComponentId = $component.botcomponentid
            Name = $component.name
            SchemaName = $component.schemaname
            ComponentType = $component.componenttype
            ComponentState = $component.componentstate
            StateCode = $component.statecode
            StatusCode = $component.statuscode
            ModifiedOn = $component.modifiedon
            Description = $component.description
            MatchedPatterns = $matchedPatterns
            FlowIds = Get-FlowIds -Text $text
            HasInvokeFlowTaskAction = ($text -match 'InvokeFlowTaskAction')
            HasInvokeFlowAction = ($text -match 'InvokeFlowAction')
            HasSearchKnowledgeBase = ($text -match 'SearchKnowledgeBase')
            HasF1B47FlowId = ($text -match '00000000-0000-4000-8000-000000000053')
            Data = $component.data
            Content = $component.content
        }
    }
}

$localFullText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $LocalActionPath))
$localData = Get-ComponentDataFromFile -Path $LocalActionPath

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    BotId = $BotId
    LocalAction = [pscustomobject]@{
        Path = $LocalActionPath
        FlowIds = Get-FlowIds -Text $localFullText
        Data = $localData
    }
    MatchingComponents = @($matches)
    Summary = [pscustomobject]@{
        MatchingComponentCount = @($matches).Count
        InvokeFlowTaskActionComponents = @($matches | Where-Object { $_.HasInvokeFlowTaskAction }).Count
        ComponentsWithF1B47FlowId = @($matches | Where-Object { $_.HasF1B47FlowId }).Count
        ComponentNames = @($matches | ForEach-Object { "$($_.Name) [$($_.SchemaName)]" })
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

$evidence.Summary | ConvertTo-Json -Depth 10
$evidence.MatchingComponents |
    Select-Object Name,SchemaName,ComponentType,ModifiedOn,HasInvokeFlowTaskAction,HasF1B47FlowId,@{n='FlowIds';e={$_.FlowIds -join ','}},@{n='MatchedPatterns';e={$_.MatchedPatterns -join ','}} |
    ConvertTo-Json -Depth 10
