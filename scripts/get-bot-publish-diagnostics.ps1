#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000039',
    [string]$EvidencePath = 'prompts/day4_tasks6_22_56_publish_diagnostics.json'
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

$botSelect = 'botid,name,schemaname,componentstate,synchronizationstatus,statuscode,statecode,publishedon,configuration,createdon,modifiedon'
$bot = Invoke-DvGet -Url "$OrgUrl/api/data/v9.2/bots($BotId)?`$select=$botSelect"

$componentSelect = 'botcomponentid,name,schemaname,componenttype,componentstate,statecode,statuscode,description,modifiedon,data,content'
$componentFilter = [System.Uri]::EscapeDataString("_parentbotid_value eq $BotId")
$components = (Invoke-DvGet -Url "$OrgUrl/api/data/v9.2/botcomponents?`$select=$componentSelect&`$filter=$componentFilter").value

$flowPatterns = @(
    '4355ee4d364140b99e64225915274edd',
    '00000000-0000-4000-8000-000000000048',
    '00000000-0000-4000-8000-000000000036'
)

$problemSnippets = foreach ($component in $components) {
    $text = @($component.data, $component.content, $component.description) -join "`n"
    if ($text -match 'sig=' -or $component.schemaname -match 'ProposeAction' -or ($flowPatterns | Where-Object { $text -match [regex]::Escape($_) })) {
        [pscustomobject]@{
            SchemaName = $component.schemaname
            Name = $component.name
            ComponentType = $component.componenttype
            ComponentState = $component.componentstate
            StateCode = $component.statecode
            StatusCode = $component.statuscode
            ModifiedOn = $component.modifiedon
            HasLegacySig = ($text -match 'sig=')
            HasLegacyWorkflow = ($text -match '4355ee4d364140b99e64225915274edd')
            HasManagementFlowId = ($text -match '00000000-0000-4000-8000-000000000048')
            HasDataverseWorkflowId = ($text -match '00000000-0000-4000-8000-000000000036')
            Preview = ($text -replace '\s+', ' ').Substring(0, [Math]::Min(500, ($text -replace '\s+', ' ').Length))
        }
    }
}

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    Bot = $bot
    MatchingComponents = @($problemSnippets)
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 30
