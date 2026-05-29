#Requires -Version 5.1

param(
    [string]$WebUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$CsvPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'prompts/kb_seed_articles.csv'),
    [string]$ListTitle = 'Knowledge Base'
)

$ErrorActionPreference = 'Stop'

function Invoke-M365Json {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & m365 @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "m365 command failed: m365 $($Arguments -join ' ')"
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    return $output | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$resource = 'https://contoso.sharepoint.com'
$articles = Import-Csv -LiteralPath $CsvPath
if ($articles.Count -ne 40) {
    throw "Expected 40 seed rows, found $($articles.Count)."
}

Write-Host "Loading live category lookup IDs..."
$categoryItems = Invoke-M365Json -Arguments @(
    'spo', 'listitem', 'list',
    '--webUrl', $WebUrl,
    '--listTitle', 'Categories',
    '--fields', 'Id,Title',
    '--pageSize', '5000',
    '--output', 'json'
)

$categoryByTitle = @{}
foreach ($category in $categoryItems) {
    $categoryByTitle[$category.Title] = [int]$category.Id
}

$missingCategories = $articles |
    Select-Object -ExpandProperty CategoryTitle -Unique |
    Where-Object { -not $categoryByTitle.ContainsKey($_) }

if ($missingCategories) {
    throw "Missing Categories lookup rows for: $($missingCategories -join ', ')"
}

Write-Host "Resolving KB author user IDs..."
$authorByUpn = @{}
foreach ($upn in ($articles | Select-Object -ExpandProperty KbAuthorUpn -Unique)) {
    $user = Invoke-M365Json -Arguments @(
        'spo', 'user', 'get',
        '--webUrl', $WebUrl,
        '--email', $upn,
        '--output', 'json'
    )
    $authorByUpn[$upn] = [int]$user.Id
}

Write-Host "Loading existing KB article numbers..."
$existingItems = Invoke-M365Json -Arguments @(
    'spo', 'listitem', 'list',
    '--webUrl', $WebUrl,
    '--listTitle', $ListTitle,
    '--fields', 'Id,ArticleNumber',
    '--pageSize', '5000',
    '--output', 'json'
)

$existingByArticleNumber = @{}
foreach ($item in @($existingItems)) {
    if (-not [string]::IsNullOrWhiteSpace($item.ArticleNumber)) {
        $existingByArticleNumber[$item.ArticleNumber] = [int]$item.Id
    }
}

$entityTypeUrl = "$WebUrl/_api/web/lists/getbytitle(%27Knowledge%20Base%27)?`$select=ListItemEntityTypeFullName"
$entityType = (Invoke-M365Json -Arguments @(
    'request',
    '--url', $entityTypeUrl,
    '--resource', $resource,
    '--output', 'json'
)).ListItemEntityTypeFullName

$publishedDate = (Get-Date).ToUniversalTime().ToString('o')
$created = 0
$skipped = 0

foreach ($article in $articles) {
    if ($existingByArticleNumber.ContainsKey($article.ArticleNumber)) {
        Write-Host "SKIP existing $($article.ArticleNumber) item $($existingByArticleNumber[$article.ArticleNumber])"
        $skipped++
        continue
    }

    $body = [ordered]@{
        '__metadata' = @{ type = $entityType }
        Title = $article.Title
        ArticleNumber = $article.ArticleNumber
        Summary = $article.Summary
        Body = $article.Body
        CategoryId = $categoryByTitle[$article.CategoryTitle]
        Audience = $article.Audience
        ArticleStatus = 'Published'
        KbAuthorId = $authorByUpn[$article.KbAuthorUpn]
        PublishedDate = $publishedDate
        Keywords = $article.Keywords
        ResolvesJobType = $article.ResolvesJobType
        ViewCount = 0
        HelpfulCount = 0
        NotHelpfulCount = 0
    }

    $bodyPath = Join-Path $env:TEMP ("itsm-kb-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    try {
        $jsonBody = $body | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($bodyPath, $jsonBody, (New-Object System.Text.UTF8Encoding $false))
        $addUrl = "$WebUrl/_api/web/lists/getbytitle(%27Knowledge%20Base%27)/items"
        Invoke-M365Json -Arguments @(
            'request',
            '--method', 'post',
            '--url', $addUrl,
            '--resource', $resource,
            '--body', "@$bodyPath",
            '--content-type', 'application/json;odata=verbose',
            '--accept', 'application/json;odata=verbose',
            '--output', 'none'
        )
        Write-Host "CREATED $($article.ArticleNumber): $($article.Title)"
        $created++
    }
    finally {
        if (Test-Path -LiteralPath $bodyPath) {
            Remove-Item -LiteralPath $bodyPath -Force
        }
    }
}

Write-Host "Verifying seeded articles..."
$allKbItems = Invoke-M365Json -Arguments @(
    'spo', 'listitem', 'list',
    '--webUrl', $WebUrl,
    '--listTitle', $ListTitle,
    '--fields', 'Id,Title,ArticleNumber,ArticleStatus',
    '--pageSize', '5000',
    '--output', 'json'
)

$seeded = @($allKbItems | Where-Object {
    $_.ArticleNumber -match '^KB-00[0-4][0-9]$' -and $_.ArticleStatus -eq 'Published'
})

$expected = 1..40 | ForEach-Object { 'KB-{0:0000}' -f $_ }
$actual = $seeded | Select-Object -ExpandProperty ArticleNumber
$missing = $expected | Where-Object { $_ -notin $actual }

if ($missing) {
    throw "Seed verification failed. Missing: $($missing -join ', ')"
}

[pscustomobject]@{
    Created = $created
    SkippedExisting = $skipped
    PublishedSeedArticles = @($seeded).Count
    PublishedDateUtc = $publishedDate
} | ConvertTo-Json
