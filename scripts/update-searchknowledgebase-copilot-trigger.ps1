#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$FlowId = '00000000-0000-4000-8000-000000000044',
    [string]$EvidencePath = 'prompts/task22_searchknowledgebase_copilot_trigger_update_20260509.json'
)

$ErrorActionPreference = 'Stop'

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

$uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId`?api-version=2016-11-01"
$flow = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
$definition = $flow.properties.definition

$beforeTrigger = $definition.triggers.manual

$definition.triggers.manual = [ordered]@{
    type = 'Request'
    kind = 'Skills'
    inputs = [ordered]@{
        schema = [ordered]@{
            type = 'object'
            required = @('query')
            properties = [ordered]@{
                query = [ordered]@{
                    title = 'query'
                    type = 'string'
                    'x-ms-dynamically-added' = $true
                    description = 'Raw user question or issue text to search for in the Knowledge Base.'
                    'x-ms-content-hint' = 'TEXT'
                }
                top = [ordered]@{
                    title = 'top'
                    type = 'number'
                    'x-ms-dynamically-added' = $true
                    description = 'Maximum number of matching articles to return.'
                    'x-ms-content-hint' = 'NUMBER'
                }
            }
        }
    }
    metadata = [ordered]@{
        operationMetadataId = [guid]::NewGuid().ToString()
    }
}

$definition.actions.Response.kind = 'Skills'
$responseSchema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        query = [ordered]@{
            title = 'query'
            type = 'string'
            'x-ms-dynamically-added' = $true
            'x-ms-content-hint' = 'TEXT'
        }
        normalizedQuery = [ordered]@{
            title = 'normalizedQuery'
            type = 'string'
            'x-ms-dynamically-added' = $true
            'x-ms-content-hint' = 'TEXT'
        }
        queryTokens = [ordered]@{
            title = 'queryTokens'
            type = 'array'
            items = [ordered]@{ type = 'string' }
            'x-ms-dynamically-added' = $true
        }
        matchCount = [ordered]@{
            title = 'matchCount'
            type = 'integer'
            'x-ms-dynamically-added' = $true
            'x-ms-content-hint' = 'NUMBER'
        }
        hasMatches = [ordered]@{
            title = 'hasMatches'
            type = 'boolean'
            'x-ms-dynamically-added' = $true
            'x-ms-content-hint' = 'BOOLEAN'
        }
        articles = [ordered]@{
            title = 'articles'
            type = 'array'
            'x-ms-dynamically-added' = $true
            items = [ordered]@{
                type = 'object'
                properties = [ordered]@{
                    score = [ordered]@{ type = 'integer' }
                    articleNumber = [ordered]@{ type = 'string' }
                    title = [ordered]@{ type = 'string' }
                    summary = [ordered]@{ type = 'string' }
                    body = [ordered]@{ type = 'string' }
                    bodyExcerpt = [ordered]@{ type = 'string' }
                    keywords = [ordered]@{ type = 'string' }
                    articleStatus = [ordered]@{ type = 'string' }
                    audience = [ordered]@{ type = 'string' }
                    resolvesJobType = [ordered]@{ type = 'string' }
                    itemId = [ordered]@{ type = 'string' }
                    url = [ordered]@{ type = 'string' }
                }
            }
        }
    }
}

if ($definition.actions.Response.inputs.PSObject.Properties.Name -contains 'schema') {
    $definition.actions.Response.inputs.schema = $responseSchema
} else {
    $definition.actions.Response.inputs | Add-Member -NotePropertyName 'schema' -NotePropertyValue $responseSchema
}

$payload = @{
    properties = @{
        displayName = $flow.properties.displayName
        definition = $definition
        connectionReferences = $flow.properties.connectionReferences
    }
}

$updated = Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body ($payload | ConvertTo-Json -Depth 100)

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    EnvironmentName = $EnvironmentName
    FlowId = $FlowId
    DisplayName = $updated.properties.displayName
    LastModifiedTime = $updated.properties.lastModifiedTime
    BeforeTriggerType = $beforeTrigger.type
    BeforeTriggerKind = $beforeTrigger.kind
    AfterTriggerType = $definition.triggers.manual.type
    AfterTriggerKind = $definition.triggers.manual.kind
    TriggerInputProperties = @($definition.triggers.manual.inputs.schema.properties.PSObject.Properties.Name)
    ResponseSchemaProperties = @($definition.actions.Response.inputs.schema.properties.PSObject.Properties.Name)
    Verdict = 'UPDATED_TO_COPILOT_DISCOVERABLE_BUTTON_TRIGGER'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
