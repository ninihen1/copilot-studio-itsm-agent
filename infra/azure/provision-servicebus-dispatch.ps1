#Requires -Version 5.1

<#
.SYNOPSIS
Provisions the Service Bus executor dispatch topology.

.DESCRIPTION
Implements the queueing design from flows/dispatcher/contract.md and
flows/executors/contract.md:

- Standard namespace for topic support
- Topic `provisioning-jobs` with duplicate detection
- One session-enabled subscription per executor category
- SQL filters on the Service Bus brokered-message Label. Modern client SDKs expose
  this as Subject, but Azure Service Bus SQL filters evaluate the system property as
  `sys.Label`.
- Peek-lock friendly subscription settings: 5 minute lock, max delivery count 5

This provisions the production hardening target only. The current pilot dispatcher and
executor flows still use SharePoint polling until they are migrated to Service Bus
triggers/senders.
#>

[CmdletBinding()]
param(
    [string]$EnvFile = '.env.production',
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$Location = 'australiaeast',
    [string]$NamespaceName = $(if ($env:ITSM_SERVICEBUS_NAMESPACE) { $env:ITSM_SERVICEBUS_NAMESPACE } else { 'sb-itsm-demo-pilot' }),
    [string]$TopicName = $(if ($env:ITSM_SERVICEBUS_TOPIC) { $env:ITSM_SERVICEBUS_TOPIC } else { 'provisioning-jobs' }),
    [string]$KeyVaultName = $env:AZURE_KEY_VAULT_NAME,
    [switch]$SkipKeyVaultSecrets
)

$ErrorActionPreference = 'Stop'

if ($EnvFile -and (Test-Path -LiteralPath $EnvFile)) {
    & (Join-Path $PSScriptRoot '../../scripts/load-env.ps1') -Path $EnvFile | Out-Host
    if (-not $PSBoundParameters.ContainsKey('SubscriptionId') -and $env:AZURE_SUBSCRIPTION_ID) { $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID }
    if (-not $PSBoundParameters.ContainsKey('ResourceGroup') -and $env:AZURE_RESOURCE_GROUP) { $ResourceGroup = $env:AZURE_RESOURCE_GROUP }
    if (-not $PSBoundParameters.ContainsKey('KeyVaultName') -and $env:AZURE_KEY_VAULT_NAME) { $KeyVaultName = $env:AZURE_KEY_VAULT_NAME }
    if (-not $PSBoundParameters.ContainsKey('NamespaceName') -and $env:ITSM_SERVICEBUS_NAMESPACE) { $NamespaceName = $env:ITSM_SERVICEBUS_NAMESPACE }
    if (-not $PSBoundParameters.ContainsKey('TopicName') -and $env:ITSM_SERVICEBUS_TOPIC) { $TopicName = $env:ITSM_SERVICEBUS_TOPIC }
}

foreach ($required in @(
    @{ Name = 'SubscriptionId'; Value = $SubscriptionId },
    @{ Name = 'ResourceGroup'; Value = $ResourceGroup },
    @{ Name = 'NamespaceName'; Value = $NamespaceName },
    @{ Name = 'TopicName'; Value = $TopicName }
)) {
    if ([string]::IsNullOrWhiteSpace($required.Value)) {
        throw "Missing required value: $($required.Name)"
    }
}

if ($NamespaceName -notmatch '^[a-z0-9-]{6,50}$') {
    throw "Service Bus namespace name must be 6-50 lowercase letters/numbers/hyphens: $NamespaceName"
}

$subscriptions = @(
    @{ Name = 'sub-identity'; Filter = "sys.Label LIKE 'identity.%'" },
    @{ Name = 'sub-groups'; Filter = "sys.Label LIKE 'groups.%'" },
    @{ Name = 'sub-licensing'; Filter = "sys.Label LIKE 'licensing.%'" },
    @{ Name = 'sub-exchange'; Filter = "sys.Label LIKE 'exchange.%'" },
    @{ Name = 'sub-sharepoint'; Filter = "sys.Label LIKE 'sharepoint.%'" },
    @{ Name = 'sub-teams'; Filter = "sys.Label LIKE 'teams.%' OR sys.Label LIKE 'endpoint.%'" }
)

Write-Host "Selecting subscription $SubscriptionId..."
az account set --subscription $SubscriptionId

Write-Host "Ensuring resource group $ResourceGroup..."
az group show --name $ResourceGroup --only-show-errors | Out-Null

