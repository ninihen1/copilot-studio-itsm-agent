#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$EvidencePath = 'prompts/day4_task22_kb_source_pinning_live_verification_20260508.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

function Invoke-DvGet {
    param([Parameter(Mandatory)][string]$Url)
    Invoke-RestMethod -Method Get -Uri $Url -Headers $headers
}

function Get-BotComponentBySchemaName {
    param([Parameter(Mandatory)][string]$SchemaName)
    $filter = [System.Uri]::EscapeDataString("schemaname eq '$SchemaName' and _parentbotid_value eq $BotId")
    $select = 'botcomponentid,name,schemaname,modifiedon,data,description'
    $result = Invoke-DvGet -Url "$OrgUrl/api/data/v9.2/botcomponents?`$select=$select&`$filter=$filter"
    return @($result.value)[0]
}

$schemaNames = @(
    'cre79_agent.topic.SearchKnowledge',
    'cre79_agent.topic.CreateTicket',
    'cre79_agent.knowledge.KnowledgeBase'
)

$components = foreach ($schemaName in $schemaNames) {
    $component = Get-BotComponentBySchemaName -SchemaName $schemaName
    $text = [string]$component.data
    $compact = $text -replace '\s+', ' '
    [pscustomobject]@{
        SchemaName = $component.schemaname
        Name = $component.name
        BotComponentId = $component.botcomponentid
        ModifiedOn = $component.modifiedon
        HasKbListUrl = ($text -like '*https://contoso.sharepoint.com/sites/ITSM/Lists/Knowledge%20Base*')
        HasApplyModelKnowledgeFalse = ($text -like '*applyModelKnowledgeSetting: false*')
        HasDoNotSearchFiles = ($text -like '*DoNotSearchFiles*')
        HasSearchSpecificKnowledgeSources = ($text -like '*SearchSpecificKnowledgeSources*')
        KnowledgeBaseRefs = ([regex]::Matches($text, 'cre79_agent\.knowledge\.KnowledgeBase').Count)
        SearchOnlyInstruction = ($text -like '*Search ONLY the Knowledge Base*')
        Preview = $compact.Substring(0, [Math]::Min(500, $compact.Length))
    }
}

$botSelect = 'botid,name,schemaname,publishedon,synchronizationstatus,modifiedon'
$bot = Invoke-DvGet -Url "$OrgUrl/api/data/v9.2/bots($BotId)?`$select=$botSelect"

$topicFailures = @($components | Where-Object {
    $_.SchemaName -like '*.topic.*' -and (
        -not $_.HasKbListUrl -or
        -not $_.HasApplyModelKnowledgeFalse -or
        -not $_.HasDoNotSearchFiles -or
        -not $_.HasSearchSpecificKnowledgeSources -or
        $_.KnowledgeBaseRefs -lt 1
    )
})

$knowledgeFailures = @($components | Where-Object {
    $_.SchemaName -eq 'cre79_agent.knowledge.KnowledgeBase' -and -not $_.HasKbListUrl
})

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    BotId = $BotId
    Bot = $bot
    Components = @($components)
    Verdict = if ($topicFailures.Count -eq 0 -and $knowledgeFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
