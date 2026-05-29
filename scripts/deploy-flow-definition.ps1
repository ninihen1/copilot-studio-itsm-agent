#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [string]$FlowName,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [string]$DefinitionPath,

    [string]$Description = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DefinitionPath)) {
    throw "Definition file not found: $DefinitionPath"
}

$definition = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json

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

$baseUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowName"
$getUri = "$baseUri`?api-version=2016-11-01"
$live = Invoke-RestMethod -Method Get -Uri $getUri -Headers $headers

$payload = @{
    properties = @{
        displayName = $DisplayName
        definition = $definition
        connectionReferences = $live.properties.connectionReferences
    }
}

if ($Description) {
    $payload.properties.description = $Description
}

$body = $payload | ConvertTo-Json -Depth 100
$updated = Invoke-RestMethod -Method Patch -Uri $getUri -Headers $headers -Body $body

[pscustomobject]@{
    Name = $updated.name
    DisplayName = $updated.properties.displayName
    State = $updated.properties.state
    LastModifiedTime = $updated.properties.lastModifiedTime
    ConnectionReferenceKeys = @($updated.properties.connectionReferences.PSObject.Properties.Name) -join ', '
} | ConvertTo-Json -Depth 5
