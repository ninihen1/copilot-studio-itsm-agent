#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [string]$LogicalName = 'botcomponent'
)

$ErrorActionPreference = 'Stop'
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$url = "$OrgUrl/api/data/v9.2/EntityDefinitions(LogicalName='$LogicalName')/Attributes?`$select=LogicalName,SchemaName,AttributeType"
(Invoke-RestMethod -Uri $url -Headers $headers).value |
    Sort-Object LogicalName |
    Select-Object LogicalName,SchemaName,AttributeType |
    ConvertTo-Json -Depth 5
