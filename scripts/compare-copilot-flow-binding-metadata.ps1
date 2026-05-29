#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$DefaultOrgUrl = 'https://org9ef703f1.crm6.dynamics.com',
    [string]$DefaultEnvironmentName = '00000000-0000-4000-8000-000000000009',
    [string]$DefaultBotId = '00000000-0000-4000-8000-000000000022',
    [string]$WorkingWorkflowId = '00000000-0000-4000-8000-000000000016',
    [string]$DemoOrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$DemoEnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$DemoBotId = '00000000-0000-4000-8000-000000000039',
    [string]$DemoWorkflowId = '00000000-0000-4000-8000-000000000053',
    [string]$DemoManagementFlowId = '00000000-0000-4000-8000-000000000044',
    [string]$EvidencePath = 'prompts/copilot_flow_binding_metadata_comparison_20260509.json',
    [string]$ReportPath = 'prompts/copilot_flow_binding_metadata_comparison_20260509.md'
)

$ErrorActionPreference = 'Stop'

function Get-Token {
    param([Parameter(Mandatory)][string]$Resource)
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if (-not $token) {
        throw "Unable to acquire token for $Resource."
    }
    return $token
}

function Invoke-DvGet {
    param(
        [Parameter(Mandatory)][string]$OrgUrl,
        [Parameter(Mandatory)][string]$Path
    )
    $token = Get-Token -Resource $OrgUrl
    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/json'
    }
    Invoke-RestMethod -Method Get -Uri "$OrgUrl/api/data/v9.2/$Path" -Headers $headers
}

function Try-Invoke {
    param([scriptblock]$Script)
    try {
        & $Script
    }
    catch {
        [pscustomobject]@{
            Error = $_.Exception.Message
        }
    }
}

function Get-DvWorkflow {
    param([string]$OrgUrl, [string]$WorkflowId)
    $select = 'workflowid,name,category,type,statecode,statuscode,solutionid,createdon,modifiedon,clientdata,description'
    Try-Invoke { Invoke-DvGet -OrgUrl $OrgUrl -Path "workflows($WorkflowId)?`$select=$select" }
}

function Get-DvSolutionMembership {
    param([string]$OrgUrl, [string]$ObjectId)
    $response = Try-Invoke { Invoke-DvGet -OrgUrl $OrgUrl -Path "solutioncomponents?`$select=solutioncomponentid,componenttype,objectid,_solutionid_value&`$filter=objectid eq $ObjectId" }
    if ($response.Error) {
        return @([pscustomobject]@{ Error = $response.Error })
    }
    $components = $response.value
    foreach ($component in @($components)) {
        $solution = Invoke-DvGet -OrgUrl $OrgUrl -Path "solutions($($component._solutionid_value))?`$select=solutionid,uniquename,friendlyname,ismanaged,version"
        [pscustomobject]@{
            SolutionComponentId = $component.solutioncomponentid
            ComponentType = $component.componenttype
            ObjectId = $component.objectid
            SolutionId = $solution.solutionid
            SolutionUniqueName = $solution.uniquename
            SolutionFriendlyName = $solution.friendlyname
            IsManaged = $solution.ismanaged
            Version = $solution.version
        }
    }
}

function Get-DvBotActionComponentsForWorkflow {
    param([string]$OrgUrl, [string]$BotId, [string]$WorkflowId)
    $filter = [System.Uri]::EscapeDataString("_parentbotid_value eq $BotId")
    $select = 'botcomponentid,name,schemaname,componenttype,modifiedon,description,data,content'
    $components = (Invoke-DvGet -OrgUrl $OrgUrl -Path "botcomponents?`$select=$select&`$filter=$filter").value
    foreach ($component in @($components)) {
        $text = @($component.data, $component.content, $component.description) -join "`n"
        if ($text -match [regex]::Escape($WorkflowId)) {
            [pscustomobject]@{
                BotComponentId = $component.botcomponentid
                Name = $component.name
                SchemaName = $component.schemaname
                ComponentType = $component.componenttype
                ModifiedOn = $component.modifiedon
                HasInvokeFlowTaskAction = ($text -match 'InvokeFlowTaskAction')
                HasConnectionProperties = ($text -match 'connectionProperties')
                HasInputs = ($text -match '(?m)^inputs:')
                HasOutputs = ($text -match '(?m)^outputs:')
                Data = $component.data
                Description = $component.description
            }
        }
    }
}

function Get-ManagementFlowByWorkflowId {
    param([string]$EnvironmentName, [string]$WorkflowId)
    $token = Get-Token -Resource 'https://service.flow.microsoft.com/'
    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/json'
    }
    $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows?api-version=2016-11-01"
    $flows = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value
    $matches = foreach ($flow in @($flows)) {
        $definitionText = $flow.properties.definition | ConvertTo-Json -Depth 80
        if ($definitionText -match [regex]::Escape($WorkflowId) -or $flow.name -eq $WorkflowId -or $flow.properties.workflowEntityId -eq $WorkflowId) {
            $flow
        }
    }
    if (@($matches).Count -eq 1) {
        return $matches[0]
    }
    return $null
}

