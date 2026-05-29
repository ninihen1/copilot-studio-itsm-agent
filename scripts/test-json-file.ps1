#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'
Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
[pscustomobject]@{
    Path = $Path
    Verdict = 'JSON_OK'
} | ConvertTo-Json
