#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ClientId = '00000000-0000-4000-8000-000000000020',
    [string]$ListTitle = 'Knowledge Base',
    [string]$OutputPath = 'prompts/task22_kb_list_search_indexing_20260509.json'
)

$ErrorActionPreference = 'Stop'

$helperScript = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../infra/sharepoint/lists/_helpers.ps1')
. $helperScript

Connect-ItsmTenantPilot -SiteUrl $SiteUrl -ClientId $ClientId | Out-Null

try {
    $list = Get-PnPList -Identity $ListTitle -Includes NoCrawl,ItemCount,EnableVersioning,Hidden,BaseTemplate,RootFolder,Fields
    $fields = Get-PnPField -List $ListTitle |
        Select-Object Title,InternalName,TypeAsString,Indexed,Hidden,ReadOnlyField,Sealed

    $importantFields = @('Title','ArticleNumber','Summary','Body','Keywords','ArticleStatus','Audience','Category','ResolvesJobType')
    $important = $fields | Where-Object { $_.InternalName -in $importantFields -or $_.Title -in $importantFields }
    $indexed = $fields | Where-Object { $_.Indexed -eq $true }

    $result = [pscustomobject]@{
        CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
        SiteUrl = $SiteUrl
        ListTitle = $list.Title
        ListId = $list.Id
        ListUrl = $list.RootFolder.ServerRelativeUrl
        ItemCount = $list.ItemCount
        NoCrawl = $list.NoCrawl
        SearchIndexingEnabled = (-not $list.NoCrawl)
        EnableVersioning = $list.EnableVersioning
        Hidden = $list.Hidden
        BaseTemplate = $list.BaseTemplate
        ImportantFields = @($important)
        IndexedFields = @($indexed)
        Verdict = if (-not $list.NoCrawl) { 'LIST_SEARCH_INDEXING_ENABLED' } else { 'LIST_SEARCH_INDEXING_DISABLED_NOCrawl_TRUE' }
        Note = 'NoCrawl=false means SharePoint search indexing is enabled for the list. Field Indexed=true is separate list-query indexing, not the same as search crawl inclusion.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 20
}
finally {
    Disconnect-PnPOnline
}
