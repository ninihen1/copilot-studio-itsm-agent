#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -like '*operational-regression.cjs*' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force
        [pscustomobject]@{
            Stopped = $_.ProcessId
            CommandLine = $_.CommandLine
        }
    } |
    ConvertTo-Json -Depth 3
