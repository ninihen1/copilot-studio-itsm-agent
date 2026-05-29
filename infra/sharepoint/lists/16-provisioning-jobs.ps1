#Requires -Version 7.0

# Provisioning Jobs list — audit row per privileged write.
# Source: flows/dispatcher/contract.md §3 + flows/executors/contract.md §5
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ProvisioningJobsList {
    param([string]$ListTitle = 'Provisioning Jobs')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Audit row per privileged write. Created by ProposeAction (Status=Proposed), updated by Approval and Dispatcher and Executor as the job progresses.' `
        -EnableVersioning $true -MajorVersionLimit 50 | Out-Null

    # Phase B dedupe: JobId column dropped — Title now carries the PJ-{ULID} job id.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Job ID' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='JobType'; DisplayName='Job Type'; Type='Text'; Required=$true; Indexed=$true; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentTicket'; DisplayName='Ticket'; Type='Lookup'; LookupList='Tickets'; LookupField='TicketNumber'; Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentRitm'; DisplayName='Request Item'; Type='Lookup'; LookupList='Request Items'; LookupField='RitmNumber' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='JobStatus'; DisplayName='Status'; Type='Choice'; Choices=@('Proposed','AwaitingApproval','Rejected','DispatchRejected','DispatchFailed','Dispatched','Queued','InProgress','Succeeded','Failed','Compensated','DeadLettered','Cancelled'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CallerUpn'; DisplayName='Caller UPN'; Type='Text'; Required=$true; Indexed=$true; MaxLength=256 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='TargetJson'; DisplayName='Target (JSON)'; Type='Note'; RichText=$false; Required=$true; Description='{ type, upn, id }' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ArgsJson'; DisplayName='Args (JSON)'; Type='Note'; RichText=$false; Description='Job-specific args object' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='IdempotencyKey'; DisplayName='Idempotency Key'; Type='Text'; Required=$true; Indexed=$true; MaxLength=128 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CorrelationId'; DisplayName='Correlation ID'; Type='Text'; Required=$true; Indexed=$true; MaxLength=64 }

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='AwaitingApprovalAt'; DisplayName='Awaiting Approval At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DispatchedAt'; DisplayName='Dispatched At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='StartedAt'; DisplayName='Started At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CompletedAt'; DisplayName='Completed At'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DurationMs'; DisplayName='Duration (ms)'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ServicePrincipal'; DisplayName='Service Principal'; Type='Text'; MaxLength=64; Description='Which executor SP did the write' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='GraphRequestId'; DisplayName='Graph Request ID'; Type='Text'; MaxLength=128; Description='x-ms-correlation-id from Graph response' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ResultJson'; DisplayName='Result (JSON)'; Type='Note'; RichText=$false; Description='Truncated to 4000 chars; full body in App Insights' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ErrorJson'; DisplayName='Error (JSON)'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RetryCount'; DisplayName='Retry Count'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Confidence'; DisplayName='Confidence'; Type='Number'; Description='0-1 — agent self-assessment' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Risk'; DisplayName='Risk'; Type='Choice'; Choices=@('low','medium','high') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Rationale'; DisplayName='Rationale'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CompensationJobId'; DisplayName='Compensation Job ID'; Type='Text'; MaxLength=64 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ApprovalSessionId'; DisplayName='Approval Session ID'; Type='Text'; Indexed=$true; MaxLength=64 }
}

