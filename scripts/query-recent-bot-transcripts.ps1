param(
    [string]$OrgUrl = 'https://org2684ab85.crm6.dynamics.com',
    [int]$Top = 20,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$uri = "$OrgUrl/api/data/v9.2/conversationtranscripts?`$select=conversationtranscriptid,name,createdon,content,metadata&`$orderby=createdon desc&`$top=$Top"
$items = (Invoke-RestMethod -Uri $uri -Headers $headers).value

$rows = foreach ($item in $items) {
    $content = [string]$item.content
    $meta = [string]$item.metadata

    $texts = @()
    try {
        $json = $content | ConvertFrom-Json
        $texts = $json.activities |
            Where-Object { $_.text } |
            Select-Object -First 12 |
            ForEach-Object { $_.text }
    }
    catch {
        $texts = [regex]::Matches($content, '"text":"((?:\\.|[^"\\])*)"') |
            Select-Object -First 12 |
            ForEach-Object { $_.Groups[1].Value -replace '\\n', ' ' -replace '\\"', '"' }
    }

    [pscustomobject]@{
        id = $item.conversationtranscriptid
        createdon = $item.createdon
        name = $item.name
        metadata = $meta
        hasResetQuestion = $content -like '*How do I reset my password*'
        hasNoTicketFollowup = $content -like '*No, I need a ticket*'
        hasKB0001 = $content -like '*KB-0001*'
        hasSearchKnowledgeBase = $content -like '*SearchKnowledgeBase*' -or $content -like '*Search knowledge base*'
        hasConnectionManagerCard = $content -like '*connectionManagerCard*'
        textPreview = ($texts -join ' | ')
    }
}

if ($OutPath) {
    $rows | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8
}

$rows | ConvertTo-Json -Depth 10