function Get-LiveFlow {
    param([string]$EnvironmentName, [string]$FlowId)
    $token = Get-Token -Resource 'https://service.flow.microsoft.com/'
    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/json'
    }
    $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId`?api-version=2016-11-01"
    Try-Invoke { Invoke-RestMethod -Method Get -Uri $uri -Headers $headers }
}

function Summarize-FlowDefinition {
    param([object]$Flow)
    $definition = $Flow.properties.definition
    $trigger = $definition.triggers.manual
    $responseActions = @()
    foreach ($action in @($definition.actions.PSObject.Properties)) {
        if ($action.Value.type -eq 'Response') {
            $responseActions += [pscustomobject]@{
                Name = $action.Name
                Type = $action.Value.type
                Kind = $action.Value.kind
                HasSchema = ($null -ne $action.Value.inputs.schema)
                SchemaProperties = if ($action.Value.inputs.schema.properties) { @($action.Value.inputs.schema.properties.PSObject.Properties.Name) } else { @() }
                BodyProperties = if ($action.Value.inputs.body) { @($action.Value.inputs.body.PSObject.Properties.Name) } else { @() }
            }
        }
    }

    [pscustomobject]@{
        ManagementFlowId = $Flow.name
        DisplayName = $Flow.properties.displayName
        State = $Flow.properties.state
        CreatedTime = $Flow.properties.createdTime
        LastModifiedTime = $Flow.properties.lastModifiedTime
        TriggerType = $trigger.type
        TriggerKind = $trigger.kind
        TriggerHasOperationMetadataId = [bool]$trigger.metadata.operationMetadataId
        TriggerInputProperties = if ($trigger.inputs.schema.properties) { @($trigger.inputs.schema.properties.PSObject.Properties.Name) } else { @() }
        TriggerSchema = $trigger.inputs.schema
        ResponseActions = @($responseActions)
        ConnectionReferenceKeys = @($Flow.properties.connectionReferences.PSObject.Properties.Name)
    }
}

$workingWorkflow = Get-DvWorkflow -OrgUrl $DefaultOrgUrl -WorkflowId $WorkingWorkflowId
$demoWorkflow = Get-DvWorkflow -OrgUrl $DemoOrgUrl -WorkflowId $DemoWorkflowId

$workingActionComponents = @(Get-DvBotActionComponentsForWorkflow -OrgUrl $DefaultOrgUrl -BotId $DefaultBotId -WorkflowId $WorkingWorkflowId)
$demoActionComponents = @(Get-DvBotActionComponentsForWorkflow -OrgUrl $DemoOrgUrl -BotId $DemoBotId -WorkflowId $DemoWorkflowId)

$workingLiveFlow = Get-LiveFlow -EnvironmentName $DefaultEnvironmentName -FlowId $WorkingWorkflowId

$demoLiveFlow = Get-LiveFlow -EnvironmentName $DemoEnvironmentName -FlowId $DemoManagementFlowId

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    Working = [pscustomobject]@{
        OrgUrl = $DefaultOrgUrl
        EnvironmentName = $DefaultEnvironmentName
        BotId = $DefaultBotId
        WorkflowId = $WorkingWorkflowId
        Workflow = $workingWorkflow
        SolutionComponents = @(Get-DvSolutionMembership -OrgUrl $DefaultOrgUrl -ObjectId $WorkingWorkflowId)
        BotActionComponents = $workingActionComponents
        ManagementFlowFound = ($null -ne $workingLiveFlow -and -not $workingLiveFlow.Error)
        ManagementFlowError = $workingLiveFlow.Error
        FlowSummary = if ($workingLiveFlow -and -not $workingLiveFlow.Error) { Summarize-FlowDefinition -Flow $workingLiveFlow } else { $null }
    }
    Demo = [pscustomobject]@{
        OrgUrl = $DemoOrgUrl
        EnvironmentName = $DemoEnvironmentName
        BotId = $DemoBotId
        WorkflowId = $DemoWorkflowId
        ManagementFlowId = $DemoManagementFlowId
        Workflow = $demoWorkflow
        SolutionComponents = @(Get-DvSolutionMembership -OrgUrl $DemoOrgUrl -ObjectId $DemoWorkflowId)
        BotActionComponents = $demoActionComponents
        FlowSummary = Summarize-FlowDefinition -Flow $demoLiveFlow
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

$workingAction = @($workingActionComponents)[0]
$demoAction = @($demoActionComponents)[0]
$workingFlowSummary = $evidence.Working.FlowSummary
$demoFlowSummary = $evidence.Demo.FlowSummary

$workingResponseSummary = @($workingFlowSummary.ResponseActions | ForEach-Object { "$($_.Name):$($_.Kind):schema=$($_.HasSchema)" }) -join '; '
$demoResponseSummary = @($demoFlowSummary.ResponseActions | ForEach-Object { "$($_.Name):$($_.Kind):schema=$($_.HasSchema)" }) -join '; '
$reportLines = @(
    '# Copilot Flow Binding Metadata Comparison - 2026-05-09',
    '',
    '## Scope',
    '',
    'Compared a working Copilot Studio flow action in the default environment with the Helpdesk Triage Agent SearchKnowledgeBase flow in FS Demo.',
    '',
    '## Working Flow Action',
    '',
    "- Environment: $DefaultEnvironmentName",
    "- Org: $DefaultOrgUrl",
    "- Bot: Flow Studio MCP Agent ($DefaultBotId)",
    "- Workflow ID referenced by action: $WorkingWorkflowId",
    "- Management flow found through Power Automate API: $($evidence.Working.ManagementFlowFound)",
    "- Action component: $($workingAction.SchemaName) / $($workingAction.Name)",
    "- Action has InvokeFlowTaskAction: $($workingAction.HasInvokeFlowTaskAction)",
    "- Action has connectionProperties: $($workingAction.HasConnectionProperties)",
    "- Action declares inputs: $($workingAction.HasInputs)",
    "- Action declares outputs: $($workingAction.HasOutputs)",
    '',
    '## Demo Flow Action',
    '',
    "- Environment: $DemoEnvironmentName",
    "- Org: $DemoOrgUrl",
    "- Bot: Helpdesk Triage Agent ($DemoBotId)",
    "- Workflow ID referenced by action: $DemoWorkflowId",
    "- Management flow ID: $DemoManagementFlowId",
    "- Action component: $($demoAction.SchemaName) / $($demoAction.Name)",
    "- Action has InvokeFlowTaskAction: $($demoAction.HasInvokeFlowTaskAction)",
    "- Action has connectionProperties: $($demoAction.HasConnectionProperties)",
    "- Action declares inputs: $($demoAction.HasInputs)",
    "- Action declares outputs: $($demoAction.HasOutputs)",
    '',
    '## Live Definition Comparison',
    '',
    '| Field | Working | Demo |',
    '| --- | --- | --- |',
    "| Management flow found | $($evidence.Working.ManagementFlowFound) | true |",
    "| Trigger type | $($workingFlowSummary.TriggerType) | $($demoFlowSummary.TriggerType) |",
    "| Trigger kind | $($workingFlowSummary.TriggerKind) | $($demoFlowSummary.TriggerKind) |",
    "| Trigger operationMetadataId | $($workingFlowSummary.TriggerHasOperationMetadataId) | $($demoFlowSummary.TriggerHasOperationMetadataId) |",
    "| Trigger input properties | $(@($workingFlowSummary.TriggerInputProperties) -join ', ') | $(@($demoFlowSummary.TriggerInputProperties) -join ', ') |",
    "| Response actions | $workingResponseSummary | $demoResponseSummary |",
    '',
    '## Findings',
    '',
    '1. The working action component is a standalone `TaskDialog` tool; it is not called from an explicit topic in the default agent export. This means it proves the flow-action registration pattern, but not a topic-level `BeginDialog` binding pattern.',
    '2. The working action component can be very small. For the `Untitled` action it has no declared YAML `inputs` or `outputs`; it only has `kind: InvokeFlowTaskAction`, `flowId`, `connectionProperties`, and `outputMode: All`.',
    '3. The demo action now matches the working action connection block, but the publisher still rejects topic-level bindings. That suggests the remaining problem is not the action YAML connection block.',
    '4. The latest publish failure points at the topic node `beginDialog_searchKnowledgeBase`, not at the action component itself. The binding metadata is not being resolved for explicit `input.binding` / `output.binding` in the topic.',
    '5. The flow may need a Copilot Studio UI refresh operation after trigger changes. Raw Power Automate definition changes made the flow visible in Tools, but the topic publisher still does not see the specific binding keys.',
    '6. Another material difference is output complexity. The working examples expose either no explicit output list or one `body` output, while the demo action exposes multiple outputs including arrays and an array of article objects. Simplifying the flow return to one `body` string/object may align better with the proven working pattern.',
    '',
    '## Recommended Next Step',
    '',
    'Use the Copilot Studio UI to insert the now-visible `Search knowl...` tool into the topic once, then export the generated YAML. If UI editing is not available, simplify `SearchKnowledgeBase.action.mcs.yml` to the proven minimal TaskDialog pattern and expose a single `body` output from the flow/action instead of binding `query`, `top`, `articles`, `hasMatches`, etc. individually.',
    '',
    '## Evidence',
    '',
    "Full JSON evidence: $EvidencePath"
)

$report = $reportLines -join "`r`n"

$report | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$report
