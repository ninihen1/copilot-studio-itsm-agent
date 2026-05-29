#Requires -Version 5.1

<#
.SYNOPSIS
Provisions Azure Table Storage resources for dispatcher idempotency and JWT replay protection.

.DESCRIPTION
Implements the storage shape from ADR 0001 and flows/dispatcher/contract.md:

- Storage account isolated from Function App/runtime storage
- Table `IdempotencyKeys`
- Table `JwtReplay`
- Optional Key Vault secrets containing the storage account name and connection string

Dispatcher production semantics:
Insert into `IdempotencyKeys` with `PartitionKey = jobType`, `RowKey = idempotencyKey`,
and `If-None-Match: *`. A 409 conflict is the authoritative duplicate/replay signal.
#>

[CmdletBinding()]
param(
    [string]$EnvFile = '.env.production',
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$Location = 'australiaeast',
    [string]$StorageAccountName = $(if ($env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT) { $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT } else { 'stitsmidempotency' }),
    [string]$KeyVaultName = $env:AZURE_KEY_VAULT_NAME,
    [switch]$SkipKeyVaultSecrets
)

$ErrorActionPreference = 'Stop'

if ($EnvFile -and (Test-Path -LiteralPath $EnvFile)) {
    & (Join-Path $PSScriptRoot '../../scripts/load-env.ps1') -Path $EnvFile | Out-Host
    if (-not $PSBoundParameters.ContainsKey('SubscriptionId') -and $env:AZURE_SUBSCRIPTION_ID) { $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID }
    if (-not $PSBoundParameters.ContainsKey('ResourceGroup') -and $env:AZURE_RESOURCE_GROUP) { $ResourceGroup = $env:AZURE_RESOURCE_GROUP }
    if (-not $PSBoundParameters.ContainsKey('KeyVaultName') -and $env:AZURE_KEY_VAULT_NAME) { $KeyVaultName = $env:AZURE_KEY_VAULT_NAME }
    if (-not $PSBoundParameters.ContainsKey('StorageAccountName') -and $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT) { $StorageAccountName = $env:ITSM_IDEMPOTENCY_STORAGE_ACCOUNT }
}

foreach ($required in @(
    @{ Name = 'SubscriptionId'; Value = $SubscriptionId },
    @{ Name = 'ResourceGroup'; Value = $ResourceGroup },
    @{ Name = 'StorageAccountName'; Value = $StorageAccountName }
)) {
    if ([string]::IsNullOrWhiteSpace($required.Value)) {
        throw "Missing required value: $($required.Name)"
    }
}

if ($StorageAccountName -notmatch '^[a-z0-9]{3,24}$') {
    throw "Storage account name must be 3-24 lowercase letters/numbers: $StorageAccountName"
}

Write-Host "Selecting subscription $SubscriptionId..."
az account set --subscription $SubscriptionId

Write-Host "Ensuring resource group $ResourceGroup..."
az group show --name $ResourceGroup --only-show-errors | Out-Null

$existingAccount = az storage account list `
    --resource-group $ResourceGroup `
    --query "[?name=='$StorageAccountName'].name | [0]" `
    -o tsv

if (-not $existingAccount) {
    Write-Host "Creating storage account $StorageAccountName..."
    az storage account create `
        --name $StorageAccountName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --https-only true `
        --tags Purpose=ITSM-Idempotency Environment=production | Out-Null
} else {
    Write-Host "Storage account exists: $StorageAccountName"
}

Write-Host "Ensuring tables..."
foreach ($table in @('IdempotencyKeys', 'JwtReplay')) {
    az storage table create `
        --account-name $StorageAccountName `
        --name $table `
        --auth-mode login `
        --only-show-errors `
        -o none
    Write-Host "  $table"
}

$connectionString = az storage account show-connection-string `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --query connectionString `
    -o tsv

if (-not $SkipKeyVaultSecrets) {
    if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
        throw 'KeyVaultName is required unless -SkipKeyVaultSecrets is set.'
    }

    Write-Host "Storing storage references in Key Vault $KeyVaultName..."
    az keyvault secret set --vault-name $KeyVaultName --name 'IdempotencyStorageAccountName' --value $StorageAccountName -o none
    az keyvault secret set --vault-name $KeyVaultName --name 'IdempotencyStorageConnectionString' --value $connectionString -o none
}

[pscustomobject]@{
    StorageAccountName = $StorageAccountName
    ResourceGroup = $ResourceGroup
    Location = $Location
    Tables = @('IdempotencyKeys', 'JwtReplay') -join ', '
    KeyVaultSecrets = if ($SkipKeyVaultSecrets) { 'Skipped' } else { 'IdempotencyStorageAccountName, IdempotencyStorageConnectionString' }
} | ConvertTo-Json
