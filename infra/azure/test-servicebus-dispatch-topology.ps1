#Requires -Version 5.1

<#
.SYNOPSIS
Validates the Service Bus dispatch topology for executor isolation.

.DESCRIPTION
Checks that the Service Bus namespace/topic/subscriptions/rules match
flows/dispatcher/contract.md and flows/executors/contract.md. This is a topology
verification script, not a live executor migration test; current pilot flows still poll
SharePoint until dispatcher/executors are rewritten to use Service Bus actions.
#>

[CmdletBinding()]
param(
    [string]$EnvFile = '.env.production',
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$NamespaceName = $(if ($env:ITSM_SERVICEBUS_NAMESPACE) { $env:ITSM_SERVICEBUS_NAMESPACE } else { 'sb-itsm-demo-pilot' }),
    [string]$TopicName = $(if ($env:ITSM_SERVICEBUS_TOPIC) { $env:ITSM_SERVICEBUS_TOPIC } else { 'provisioning-jobs' })
)

$ErrorActionPreference = 'Stop'

if ($EnvFile -and (Test-Path -LiteralPath $EnvFile)) {
    & (Join-Path $PSScriptRoot '../../scripts/load-env.ps1') -Path $EnvFile | Out-Host
    if (-not $PSBoundParameters.ContainsKey('SubscriptionId') -and $env:AZURE_SUBSCRIPTION_ID) { $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID }
    if (-not $PSBoundParameters.ContainsKey('ResourceGroup') -and $env:AZURE_RESOURCE_GROUP) { $ResourceGroup = $env:AZURE_RESOURCE_GROUP }
    if (-not $PSBoundParameters.ContainsKey('NamespaceName') -and $env:ITSM_SERVICEBUS_NAMESPACE) { $NamespaceName = $env:ITSM_SERVICEBUS_NAMESPACE }
    if (-not $PSBoundParameters.ContainsKey('TopicName') -and $env:ITSM_SERVICEBUS_TOPIC) { $TopicName = $env:ITSM_SERVICEBUS_TOPIC }
}

az account set --subscription $SubscriptionId

$expectedSubscriptions = @(
    @{ Name = 'sub-identity'; Filter = "sys.Label LIKE 'identity.%'" },
    @{ Name = 'sub-groups'; Filter = "sys.Label LIKE 'groups.%'" },
    @{ Name = 'sub-licensing'; Filter = "sys.Label LIKE 'licensing.%'" },
    @{ Name = 'sub-exchange'; Filter = "sys.Label LIKE 'exchange.%'" },
    @{ Name = 'sub-sharepoint'; Filter = "sys.Label LIKE 'sharepoint.%'" },
    @{ Name = 'sub-teams'; Filter = "sys.Label LIKE 'teams.%' OR sys.Label LIKE 'endpoint.%'" }
)

$namespace = az servicebus namespace show `
    --resource-group $ResourceGroup `
    --name $NamespaceName `
    --query '{name:name,sku:sku.name,status:status,minimumTlsVersion:minimumTlsVersion}' `
    -o json | ConvertFrom-Json

$topic = az servicebus topic show `
    --resource-group $ResourceGroup `
    --namespace-name $NamespaceName `
    --name $TopicName `
    --query '{name:name,status:status,requiresDuplicateDetection:requiresDuplicateDetection,duplicateDetectionHistoryTimeWindow:duplicateDetectionHistoryTimeWindow,defaultMessageTimeToLive:defaultMessageTimeToLive,enablePartitioning:enablePartitioning}' `
    -o json | ConvertFrom-Json

$failures = [System.Collections.Generic.List[string]]::new()

if ($namespace.sku -ne 'Standard') { $failures.Add("Namespace SKU expected Standard, found $($namespace.sku)") }
if ($topic.requiresDuplicateDetection -ne $true) { $failures.Add('Topic duplicate detection is not enabled') }
if ($topic.duplicateDetectionHistoryTimeWindow -ne 'PT10M') { $failures.Add("Topic duplicate detection window expected PT10M, found $($topic.duplicateDetectionHistoryTimeWindow)") }
if ($topic.defaultMessageTimeToLive -ne 'P1D') { $failures.Add("Topic TTL expected P1D, found $($topic.defaultMessageTimeToLive)") }

$validated = @()
foreach ($expected in $expectedSubscriptions) {
    $sub = az servicebus topic subscription show `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --name $expected.Name `
        --query '{name:name,requiresSession:requiresSession,lockDuration:lockDuration,maxDeliveryCount:maxDeliveryCount,status:status}' `
        -o json | ConvertFrom-Json

    if ($sub.requiresSession -ne $true) { $failures.Add("$($expected.Name) does not require sessions") }
    if ($sub.lockDuration -ne 'PT5M') { $failures.Add("$($expected.Name) lock duration expected PT5M, found $($sub.lockDuration)") }
    if ([int]$sub.maxDeliveryCount -ne 5) { $failures.Add("$($expected.Name) max delivery count expected 5, found $($sub.maxDeliveryCount)") }

    $rules = az servicebus topic subscription rule list `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --topic-name $TopicName `
        --subscription-name $expected.Name `
        --query '[].{name:name,sql:sqlFilter.sqlExpression}' `
        -o json | ConvertFrom-Json

    $defaultRule = $rules | Where-Object { $_.name -eq '$Default' }
    if ($defaultRule) { $failures.Add("$($expected.Name) still has catch-all `$Default rule") }

    $filterRule = $rules | Where-Object { $_.name -eq 'jobtype-filter' } | Select-Object -First 1
    if (-not $filterRule) {
        $failures.Add("$($expected.Name) is missing jobtype-filter rule")
    } elseif ($filterRule.sql -ne $expected.Filter) {
        $failures.Add("$($expected.Name) filter expected [$($expected.Filter)], found [$($filterRule.sql)]")
    }

    $validated += [pscustomobject]@{
        Subscription = $expected.Name
        RequiresSession = [bool]$sub.requiresSession
        LockDuration = $sub.lockDuration
        MaxDeliveryCount = [int]$sub.maxDeliveryCount
        Filter = if ($filterRule) { $filterRule.sql } else { $null }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Service Bus topology validation failed with $($failures.Count) issue(s)."
}

[pscustomobject]@{
    Namespace = $namespace.name
    NamespaceSku = $namespace.sku
    Topic = $topic.name
    DuplicateDetection = $topic.duplicateDetectionHistoryTimeWindow
    DefaultMessageTimeToLive = $topic.defaultMessageTimeToLive
    SubscriptionsValidated = $validated.Count
    Subscriptions = $validated
} | ConvertTo-Json -Depth 5
