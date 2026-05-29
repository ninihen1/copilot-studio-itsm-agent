#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$FlowId = '00000000-0000-4000-8000-000000000044',
    [string]$EvidencePath = 'prompts/task22_searchknowledgebase_scoring_update_20260509.json'
)

$ErrorActionPreference = 'Stop'

function Add-Wdl {
    param([string[]]$Terms)
    if ($Terms.Count -eq 1) {
        return $Terms[0]
    }

    $expr = "add($($Terms[0]), $($Terms[1]))"
    for ($i = 2; $i -lt $Terms.Count; $i++) {
        $expr = "add($expr, $($Terms[$i]))"
    }
    return $expr
}

function Normalize-FieldExpression {
    param([Parameter(Mandatory)][string]$FieldName)

    $base = "toLower(coalesce(item()?['$FieldName'], ''))"
    return "replace(replace(replace(replace(replace(replace(replace(replace($base, 'pasword', 'password'), 'rset', 'reset'), 'log in', 'login'), 'sign in', 'signin'), '-', ' '), '/', ' '), ',', ' '), '.', '')"
}

function Token-ScoreExpression {
    param(
        [Parameter(Mandatory)][string]$FieldName,
        [Parameter(Mandatory)][int]$Weight
    )

    $normalized = Normalize-FieldExpression -FieldName $FieldName
    return "mul(length(intersection(outputs('Query_Tokens'), split($normalized, ' '))), $Weight)"
}

$normalizeQuery = "@trim(replace(replace(replace(replace(replace(replace(replace(replace(toLower(coalesce(triggerBody()?['query'], '')), 'pasword', 'password'), 'rset', 'reset'), 'log in', 'login'), 'sign in', 'signin'), '?', ''), '.', ''), ',', ' '), '/', ' '))"
$queryTokens = "@split(replace(replace(replace(outputs('Normalize_Query'), '  ', ' '), '  ', ' '), '-', ' '), ' ')"

$scoreTerms = @(
    # Article number extraction: if the query contains KB-0001, KB-0002, etc., score that article.
    "if(equals(toLower(coalesce(item()?['ArticleNumber'], '')), outputs('Normalize_Query')), 1200, 0)",
    "if(and(not(empty(coalesce(item()?['ArticleNumber'], ''))), contains(outputs('Normalize_Query'), toLower(coalesce(item()?['ArticleNumber'], '')))), 1100, 0)",

    # Full-phrase matching, retained from the first version.
    "if(and(not(empty(outputs('Normalize_Query'))), contains($(Normalize-FieldExpression -FieldName 'Title'), outputs('Normalize_Query'))), 300, 0)",
    "if(and(not(empty(outputs('Normalize_Query'))), contains($(Normalize-FieldExpression -FieldName 'Keywords'), outputs('Normalize_Query'))), 250, 0)",
    "if(and(not(empty(outputs('Normalize_Query'))), contains($(Normalize-FieldExpression -FieldName 'Summary'), outputs('Normalize_Query'))), 200, 0)",
    "if(and(not(empty(outputs('Normalize_Query'))), contains($(Normalize-FieldExpression -FieldName 'Body'), outputs('Normalize_Query'))), 150, 0)",

    # Tokenized matching: each query token that appears in a field contributes score.
    (Token-ScoreExpression -FieldName 'Title' -Weight 70),
    (Token-ScoreExpression -FieldName 'Keywords' -Weight 90),
    (Token-ScoreExpression -FieldName 'Summary' -Weight 45),
    (Token-ScoreExpression -FieldName 'Body' -Weight 25),

    # Intent-specific password handling. Change-password should favor known-password article.
    "if(and(outputs('Is_Change_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Keywords'), 'change password')), 520, 0)",
    "if(and(outputs('Is_Change_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Title'), 'change')), 260, 0)",
    "if(and(outputs('Is_Change_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Summary'), 'still signin')), 120, 0)",

    # Reset/forgot-password should favor the reset flow article.
    "if(and(outputs('Is_Reset_Password_Query'), equals(toLower(coalesce(item()?['ResolvesJobType'], '')), 'identity.resetpassword')), 420, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Keywords'), 'forgot password')), 260, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Keywords'), 'reset')), 180, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Title'), 'forgot')), 140, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Title'), 'password')), 90, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Body'), 'reset')), 120, 0)",
    "if(and(outputs('Is_Reset_Password_Query'), contains($(Normalize-FieldExpression -FieldName 'Body'), 'password')), 80, 0)"
)

