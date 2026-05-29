#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$TopicPath = 'agents/triage/Helpdesk Triage Agent/topics/SearchKnowledge.mcs.yml',
    [string]$ActionPath = 'agents/triage/Helpdesk Triage Agent/actions/SearchKnowledgeBase.action.mcs.yml',
    [string]$FlowWorkflowId = '00000000-0000-4000-8000-000000000053',
    [string]$EvidencePath = 'prompts/task22_searchknowledge_flow_wiring_component_push_20260509.json'
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

$postHeaders = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

function Get-ComponentData {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    return ($text -split "`r?`n", 4)[3]
}

function Upsert-Component {
    param(
        [Parameter(Mandatory)][string]$SchemaName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Data,
        [Parameter(Mandatory)][string]$Description
    )

    $filter = [System.Uri]::EscapeDataString("schemaname eq '$SchemaName' and _parentbotid_value eq $BotId")
    $url = "$OrgUrl/api/data/v9.2/botcomponents?`$select=botcomponentid,name,schemaname,modifiedon,data&`$filter=$filter"
    $existing = @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]
    $payload = @{
        name = $Name
        schemaname = $SchemaName
        componenttype = 9
        data = $Data
        description = $Description
        language = 1033
    }

    if ($existing) {
        Invoke-RestMethod `
            -Method Patch `
            -Uri "$OrgUrl/api/data/v9.2/botcomponents($($existing.botcomponentid))" `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body ($payload | ConvertTo-Json -Depth 30) |
            Out-Null
    }
    else {
        $payload['parentbotid@odata.bind'] = "/bots($BotId)"
        Invoke-RestMethod `
            -Method Post `
            -Uri "$OrgUrl/api/data/v9.2/botcomponents" `
            -Headers $postHeaders `
            -ContentType 'application/json' `
            -Body ($payload | ConvertTo-Json -Depth 30) |
            Out-Null
    }

    return @((Invoke-RestMethod -Method Get -Uri $url -Headers $headers).value)[0]
}

$updatedAction = Upsert-Component `
    -SchemaName 'cre79_agent.action.SearchKnowledgeBase' `
    -Name 'SearchKnowledgeBase' `
    -Data (Get-ComponentData -Path $ActionPath) `
    -Description 'Deterministic ITSM-SearchKnowledgeBase Power Automate tool.'

$updatedTopic = Upsert-Component `
    -SchemaName 'cre79_agent.topic.SearchKnowledge' `
    -Name 'Search Knowledge' `
    -Data (Get-ComponentData -Path $TopicPath) `
    -Description 'User-facing KB lookup topic wired to deterministic ITSM-SearchKnowledgeBase action.'

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    BotId = $BotId
    Components = @(
        [pscustomobject]@{
            SchemaName = $updatedAction.schemaname
            BotComponentId = $updatedAction.botcomponentid
            ModifiedOn = $updatedAction.modifiedon
            ContainsInvokeFlowTaskAction = ($updatedAction.data -like '*InvokeFlowTaskAction*')
            ContainsFlowId = ($updatedAction.data -like "*$FlowWorkflowId*")
        }
        [pscustomobject]@{
            SchemaName = $updatedTopic.schemaname
            BotComponentId = $updatedTopic.botcomponentid
            ModifiedOn = $updatedTopic.modifiedon
            ContainsBeginDialog = ($updatedTopic.data -like '*BeginDialog*')
            ContainsActionDialog = ($updatedTopic.data -like '*cre79_agent.action.SearchKnowledgeBase*')
            ContainsInlineInvokeFlowAction = ($updatedTopic.data -like '*InvokeFlowAction*')
            ContainsSearchAndSummarizeContent = ($updatedTopic.data -like '*SearchAndSummarizeContent*')
        }
    )
    FlowWorkflowId = $FlowWorkflowId
    Verdict = 'PUSHED_ACTION_AND_TOPIC_COMPONENTS'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 10
