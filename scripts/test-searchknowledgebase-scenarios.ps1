#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$FlowId = '00000000-0000-4000-8000-000000000044',
    [string]$EvidencePath = 'prompts/task22_searchknowledgebase_scoring_test_20260509.json'
)

$ErrorActionPreference = 'Stop'

$scenarios = @(
    'How do I reset my password?',
    'change my password',
    'I can''t sign in',
    'change password',
    'reset password',
    'VPN not working',
    'pasword rset',
    'KB-0001 and KB-0002',
    'login',
    'log in',
    'sign in'
)

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

$baseUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId"
$callbackUri = "$baseUri/triggers/manual/listCallbackUrl?api-version=2016-11-01"
$callback = Invoke-RestMethod -Method Post -Uri $callbackUri -Headers $headers -Body '{}'
$triggerUrl = $callback.value
if (-not $triggerUrl -and $callback.response) {
    $triggerUrl = $callback.response.value
}
if (-not $triggerUrl) {
    throw 'Power Automate listCallbackUrl did not return a trigger URL.'
}

$results = foreach ($scenario in $scenarios) {
    $body = @{
        query = $scenario
        top = 5
    } | ConvertTo-Json -Depth 5

    $started = (Get-Date).ToUniversalTime()
    try {
        $response = Invoke-RestMethod -Method Post -Uri $triggerUrl -ContentType 'application/json' -Body $body
        [pscustomobject]@{
            Query = $scenario
            StartedAt = $started.ToString('o')
            Status = 'Succeeded'
            NormalizedQuery = $response.normalizedQuery
            QueryTokens = $response.queryTokens
            MatchCount = $response.matchCount
            TopArticles = @($response.articles | Select-Object -First 5 | ForEach-Object {
                [pscustomobject]@{
                    Score = $_.score
                    ArticleNumber = $_.articleNumber
                    Title = $_.title
                    Keywords = $_.keywords
                    ResolvesJobType = $_.resolvesJobType
                }
            })
        }
    }
    catch {
        [pscustomobject]@{
            Query = $scenario
            StartedAt = $started.ToString('o')
            Status = 'Failed'
            Error = $_.Exception.Message
        }
    }
}

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    EnvironmentName = $EnvironmentName
    FlowId = $FlowId
    Scenarios = $results
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
