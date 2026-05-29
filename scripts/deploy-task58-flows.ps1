param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045'
)

$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\ninih\GitHub\Copilot Studio'

$token = az account get-access-token `
    --resource 'https://service.flow.microsoft.com/' `
    --query accessToken `
    -o tsv

if (-not $token) {
    throw 'Unable to acquire Power Automate access token from Azure CLI.'
}

$headers = @{
    Authorization = "Bearer $token"
    'Content-Type' = 'application/json'
}

$base = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName"
$api = 'api-version=2016-11-01'

function Get-FlowById {
    param([Parameter(Mandatory)][string]$FlowId)
    Invoke-RestMethod -Method Get -Uri "$base/flows/$FlowId`?$api" -Headers $headers
}

function Get-FlowByDisplayName {
    param([Parameter(Mandatory)][string]$DisplayName)
    $flows = (Invoke-RestMethod -Method Get -Uri "$base/flows?$api" -Headers $headers).value
    $flows | Where-Object { $_.properties.displayName -eq $DisplayName } | Select-Object -First 1
}

function Start-FlowIfNeeded {
    param([Parameter(Mandatory)][string]$FlowId)
    try {
        Invoke-RestMethod -Method Post -Uri "$base/flows/$FlowId/start?$api" -Headers $headers -Body '{}' | Out-Null
    } catch {
        Write-Host "Start skipped for ${FlowId}: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Deploy-FlowDefinition {
    param(
        [string]$FlowId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$DefinitionPath,
        [object]$FallbackConnectionReferences
    )

    if (-not (Test-Path -LiteralPath $DefinitionPath)) {
        throw "Definition not found: $DefinitionPath"
    }

    $definition = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json
    $live = $null

    if ($FlowId) {
        $live = Get-FlowById -FlowId $FlowId
    } else {
        $live = Get-FlowByDisplayName -DisplayName $DisplayName
    }

    $connectionReferences = if ($live) {
        $live.properties.connectionReferences
    } elseif ($FallbackConnectionReferences) {
        $FallbackConnectionReferences
    } else {
        throw "No connection references available for new flow $DisplayName."
    }

    $payload = @{
        properties = @{
            displayName = if ($live) { $live.properties.displayName } else { $DisplayName }
            definition = $definition
            connectionReferences = $connectionReferences
        }
    }

    $body = $payload | ConvertTo-Json -Depth 100

    if ($live) {
        $targetId = $live.name
        $updated = Invoke-RestMethod -Method Patch -Uri "$base/flows/$targetId`?$api" -Headers $headers -Body $body
    } else {
        $updated = Invoke-RestMethod -Method Post -Uri "$base/flows?$api" -Headers $headers -Body $body
        $targetId = $updated.name
    }

    Start-FlowIfNeeded -FlowId $targetId

    [pscustomobject]@{
        FlowId = $targetId
        DisplayName = $updated.properties.displayName
        State = $updated.properties.state
        Modified = $updated.properties.lastModifiedTime
        DefinitionPath = $DefinitionPath
    }
}

$ritm = Get-FlowById -FlowId '00000000-0000-4000-8000-000000000004'

$results = @()
$results += Deploy-FlowDefinition `
    -DisplayName 'ITSM-Ticket-Type-Validator' `
    -DefinitionPath 'flows/ticket-type-validator/definition.json' `
    -FallbackConnectionReferences $ritm.properties.connectionReferences

$results += Deploy-FlowDefinition `
    -FlowId '00000000-0000-4000-8000-000000000004' `
    -DisplayName 'ITSM-RITM-Generator (1.5)' `
    -DefinitionPath 'flows/ritm-generator/definition.json'

$results += Deploy-FlowDefinition `
    -FlowId '00000000-0000-4000-8000-000000000030' `
    -DisplayName 'ITSM-Triage-Orchestrator' `
    -DefinitionPath 'flows/triage-orchestrator/definition.json'

$results += Deploy-FlowDefinition `
    -FlowId '00000000-0000-4000-8000-000000000057' `
    -DisplayName 'ITSM-Major-Incident-Detector' `
    -DefinitionPath 'flows/major-incident/definition.json'

$results += Deploy-FlowDefinition `
    -FlowId '00000000-0000-4000-8000-000000000010' `
    -DisplayName 'ITSM-Scheduled-SLA-Timer' `
    -DefinitionPath 'flows/sla-timer/definition.json'

$results | ConvertTo-Json -Depth 5
