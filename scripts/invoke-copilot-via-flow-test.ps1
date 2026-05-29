param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$SourceFlowName = '00000000-0000-4000-8000-000000000030',
    [string]$TestFlowName = 'task22-copilot-chat-test',
    [string]$Message = 'How do I reset my password?',
    [string]$OutPath = 'prompts/task22_copilot_connector_flow_test_20260509.json'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource 'https://service.flow.microsoft.com/' --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    'Content-Type' = 'application/json'
}

$base = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName"
$sourceUri = "$base/flows/$SourceFlowName`?api-version=2016-11-01"
$source = Invoke-RestMethod -Uri $sourceUri -Headers $headers

$definition = @{
    '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        '$connections' = @{
            defaultValue = @{}
            type = 'Object'
        }
        '$authentication' = @{
            defaultValue = @{}
            type = 'SecureObject'
        }
    }
    triggers = @{
        manual = @{
            type = 'Request'
            kind = 'Http'
            inputs = @{
                method = 'POST'
                schema = @{
                    type = 'object'
                    required = @('message')
                    properties = @{
                        message = @{
                            type = 'string'
                        }
                    }
                }
            }
        }
    }
    actions = @{
        Execute_Copilot = @{
            runAfter = @{}
            type = 'OpenApiConnectionWebhook'
            inputs = @{
                host = @{
                    apiId = '/providers/Microsoft.PowerApps/apis/shared_microsoftcopilotstudio'
                    connectionName = 'shared_microsoftcopilotstudio'
                    operationId = 'ExecuteCopilotAsyncV2'
                }
                parameters = @{
                    Copilot = 'cre79_agent'
                    'body/message' = "@{triggerBody()?['message']}"
                }
                authentication = "@parameters('$authentication')"
            }
        }
        Response = @{
            runAfter = @{
                Execute_Copilot = @('Succeeded')
            }
            type = 'Response'
            inputs = @{
                statusCode = 200
                body = @{
                    lastResponse = "@{coalesce(outputs('Execute_Copilot')?['body/lastResponse'], '')}"
                    rawBody = "@outputs('Execute_Copilot')?['body']"
                }
            }
        }
    }
    outputs = @{}
}

$payload = @{
    properties = @{
        displayName = 'Task22-Copilot-Chat-Test'
        definition = $definition
        connectionReferences = $source.properties.connectionReferences
    }
}

$flowUri = "$base/flows/$TestFlowName`?api-version=2016-11-01"
try {
    Invoke-RestMethod -Uri $flowUri -Headers $headers | Out-Null
    $createdOrUpdated = Invoke-RestMethod -Method Patch -Uri $flowUri -Headers $headers -Body ($payload | ConvertTo-Json -Depth 100)
}
catch {
    $createdOrUpdated = Invoke-RestMethod -Method Post -Uri "$base/flows?api-version=2016-11-01" -Headers $headers -Body ($payload | ConvertTo-Json -Depth 100)
    $TestFlowName = $createdOrUpdated.name
    $flowUri = "$base/flows/$TestFlowName`?api-version=2016-11-01"
}

$startUri = "$base/flows/$TestFlowName/start?api-version=2016-11-01"
try {
    Invoke-RestMethod -Method Post -Uri $startUri -Headers $headers -Body '{}' | Out-Null
}
catch {
    # The flow may already be started immediately after PUT.
}

$callbackUri = "$base/flows/$TestFlowName/triggers/manual/listCallbackUrl?api-version=2016-11-01"
$callback = Invoke-RestMethod -Method Post -Uri $callbackUri -Headers $headers -Body '{}'

$requestBody = @{ message = $Message } | ConvertTo-Json -Depth 5
$invokeStarted = Get-Date
$callbackUrl = if ($callback.value) { $callback.value } else { $callback.response.value }
if (-not $callbackUrl) {
    throw "No callback URL returned: $($callback | ConvertTo-Json -Depth 10)"
}

$invokeResponse = Invoke-RestMethod -Method Post -Uri $callbackUrl -ContentType 'application/json' -Body $requestBody
$invokeEnded = Get-Date

$runsUri = "$base/flows/$TestFlowName/runs?api-version=2016-11-01"
$runs = (Invoke-RestMethod -Uri $runsUri -Headers $headers).value | Select-Object -First 5

$evidence = [pscustomobject]@{
    capturedAt = (Get-Date).ToUniversalTime().ToString('o')
    environmentName = $EnvironmentName
    testFlowName = $TestFlowName
    testFlowDisplayName = $createdOrUpdated.properties.displayName
    sourceFlowName = $SourceFlowName
    message = $Message
    invokeStartedUtc = $invokeStarted.ToUniversalTime().ToString('o')
    invokeEndedUtc = $invokeEnded.ToUniversalTime().ToString('o')
    response = $invokeResponse
    recentRuns = $runs | ForEach-Object {
        [pscustomobject]@{
            name = $_.name
            status = $_.properties.status
            startTime = $_.properties.startTime
            endTime = $_.properties.endTime
            triggerName = $_.properties.trigger.name
        }
    }
}

$evidence | ConvertTo-Json -Depth 20 | Set-Content -Path $OutPath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
