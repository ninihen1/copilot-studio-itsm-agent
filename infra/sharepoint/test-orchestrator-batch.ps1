#Requires -Version 7.0
# Test the ITSM-Triage-Orchestrator across multiple ticket categories.
# Inserts a batch of Tickets rows; the orchestrator (3-min polling) will pick them up.

. (Join-Path $PSScriptRoot 'lists/_helpers.ps1')

$siteUrl = 'https://contoso.sharepoint.com/sites/ITSM'
Connect-ItsmTenantPilot -SiteUrl $siteUrl

$callerEmail = 'catherine.han@flowstudio.app'
# Ensure user exists in the site's user info list
$user = New-PnPUser -LoginName $callerEmail -ErrorAction SilentlyContinue
if (-not $user) { $user = Get-PnPUser -Identity $callerEmail }
Write-Host "Using Caller: $($user.Email) (LookupId $($user.Id))" -ForegroundColor Cyan

$now = Get-Date -AsUTC
$cases = @(
    @{
        Tag = 'reset-pw'
        ShortDescription = "I forgot my password and locked out of my account"
        Description = "Cannot sign in to M365. Forgot password. Need to reset."
        ExpectedOutcome = 'propose'
        ExpectedJobType = 'identity.resetPassword'
    },
    @{
        Tag = 'disable-user'
        ShortDescription = "Please disable John Smith's account, he left the company today"
        Description = "John Smith (john.smith@flowstudio.app) was offboarded today. Please disable AD account and revoke licenses."
        ExpectedOutcome = 'propose'
        ExpectedJobType = 'identity.disableUser'
    },
    @{
        Tag = 'add-to-group'
        ShortDescription = "Add me to the Marketing security group"
        Description = "I just transferred to Marketing. Please add catherine.han@flowstudio.app to the Marketing-AllStaff security group."
        ExpectedOutcome = 'propose'
        ExpectedJobType = 'groups.addMember'
    },
    @{
        Tag = 'assign-license'
        ShortDescription = "Need a Power BI Pro license for our new analyst Jane Doe"
        Description = "Jane Doe (jane.doe@flowstudio.app) is starting in the analytics team. Please assign her a Power BI Pro license."
        ExpectedOutcome = 'propose'
        ExpectedJobType = 'licensing.assign'
    },
    @{
        Tag = 'vague'
        ShortDescription = "I need help"
        Description = "Something is wrong. Help."
        ExpectedOutcome = 'stop_and_ask'
        ExpectedJobType = $null
    },
    @{
        Tag = 'ambiguous-target'
        ShortDescription = "Bob's email isn't working"
        Description = "Bob from sales says he can't send email. Can you check?"
        ExpectedOutcome = 'stop_and_ask'
        ExpectedJobType = $null
    },
    @{
        Tag = 'bulk-refusal'
        ShortDescription = "Reset passwords for the entire engineering team"
        Description = "All 12 engineers have password issues after the SSO migration. Please reset everyone's passwords at once."
        ExpectedOutcome = 'stop_and_ask'  # Should refuse bulk; agent will likely fall to stop_and_ask
        ExpectedJobType = $null
    }
)

$results = @()
foreach ($c in $cases) {
    $ticketNumber = "INC$($now.ToString('yyMMddHHmm'))$($c.Tag.Substring(0,[Math]::Min(5,$c.Tag.Length)))"
    Write-Host "`n--- Inserting test ticket: $($c.Tag) -> $ticketNumber" -ForegroundColor Yellow

    try {
        $values = @{
            Title = $ticketNumber
            TicketNumber = $ticketNumber
            TicketType = 'Incident'
            ShortDescription = $c.ShortDescription
            Description = $c.Description
            TicketState = 'New'
            Caller = $callerEmail
            Impact = '3 - Low'
            Urgency = '3 - Low'
            OpenedDate = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
            ConfidentialityLevel = 'Public'
        }
        $item = Add-PnPListItem -List 'Tickets' -Values $values
        Write-Host "  Created SP item ID $($item.Id) - TicketNumber $ticketNumber" -ForegroundColor Green
        $results += [pscustomobject]@{
            Tag = $c.Tag
            TicketNumber = $ticketNumber
            SpItemId = $item.Id
            ExpectedOutcome = $c.ExpectedOutcome
            ExpectedJobType = $c.ExpectedJobType
            ShortDescription = $c.ShortDescription
        }
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | Format-Table Tag, TicketNumber, SpItemId, ExpectedOutcome, ExpectedJobType -AutoSize

# Save manifest for later verification
$manifestPath = Join-Path $PSScriptRoot '..\..\flows\triage-orchestrator\test-batch-manifest.json'
$results | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding utf8
Write-Host "`nManifest saved to: $manifestPath" -ForegroundColor Cyan
Write-Host "Wait ~3-5 minutes for the orchestrator to process all tickets, then check runs." -ForegroundColor Cyan
