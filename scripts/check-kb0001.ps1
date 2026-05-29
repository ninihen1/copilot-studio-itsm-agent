#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$helperScript = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../infra/sharepoint/lists/_helpers.ps1')
. $helperScript
Connect-ItsmTenantPilot -SiteUrl 'https://contoso.sharepoint.com/sites/ITSM' -ClientId '00000000-0000-4000-8000-000000000020' | Out-Null

$items = Get-PnPListItem -List 'Knowledge Base' -PageSize 100 -Fields 'ArticleNumber','Title','Summary','ArticleStatus','Keywords' |
    Where-Object { $_.FieldValues.ArticleNumber -eq 'KB-0001' }

$items | ForEach-Object {
    [pscustomobject]@{
        Id = $_.Id
        ArticleNumber = $_.FieldValues.ArticleNumber
        Title = $_.FieldValues.Title
        Status = $_.FieldValues.ArticleStatus
        Summary = $_.FieldValues.Summary
        Keywords = $_.FieldValues.Keywords
    }
} | ConvertTo-Json -Depth 5