$existingNamespace = az servicebus namespace list `
    --resource-group $ResourceGroup `
    --query "[?name=='$NamespaceName'].name | [0]" `
    -o tsv

if (-not $existingNamespace) {
    Write-Host "Creating Service Bus namespace $NamespaceName..."
    az servicebus namespace create `
        --resource-group $ResourceGroup `
        --name $NamespaceName `
        --location $Location `
        --sku Standard `
        --min-tls 1.2 `
        --tags Purpose=ITSM-ExecutorDispatch Environment=production `
        --only-show-errors `
        -o none
} else {
    Write-Host "Service Bus namespace exists: $NamespaceName"
}

$existingTopic = az servicebus topic list `
    --resource-group $ResourceGroup `
    --namespace-name $NamespaceName `
    --query "[?name=='$TopicName'].name | [0]" `
    -o tsv

if (-not $existingTopic) {
    Write-Host "Creating topic $TopicName..."
    az servicebus topic create `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --name $TopicName `
        --duplicate-detection true `
        --duplicate-detection-history-time-window PT10M `
        --default-message-time-to-live P1D `
        --enable-partitioning true `
        --enable-ordering true `
        --max-size 1024 `
        --only-show-errors `
        -o none
} else {
    Write-Host "Topic exists: $TopicName"
}

foreach ($subscription in $subscriptions) {
    $subscriptionName = $subscription.Name
    $filter = $subscription.Filter

    $existingSubscription = az servicebus topic subscription list `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --query "[?name=='$subscriptionName'].name | [0]" `
        -o tsv

    if (-not $existingSubscription) {
        Write-Host "Creating subscription $subscriptionName..."
        az servicebus topic subscription create `
            --resource-group $ResourceGroup `
            --namespace-name $NamespaceName `
            --topic-name $TopicName `
            --name $subscriptionName `
            --enable-session true `
            --lock-duration PT5M `
            --max-delivery-count 5 `
            --enable-dead-lettering-on-message-expiration true `
            --default-message-time-to-live P1D `
            --only-show-errors `
            -o none
    } else {
        Write-Host "Subscription exists: $subscriptionName"
    }

    $defaultRule = az servicebus topic subscription rule list `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --subscription-name $subscriptionName `
        --query "[?name=='`$Default'].name | [0]" `
        -o tsv

    if ($defaultRule) {
        Write-Host "Removing default catch-all rule from $subscriptionName..."
        az servicebus topic subscription rule delete `
            --resource-group $ResourceGroup `
            --namespace-name $NamespaceName `
            --topic-name $TopicName `
            --subscription-name $subscriptionName `
            --name '$Default' `
            --only-show-errors
    }

    $ruleName = 'jobtype-filter'
    $existingRule = az servicebus topic subscription rule list `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --subscription-name $subscriptionName `
        --query "[?name=='$ruleName'].name | [0]" `
        -o tsv

    if ($existingRule) {
        az servicebus topic subscription rule delete `
            --resource-group $ResourceGroup `
            --namespace-name $NamespaceName `
            --topic-name $TopicName `
            --subscription-name $subscriptionName `
            --name $ruleName `
            --only-show-errors
    }

    Write-Host "Applying rule $ruleName on ${subscriptionName}: $filter"
    az servicebus topic subscription rule create `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --subscription-name $subscriptionName `
        --name $ruleName `
        --filter-type SqlFilter `
        --filter-sql-expression $filter `
        --only-show-errors `
        -o none
}

$primaryConnectionString = az servicebus namespace authorization-rule keys list `
    --resource-group $ResourceGroup `
    --namespace-name $NamespaceName `
    --name RootManageSharedAccessKey `
    --query primaryConnectionString `
    -o tsv

if (-not $SkipKeyVaultSecrets) {
    if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
        throw 'KeyVaultName is required unless -SkipKeyVaultSecrets is set.'
    }

    Write-Host "Storing Service Bus references in Key Vault $KeyVaultName..."
    az keyvault secret set --vault-name $KeyVaultName --name 'ServiceBusNamespaceName' --value $NamespaceName -o none
    az keyvault secret set --vault-name $KeyVaultName --name 'ServiceBusTopicName' --value $TopicName -o none
    az keyvault secret set --vault-name $KeyVaultName --name 'ServiceBusConnectionString' --value $primaryConnectionString -o none
}

[pscustomobject]@{
    Namespace = $NamespaceName
    Topic = $TopicName
    ResourceGroup = $ResourceGroup
    Region = $Location
    Sku = 'Standard'
    DuplicateDetection = 'PT10M'
    DefaultMessageTimeToLive = 'P1D'
    RequiresSessions = $true
    Subscriptions = ($subscriptions | ForEach-Object { "$($_.Name): $($_.Filter)" }) -join '; '
    KeyVaultSecrets = if ($SkipKeyVaultSecrets) { 'Skipped' } else { 'ServiceBusNamespaceName, ServiceBusTopicName, ServiceBusConnectionString' }
} | ConvertTo-Json
