#Requires -Version 5.1

<#
.SYNOPSIS
Verifies Azure Table idempotency semantics using Insert Entity and duplicate conflict.

.DESCRIPTION
Creates one test entity in `IdempotencyKeys`, then attempts to create it again.
The second insert must return a conflict. This proves the storage layer can act as
the dispatcher concurrency gate before any executor write happens.
#>

[CmdletBinding()]
param(
    [string]$EnvFile = '.env.production',
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$StorageAccountName = $(if ($env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT) { $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT } else { 'stitsmidempotency' }),
    [string]$PartitionKey = 'day4.test',
    [string]$RowKey = "test-$([guid]::NewGuid().ToString('N'))",
    [switch]$KeepEntity
)

$ErrorActionPreference = 'Stop'

if ($EnvFile -and (Test-Path -LiteralPath $EnvFile)) {
    & (Join-Path $PSScriptRoot '../../scripts/load-env.ps1') -Path $EnvFile | Out-Host
    if (-not $PSBoundParameters.ContainsKey('SubscriptionId') -and $env:AZURE_SUBSCRIPTION_ID) { $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID }
    if (-not $PSBoundParameters.ContainsKey('ResourceGroup') -and $env:AZURE_RESOURCE_GROUP) { $ResourceGroup = $env:AZURE_RESOURCE_GROUP }
    if (-not $PSBoundParameters.ContainsKey('StorageAccountName') -and $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT) { $StorageAccountName = $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT }
}

az account set --subscription $SubscriptionId

$connectionString = az storage account show-connection-string `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --query connectionString `
    -o tsv

$entity = @(
    "PartitionKey=$PartitionKey"
    "RowKey=$RowKey"
    'JobId=PJ-IDEMPOTENCY-TEST'
    'TicketId=TICKET-IDEMPOTENCY-TEST'
    'CallerUpn=caller@contoso.com'
    "CreatedAt=$((Get-Date).ToUniversalTime().ToString('o'))"
    'Status=Queued'
    'ResultRef=test-only'
)

Write-Host "Inserting first entity $PartitionKey/$RowKey..."
az storage entity insert `
    --connection-string $connectionString `
    --table-name IdempotencyKeys `
    --entity $entity `
    --if-exists fail `
    --only-show-errors `
    -o none
if ($LASTEXITCODE -ne 0) {
    throw 'First insert failed.'
}

$duplicateBlocked = $false
Write-Host "Attempting duplicate insert..."
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $duplicateOutput = az storage entity insert `
        --connection-string $connectionString `
        --table-name IdempotencyKeys `
        --entity $entity `
        --if-exists fail `
        --only-show-errors `
        -o none 2>&1
    if ($LASTEXITCODE -ne 0) {
        $duplicateBlocked = $true
    }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

if (-not $duplicateBlocked) {
    throw 'Duplicate insert unexpectedly succeeded; idempotency storage is not enforcing uniqueness.'
}

if (-not $KeepEntity) {
    az storage entity delete `
        --connection-string $connectionString `
        --table-name IdempotencyKeys `
        --partition-key $PartitionKey `
        --row-key $RowKey `
        --only-show-errors `
        -o none
}

[pscustomobject]@{
    Table = 'IdempotencyKeys'
    PartitionKey = $PartitionKey
    RowKey = $RowKey
    FirstInsert = 'Created'
    DuplicateInsert = 'Blocked'
    DuplicateSignal = 'Conflict/if-exists fail'
    EntityRetained = [bool]$KeepEntity
} | ConvertTo-Json
