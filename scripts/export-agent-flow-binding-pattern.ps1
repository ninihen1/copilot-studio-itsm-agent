#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org9ef703f1.crm6.dynamics.com',
    [string]$BotId = '00000000-0000-4000-8000-000000000022',
    [string]$OutputPath = 'prompts/default_agent_flow_binding_components_20260509.json'
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

$select = 'botcomponentid,name,schemaname,componenttype,modifiedon,description,data,content'
$filter = [System.Uri]::EscapeDataString("_parentbotid_value eq $BotId")
$uri = "$OrgUrl/api/data/v9.2/botcomponents?`$select=$select&`$filter=$filter"
$components = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value

$interesting = foreach ($component in $components) {
    $text = @($component.data, $component.content, $component.description) -join "`n"
    if ($text -match 'InvokeFlow|TaskDialog|BeginDialog|flowId|InvokeFlowTaskAction|kind:\s+Action') {
        [pscustomobject]@{
            Name = $component.name
            SchemaName = $component.schemaname
            ComponentType = $component.componenttype
            ModifiedOn = $component.modifiedon
            HasInvokeFlowTaskAction = ($text -match 'InvokeFlowTaskAction')
            HasInvokeFlowAction = ($text -match 'InvokeFlowAction')
            HasBeginDialog = ($text -match 'BeginDialog')
            HasDialogReference = ($text -match 'dialog:')
            FlowIds = @([regex]::Matches($text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value } | Select-Object -Unique)
            Data = $component.data
            Content = $component.content
            Description = $component.description
        }
    }
}

$bot = Invoke-RestMethod -Method Get -Uri "$OrgUrl/api/data/v9.2/bots($BotId)?`$select=botid,name,schemaname,modifiedon,publishedon" -Headers $headers

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    OrgUrl = $OrgUrl
    Bot = $bot
    Components = @($interesting)
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

$evidence.Components |
    Select-Object Name, SchemaName, ComponentType, ModifiedOn, HasInvokeFlowTaskAction, HasInvokeFlowAction, HasBeginDialog, HasDialogReference, @{n='FlowIds';e={$_.FlowIds -join ','}} |
    ConvertTo-Json -Depth 10
