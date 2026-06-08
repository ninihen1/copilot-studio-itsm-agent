#Requires -Version 7.0

# Catalog Demand list — out-of-catalog demand log.
# Written by the RITM-Validation-Triage flow (Create_CatalogDemand) whenever a
# request can't be matched to an automatable catalog action and is handed off to
# the IT Service Desk queue. Each row is a signal: a thing people asked for that
# the catalog doesn't (yet) automate. Triage the DemandStatus column to decide
# what to onboard next.
#
# Schema-as-code captured from the live /sites/ITSM list and the flow's
# Create_CatalogDemand action 2026-06-08.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-CatalogDemandList {
    param([string]$ListTitle = 'Catalog Demand')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Out-of-catalog demand log. One row per request the automation could not fulfil and handed off to the IT Service Desk queue. Written by the RITM-Validation-Triage flow; triage DemandStatus to decide what to onboard into the catalog next.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    # Title carries a human summary the flow composes as "<RITM#> - <resource>".
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Demand Summary' } | Out-Null

    # --- What was asked for ---
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='RequestedItem'; DisplayName='Requested Item'; Type='Text'; MaxLength=255
        Description='Catalog item name if one was matched, otherwise the originating ticket title.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='ResourceName'; DisplayName='Resource Name'; Type='Text'; MaxLength=255
        Description='The specific resource the requester named (license SKU, group, app, etc.), parsed from the request.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='JobTypeGuess'; DisplayName='Job Type Guess'; Type='Text'; MaxLength=128
        Description="The agent's best guess at the JobType this demand would map to if automated. Blank when it could not be inferred."
    }

    # --- Who / which request ---
    # Requester is the UPN claim (text), not a People column — the flow writes the
    # raw claim suffix from RequestedFor, which may be an app-only or system identity.
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='Requester'; DisplayName='Requester'; Type='Text'; MaxLength=255
        Description='UPN of the person who made the request (text, taken from the RITM RequestedFor claim).'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='RitmRef'; DisplayName='RITM Ref'; Type='Text'; MaxLength=64; Indexed=$true
        Description='The RITM number the demand came from, for back-tracing to the request and ticket.'
    }

    # --- Triage ---
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='DemandStatus'; DisplayName='Demand Status'; Type='Choice'
        Choices=@('New','Reviewing','Onboarded','Declined'); DefaultValue='New'
        Description='Where this demand sits in review. New -> Reviewing -> Onboarded (added to the catalog) or Declined.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='DemandNotes'; DisplayName='Demand Notes'; Type='Note'; RichText=$false
        Description="Free-text context — the agent's summary of what was wanted, plus any reviewer notes."
    }
}
