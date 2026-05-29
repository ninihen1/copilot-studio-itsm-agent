#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$EnvironmentName = '00000000-0000-4000-8000-000000000045',
    [string]$FlowId = '00000000-0000-4000-8000-000000000048'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token `
    --resource 'https://service.flow.microsoft.com/' `
    --query accessToken `
    -o tsv

$headers = @{
    Authorization = "Bearer $token"
    'Content-Type' = 'application/json'
}

$uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId/triggers/manual/listCallbackUrl?api-version=2016-11-01"
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body '{}' | ConvertTo-Json -Depth 10
