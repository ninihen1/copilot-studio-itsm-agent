#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$AgentRoot = 'agents/triage/Helpdesk Triage Agent',
    [string]$EvidencePath = 'prompts/day4_tasks6_22_56_component_push.json'
)

$ErrorActionPreference = 'Stop'

function Get-TextFile {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [object]$Body = $null
    )

    $headers = $script:Headers.Clone()
    if ($Method -ne 'PATCH') {
        $headers.Remove('If-Match')
    }

    $params = @{
        Method = $Method
        Uri = $Url
        Headers = $headers
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }
    Invoke-RestMethod @params
}

function Get-Component {
    param([Parameter(Mandatory)][string]$SchemaName)
    $encoded = [System.Uri]::EscapeDataString("schemaname eq '$SchemaName' and _parentbotid_value eq $BotId")
    $url = "$OrgUrl/api/data/v9.2/botcomponents?`$select=botcomponentid,name,schemaname,data,description&`$filter=$encoded"
    $result = Invoke-Dv -Method GET -Url $url
    return @($result.value)[0]
}

function Upsert-Component {
    param(
        [Parameter(Mandatory)][string]$SchemaName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$ComponentType,
        [Parameter(Mandatory)][string]$Data,
        [string]$Description = ''
    )

    $existing = Get-Component -SchemaName $SchemaName
    $payload = @{
        name = $Name
        schemaname = $SchemaName
        componenttype = $ComponentType
        data = $Data
        description = $Description
        language = 1033
    }

    if ($existing) {
        Invoke-Dv -Method PATCH -Url "$OrgUrl/api/data/v9.2/botcomponents($($existing.botcomponentid))" -Body $payload | Out-Null
        return [pscustomobject]@{ SchemaName = $SchemaName; Action = 'PATCH'; BotComponentId = $existing.botcomponentid }
    }

    $payload['parentbotid@odata.bind'] = "/bots($BotId)"
    Invoke-Dv -Method POST -Url "$OrgUrl/api/data/v9.2/botcomponents" -Body $payload | Out-Null
    $created = Get-Component -SchemaName $SchemaName
    return [pscustomobject]@{ SchemaName = $SchemaName; Action = 'POST'; BotComponentId = $created.botcomponentid }
}

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$script:Headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
    'If-Match' = '*'
}

$updates = @()
$updates += Upsert-Component `
    -SchemaName 'cre79_agent.topic.ProposeWriteAction' `
    -Name 'Propose Write Action' `
    -ComponentType 9 `
    -Data (Get-TextFile -Path (Join-Path $AgentRoot 'topics/ProposeWriteAction.mcs.yml') | ForEach-Object { ($_ -split "`r?`n", 4)[3] }) `
    -Description 'Self-service password reset topic. Calls secured ITSM-ProposeAction through InvokeFlowAction.'

$updates += Upsert-Component `
    -SchemaName 'cre79_agent.topic.SearchKnowledge' `
    -Name 'Search Knowledge' `
    -ComponentType 9 `
    -Data (Get-TextFile -Path (Join-Path $AgentRoot 'topics/SearchKnowledge.mcs.yml') | ForEach-Object { ($_ -split "`r?`n", 4)[3] }) `
    -Description 'User-facing KB lookup topic with topic-level Knowledge Base source pinning for semantic grounding tests.'

$updates += Upsert-Component `
    -SchemaName 'cre79_agent.topic.CreateTicket' `
    -Name 'Create Ticket' `
    -ComponentType 9 `
    -Data (Get-TextFile -Path (Join-Path $AgentRoot 'topics/CreateTicket.mcs.yml') | ForEach-Object { ($_ -split "`r?`n", 4)[3] }) `
    -Description 'Primary intake topic. Classifies, attempts KB deflection, then proposes an action through secured InvokeFlowAction.'

$updates += Upsert-Component `
    -SchemaName 'cre79_agent.knowledge.KnowledgeBase' `
    -Name 'Knowledge Base' `
    -ComponentType 16 `
    -Data (Get-TextFile -Path (Join-Path $AgentRoot 'knowledge/KnowledgeBase.mcs.yml') | ForEach-Object { ($_ -split "`r?`n", 4)[3] }) `
    -Description 'Published KB articles for self-help and deflection. Source of truth for how-to questions.'

$updates += Upsert-Component `
    -SchemaName 'cre79_agent.action.ProposeAction' `
    -Name 'ProposeAction' `
    -ComponentType 9 `
    -Data (Get-TextFile -Path (Join-Path $AgentRoot 'actions/ProposeAction.action.mcs.yml') | ForEach-Object { ($_ -split "`r?`n", 4)[3] }) `
    -Description 'Secured ITSM-ProposeAction Power Automate tool.'

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    BotId = $BotId
    Updates = $updates
    Verdict = 'PUSHED'
    Note = 'Run pac copilot publish after component push to publish these Dataverse component changes.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 10