$scoreExpression = '@' + (Add-Wdl -Terms $scoreTerms)

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
$actions = $definition.actions

$actions.Normalize_Query.inputs = $normalizeQuery

$queryTokensAction = [ordered]@{
    runAfter = [ordered]@{
        Normalize_Query = @('Succeeded')
    }
    type = 'Compose'
    inputs = $queryTokens
}

if ($actions.PSObject.Properties.Name -contains 'Query_Tokens') {
    $actions.Query_Tokens = $queryTokensAction
}
else {
    $actions | Add-Member -NotePropertyName 'Query_Tokens' -NotePropertyValue $queryTokensAction
}

$actions.Top_Count.runAfter = [ordered]@{
    Query_Tokens = @('Succeeded')
}

$actions.Is_Password_Query.runAfter = [ordered]@{
    Top_Count = @('Succeeded')
}
$actions.Is_Password_Query.inputs = "@or(contains(outputs('Normalize_Query'), 'password'), contains(outputs('Normalize_Query'), 'forgot'), contains(outputs('Normalize_Query'), 'reset'), contains(outputs('Normalize_Query'), 'signin'), contains(outputs('Normalize_Query'), 'login'), contains(outputs('Normalize_Query'), 'locked'))"

$isChangeAction = [ordered]@{
    runAfter = [ordered]@{
        Is_Password_Query = @('Succeeded')
    }
    type = 'Compose'
    inputs = "@and(contains(outputs('Normalize_Query'), 'password'), or(contains(outputs('Normalize_Query'), 'change'), contains(outputs('Normalize_Query'), 'known'), contains(outputs('Normalize_Query'), 'current')))"
}

$isResetAction = [ordered]@{
    runAfter = [ordered]@{
        Is_Change_Password_Query = @('Succeeded')
    }
    type = 'Compose'
    inputs = "@and(outputs('Is_Password_Query'), not(outputs('Is_Change_Password_Query')), or(contains(outputs('Normalize_Query'), 'reset'), contains(outputs('Normalize_Query'), 'forgot'), contains(outputs('Normalize_Query'), 'password')))"
}

if ($actions.PSObject.Properties.Name -contains 'Is_Change_Password_Query') {
    $actions.Is_Change_Password_Query = $isChangeAction
}
else {
    $actions | Add-Member -NotePropertyName 'Is_Change_Password_Query' -NotePropertyValue $isChangeAction
}

if ($actions.PSObject.Properties.Name -contains 'Is_Reset_Password_Query') {
    $actions.Is_Reset_Password_Query = $isResetAction
}
else {
    $actions | Add-Member -NotePropertyName 'Is_Reset_Password_Query' -NotePropertyValue $isResetAction
}

$actions.Get_Published_KB_Items.runAfter = [ordered]@{
    Is_Reset_Password_Query = @('Succeeded')
}

$actions.Score_Articles.inputs.select.score = $scoreExpression

$actions.Response.inputs.body.normalizedQuery = "@outputs('Normalize_Query')"
if ($actions.Response.inputs.body.PSObject.Properties.Name -contains 'queryTokens') {
    $actions.Response.inputs.body.queryTokens = "@outputs('Query_Tokens')"
} else {
    $actions.Response.inputs.body | Add-Member -NotePropertyName 'queryTokens' -NotePropertyValue "@outputs('Query_Tokens')"
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
    State = $updated.properties.state
    LastModifiedTime = $updated.properties.lastModifiedTime
    AddedOrUpdatedActions = @('Query_Tokens', 'Is_Change_Password_Query', 'Is_Reset_Password_Query', 'Score_Articles')
    NormalizeQueryExpression = $normalizeQuery
    QueryTokensExpression = $queryTokens
    ScoreExpression = $scoreExpression
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
