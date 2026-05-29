param(
    [string]$EnvironmentName = "00000000-0000-4000-8000-000000000045",
    [Parameter(Mandatory = $true)]
    [string]$FlowId,
    [int]$Top = 10,
    [string]$OutPath
)

$ErrorActionPreference = "Stop"

$token = az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }
$uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowId/runs?api-version=2016-11-01"

$runs = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value |
    Select-Object -First $Top |
    ForEach-Object {
        [pscustomobject]@{
            name = $_.name
            status = $_.properties.status
            startTime = $_.properties.startTime
            endTime = $_.properties.endTime
            triggerName = $_.properties.trigger.name
        }
    }

$result = [pscustomobject]@{
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    environmentName = $EnvironmentName
    flowId = $FlowId
    runs = @($runs)
}

$json = $result | ConvertTo-Json -Depth 10
if ($OutPath) {
    $fullPath = Join-Path (Get-Location) $OutPath
    $directory = Split-Path -Parent $fullPath
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    Set-Content -Path $fullPath -Value $json -Encoding UTF8
}

$json
