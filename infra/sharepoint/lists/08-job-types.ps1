#Requires -Version 7.0

# JobTypes list — registry of automatable actions. Loaded by dispatcher at start-of-day.
# Source: flows/dispatcher/contract.md section 6
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-JobTypesList {
    param([string]$ListTitle = 'JobTypes')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Registry of automatable job types. Adding a row + extending dispatcher switch is how new automations are registered.' `
        -EnableVersioning $true -MajorVersionLimit 50 | Out-Null

    # Phase B dedupe: JobType column dropped — Title now carries the job-type identifier (e.g., identity.resetPassword).
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Job Type' } | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Category'; DisplayName='Category'; Type='Choice'; Choices=@('identity','groups','licensing','exchange','sharepoint','teams','endpoint'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RiskTier'; DisplayName='Risk Tier'; Type='Choice'; Choices=@('low','medium','high'); Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='DefaultPolicy'; DisplayName='Default Approval Policy'; Type='Lookup'; LookupList='Approval Policies'; LookupField='Title'; Required=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='InputSchema'; DisplayName='Input Schema'; Type='Note'; RichText=$false; Required=$true; Description='JSON Schema for the args object' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RequiredScopes'; DisplayName='Required Graph Scopes'; Type='Note'; RichText=$false; Description='Newline-separated Graph permissions needed' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CompensationJobType'; DisplayName='Compensation Job Type'; Type='Text'; MaxLength=64; Description='The inverse jobType, or empty if not compensable' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='JobStatus'; DisplayName='Status'; Type='Choice'; Choices=@('active','deprecated'); Required=$true; Indexed=$true; DefaultValue='active' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OwningTeam'; DisplayName='Engineering Owner'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false; Description='Plain-language description used by the agent during proposal' }
}

