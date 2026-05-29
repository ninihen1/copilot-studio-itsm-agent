#Requires -Version 5.1

param(
    [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/ITSM',
    [string]$ListTitle = 'Tickets'
)

$ErrorActionPreference = 'Stop'

$expectedChoices = @(
    'Portal',
    'TriageAgent',
    'ProposeAction',
    'Email',
    'Teams',
    'Manual',
    'System'
)

function Get-Field {
    param([string]$InternalName)

    try {
        $output = m365 spo field get `
            --webUrl $SiteUrl `
            --listTitle $ListTitle `
            --internalName $InternalName `
            --output json 2>$null
    }
    catch {
        return $null
    }

    if ($LASTEXITCODE -ne 0 -or -not $output) {
        return $null
    }

    $output | ConvertFrom-Json
}

$internalName = 'TicketSource'
$displayName = 'Source'
$field = Get-Field -InternalName $internalName

if (-not $field) {
    $choicesXml = ($expectedChoices | ForEach-Object { "<CHOICE>$([System.Security.SecurityElement]::Escape($_))</CHOICE>" }) -join ''
    $xml = "<Field Type='Choice' Name='$internalName' StaticName='$internalName' DisplayName='$displayName' Required='FALSE' Indexed='TRUE' Format='Dropdown'><CHOICES>$choicesXml</CHOICES></Field>"

    $addOutput = m365 spo field add `
        --webUrl $SiteUrl `
        --listTitle $ListTitle `
        --xml $xml `
        --options AddFieldInternalNameHint `
        --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add Tickets.$internalName. m365 output: $addOutput"
    }

    $field = Get-Field -InternalName $internalName
}

if (-not $field) {
    throw "Tickets.$internalName was not found after add attempt."
}

$actualChoices = @($field.Choices)
$missingChoices = $expectedChoices | Where-Object { $actualChoices -notcontains $_ }
if ($missingChoices.Count -gt 0) {
    throw "Tickets.$internalName exists but is missing choices: $($missingChoices -join ', ')"
}

if (-not $field.Indexed) {
    m365 spo field set `
        --webUrl $SiteUrl `
        --listTitle $ListTitle `
        --internalName $internalName `
        --Indexed $true `
        --output none

    $field = Get-Field -InternalName $internalName
}

[pscustomobject]@{
    SiteUrl = $SiteUrl
    ListTitle = $ListTitle
    InternalName = $field.InternalName
    Title = $field.Title
    TypeAsString = $field.TypeAsString
    Indexed = $field.Indexed
    Choices = @($field.Choices) -join ', '
} | ConvertTo-Json

$businessKeyField = Get-Field -InternalName 'BusinessKey'
if (-not $businessKeyField) {
    $businessKeyXml = "<Field Type='Text' Name='BusinessKey' StaticName='BusinessKey' DisplayName='Business Key' Required='FALSE' Indexed='TRUE' MaxLength='64' />"
    $addBusinessKeyOutput = m365 spo field add `
        --webUrl $SiteUrl `
        --listTitle $ListTitle `
        --xml $businessKeyXml `
        --options AddFieldInternalNameHint `
        --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add Tickets.BusinessKey. m365 output: $addBusinessKeyOutput"
    }

    $businessKeyField = Get-Field -InternalName 'BusinessKey'
}

if (-not $businessKeyField) {
    throw 'Tickets.BusinessKey was not found after add attempt.'
}

if (-not $businessKeyField.Indexed) {
    m365 spo field set `
        --webUrl $SiteUrl `
        --listTitle $ListTitle `
        --internalName 'BusinessKey' `
        --Indexed $true `
        --output none

    $businessKeyField = Get-Field -InternalName 'BusinessKey'
}

[pscustomobject]@{
    SiteUrl = $SiteUrl
    ListTitle = $ListTitle
    InternalName = $businessKeyField.InternalName
    Title = $businessKeyField.Title
    TypeAsString = $businessKeyField.TypeAsString
    Indexed = $businessKeyField.Indexed
} | ConvertTo-Json
