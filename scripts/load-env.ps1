#Requires -Version 5.1

<#
.SYNOPSIS
Loads key/value environment settings from an .env file into the current PowerShell process.

.DESCRIPTION
Used by deployment and validation scripts to keep tenant/site/resource identifiers
environment-specific without duplicating values in every command. Lines beginning
with # are ignored. Existing process environment variables are overwritten by
default so an explicit environment file is authoritative for that run.
#>

[CmdletBinding()]
param(
    [string]$Path = '.env.production',
    [switch]$NoClobber
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Environment file not found: $Path"
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$loaded = 0

foreach ($line in Get-Content -LiteralPath $resolved) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
        continue
    }

    $separatorIndex = $trimmed.IndexOf('=')
    if ($separatorIndex -le 0) {
        continue
    }

    $name = $trimmed.Substring(0, $separatorIndex).Trim()
    $value = $trimmed.Substring($separatorIndex + 1).Trim()

    if ($value.Length -ge 2) {
        $isQuoted = ($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))
        if ($isQuoted) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    if ($NoClobber -and [Environment]::GetEnvironmentVariable($name, 'Process')) {
        continue
    }

    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    $loaded++
}

[pscustomobject]@{
    Path = $resolved
    LoadedVariables = $loaded
}
