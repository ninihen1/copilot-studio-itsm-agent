#Requires -Version 7.0

<#
.SYNOPSIS
Seeds the Priority Matrix list with the 9 OOB Impact x Urgency rows.
Idempotent — re-runs are no-ops if the same Key already exists.

.PARAMETER SiteUrl
ITSM site URL.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [Parameter(Mandatory)][string]$CertificateName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')
Connect-ItsmTenant -SiteUrl $SiteUrl -AppId $AppId -KeyVaultName $KeyVaultName -CertificateName $CertificateName

# Standard ServiceNow OOB matrix.
# Response/resolution hours are illustrative starting points — Catherine should tune in production.
$rows = @(
    @{ Key='1-1'; Impact='1 - High';   Urgency='1 - High';   Priority='1 - Critical';  ResponseHours=1;  ResolutionHours=4   },
    @{ Key='1-2'; Impact='1 - High';   Urgency='2 - Medium'; Priority='2 - High';      ResponseHours=2;  ResolutionHours=8   },
    @{ Key='1-3'; Impact='1 - High';   Urgency='3 - Low';    Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
    @{ Key='2-1'; Impact='2 - Medium'; Urgency='1 - High';   Priority='2 - High';      ResponseHours=2;  ResolutionHours=8   },
    @{ Key='2-2'; Impact='2 - Medium'; Urgency='2 - Medium'; Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
    @{ Key='2-3'; Impact='2 - Medium'; Urgency='3 - Low';    Priority='4 - Low';       ResponseHours=8;  ResolutionHours=48  },
    @{ Key='3-1'; Impact='3 - Low';    Urgency='1 - High';   Priority='3 - Moderate';  ResponseHours=4;  ResolutionHours=24  },
    @{ Key='3-2'; Impact='3 - Low';    Urgency='2 - Medium'; Priority='4 - Low';       ResponseHours=8;  ResolutionHours=48  },
    @{ Key='3-3'; Impact='3 - Low';    Urgency='3 - Low';    Priority='5 - Planning';  ResponseHours=24; ResolutionHours=120 }
)

Write-Host "`n=== Seeding Priority Matrix ===" -ForegroundColor Cyan
foreach ($row in $rows) {
    $existing = Get-PnPListItem -List 'Priority Matrix' -Query @"
<View><Query><Where><Eq><FieldRef Name='Key'/><Value Type='Text'>$($row.Key)</Value></Eq></Where></Query></View>
"@ -ErrorAction SilentlyContinue

    if ($existing) {
        Write-StateLine -State 'NO-CHANGE' -Object "PriorityMatrix.$($row.Key)" -Detail "(exists)"
    } else {
        Add-PnPListItem -List 'Priority Matrix' -Values @{
            Title           = $row.Key
            Impact          = $row.Impact
            Urgency         = $row.Urgency
            Priority        = $row.Priority
            ResponseHours   = $row.ResponseHours
            ResolutionHours = $row.ResolutionHours
        } | Out-Null
        Write-StateLine -State CREATED -Object "PriorityMatrix.$($row.Key)" -Detail "$($row.Priority) (resp=$($row.ResponseHours)h, res=$($row.ResolutionHours)h)"
    }
}

Disconnect-PnPOnline
Write-Host "`nPriority Matrix seeded." -ForegroundColor Green
