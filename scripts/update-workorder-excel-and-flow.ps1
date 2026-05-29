#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$FlowId = '00000000-0000-4000-8000-000000000028',
    [string]$GraphResource = 'https://graph.microsoft.com',
    [string]$SharePointHost = 'contoso.sharepoint.com',
    [string]$SitePath = '/sites/MCPDemo',
    [string]$WorkbookItemId = '01UZVN4FZ65IXJJCW2MRGKG66H4SZVN2DY',
    [string]$TableName = 'WorkOrder_WorkOrders',
    [string]$EvidencePath = 'prompts/workorder_scheduling_fields_update_20260509.json'
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

$graphToken = Get-Token -Resource $GraphResource
$graphHeaders = @{
    Authorization = "Bearer $graphToken"
    Accept = 'application/json'
    'Content-Type' = 'application/json'
}

$site = Invoke-RestMethod -Method Get -Uri "$GraphResource/v1.0/sites/$SharePointHost`:$SitePath" -Headers $graphHeaders
$columnsUri = "$GraphResource/v1.0/sites/$($site.id)/drive/items/$WorkbookItemId/workbook/tables/$TableName/columns"
$beforeColumns = (Invoke-RestMethod -Method Get -Uri $columnsUri -Headers $graphHeaders).value
$rowsUri = "$GraphResource/v1.0/sites/$($site.id)/drive/items/$WorkbookItemId/workbook/tables/$TableName/rows"
$existingRows = (Invoke-RestMethod -Method Get -Uri $rowsUri -Headers $graphHeaders).value

$columnsToAdd = @('JobDate', 'JobStartTime', 'JobDuration')
$addedColumns = @()
foreach ($columnName in $columnsToAdd) {
    if (@($beforeColumns.name) -notcontains $columnName) {
        $columnValues = New-Object System.Collections.ArrayList
        [void]$columnValues.Add(@($columnName))
        foreach ($row in @($existingRows)) {
            [void]$columnValues.Add(@(''))
        }

        $body = @{
            values = @($columnValues)
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod -Method Post -Uri "$columnsUri/add" -Headers $graphHeaders -Body $body | Out-Null
        $addedColumns += $columnName
        $beforeColumns = (Invoke-RestMethod -Method Get -Uri $columnsUri -Headers $graphHeaders).value
    }
}

$afterColumns = (Invoke-RestMethod -Method Get -Uri $columnsUri -Headers $graphHeaders).value

$flowToken = Get-Token -Resource 'https://service.flow.microsoft.com/'
$flowHeaders = @{
    Authorization = "Bearer $flowToken"
    'Content-Type' = 'application/json'
}

$flowUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId`?api-version=2016-11-01"
$flow = Invoke-RestMethod -Method Get -Uri $flowUri -Headers $flowHeaders
$definition = $flow.properties.definition
$actions = $definition.actions

$oldSystemPrompt = $actions.Call_Azure_OpenAI.inputs.body.messages[0].content
$actions.Call_Azure_OpenAI.inputs.body.messages[0].content = 'Extract one property maintenance work order from email text plus any PDF/OCR text. Important details can be scattered across both sources. Use both sources together. Return only JSON with keys: propertyName, propertyAddress, unit, tenantName, contactPhone, contactEmail, issueDescription, tradeCategory, priority, requestedDate, preferredWindow, jobDate, jobStartTime, jobDuration, accessInstructions, confidence, missingFields, validationNotes, duplicateKey. Extract scheduling information when present: jobDate is the scheduled appointment date in ISO yyyy-MM-dd format when possible, jobStartTime is the scheduled start time as text such as "9:00 AM", and jobDuration is the estimated appointment duration such as "2 hours". tradeCategory must be Plumbing, Electrical, HVAC, Appliance, General, Pest, Roofing, Cleaning, or Other. priority must be Emergency, Urgent, Normal, Low, or Scheduled. confidence must be 0 to 1. Use null when unknown. Do not invent details.'

$schemaProperties = $actions.Parse_Extraction_JSON.inputs.schema.properties
foreach ($propertyName in @('jobDate', 'jobStartTime', 'jobDuration')) {
    if ($schemaProperties.PSObject.Properties.Name -notcontains $propertyName) {
        $schemaProperties | Add-Member -NotePropertyName $propertyName -NotePropertyValue ([ordered]@{
            type = @('string', 'null')
        })
    }
}

$workOrderParams = $actions.Create_Work_Order.inputs.parameters
foreach ($mapping in @(
    @{ Name = 'item/JobDate'; Value = "@coalesce(body('Parse_Extraction_JSON')?['jobDate'], '')" },
    @{ Name = 'item/JobStartTime'; Value = "@coalesce(body('Parse_Extraction_JSON')?['jobStartTime'], '')" },
    @{ Name = 'item/JobDuration'; Value = "@coalesce(body('Parse_Extraction_JSON')?['jobDuration'], '')" }
)) {
    if ($workOrderParams.PSObject.Properties.Name -contains $mapping.Name) {
        $workOrderParams.($mapping.Name) = $mapping.Value
    } else {
        $workOrderParams | Add-Member -NotePropertyName $mapping.Name -NotePropertyValue $mapping.Value
    }
}

$payload = @{
    properties = @{
        displayName = $flow.properties.displayName
        definition = $definition
        connectionReferences = $flow.properties.connectionReferences
    }
}

$updated = Invoke-RestMethod -Method Patch -Uri $flowUri -Headers $flowHeaders -Body ($payload | ConvertTo-Json -Depth 100)

$evidence = [pscustomobject]@{
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    Workbook = [pscustomobject]@{
        SiteId = $site.id
        WorkbookItemId = $WorkbookItemId
        TableName = $TableName
        AddedColumns = $addedColumns
        ColumnsAfter = @($afterColumns.name)
    }
    Flow = [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        FlowId = $FlowId
        DisplayName = $updated.properties.displayName
        LastModifiedTime = $updated.properties.lastModifiedTime
        PromptChanged = ($oldSystemPrompt -ne $actions.Call_Azure_OpenAI.inputs.body.messages[0].content)
        SchemaHasJobDate = ($schemaProperties.PSObject.Properties.Name -contains 'jobDate')
        SchemaHasJobStartTime = ($schemaProperties.PSObject.Properties.Name -contains 'jobStartTime')
        SchemaHasJobDuration = ($schemaProperties.PSObject.Properties.Name -contains 'jobDuration')
        AddRowHasJobDate = ($workOrderParams.PSObject.Properties.Name -contains 'item/JobDate')
        AddRowHasJobStartTime = ($workOrderParams.PSObject.Properties.Name -contains 'item/JobStartTime')
        AddRowHasJobDuration = ($workOrderParams.PSObject.Properties.Name -contains 'item/JobDuration')
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence | ConvertTo-Json -Depth 20
