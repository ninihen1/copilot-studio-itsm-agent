#Requires -Version 7.0

# License Costs list — per-SKU license pricing reference.
# Read by the License Lookup helper flow (license name/SKU -> pricing) and
# written by the scheduled License Costs sync (Microsoft official product name + skuId).
#
# Schema-as-code captured from the live /sites/ITSM list 2026-05-31. Supersedes
# ensure-license-costs-sync-schema.ps1, which only added the 3 sync-metadata
# fields (OfficialProductName, SkuId, SkuPartNumber); those are folded in below
# so this is the single source of truth for the list.
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-LicenseCostsList {
    param([string]$ListTitle = 'License Costs')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Per-SKU license pricing reference. Maps a Microsoft SKU (SkuPartNumber/SkuId) to the tenant display name and negotiated pricing. Read by the License Lookup helper flow; sync-metadata columns are written by the scheduled License Costs sync.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    # Title carries the tenant-facing product display name (e.g., "Microsoft 365 E5").
    # SkuPartNumber is the natural key; Title is the human label.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Product Display Name' } | Out-Null

    # --- Natural key + Microsoft SKU reference (also added by ensure-license-costs-sync-schema.ps1) ---
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='SkuPartNumber'; DisplayName='SKU Part Number'; Type='Text'; MaxLength=128
        Required=$true; Indexed=$true
        Description='Microsoft String_Id from the official SKU reference and Graph subscribedSku.skuPartNumber.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='SkuId'; DisplayName='SKU ID'; Type='Text'; MaxLength=64; Indexed=$true
        Description='GUID from the Microsoft SKU reference and Graph subscribedSku.skuId.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='OfficialProductName'; DisplayName='Official Product Name'; Type='Text'; MaxLength=255
        Description='Current Microsoft product name from the official SKU reference CSV. Do not use for tenant overrides.'
    }

    # --- Pricing ---
    # Plain Number (not SP Currency type) so the ISO code lives in the separate Currency column.
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='ListPriceMonthly'; DisplayName='List Price Monthly'; Type='Number'
        Description='Microsoft published list price per seat per month, in the Currency below.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='NegotiatedPriceMonthly'; DisplayName='Negotiated Price Monthly'; Type='Number'
        Description='Tenant negotiated/EA price per seat per month, in the Currency below. Falls back to list price when blank.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='Currency'; DisplayName='Currency'; Type='Choice'
        Choices=@('USD','AUD','EUR','GBP'); DefaultValue='USD'
        Description='ISO currency code the price columns are expressed in.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='BillingCycle'; DisplayName='Billing Cycle'; Type='Choice'
        Choices=@('Monthly','Annual','OneTime'); DefaultValue='Monthly'
        Description='Billing cadence the price reflects.'
    }

    # --- Provenance ---
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='LastVerified'; DisplayName='Last Verified'; Type='DateTime'
        Description='When the pricing was last confirmed against the source.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='SourceUrl'; DisplayName='Source URL'; Type='Text'; MaxLength=500
        Description='Link to the pricing source (Microsoft pricing page, EA quote, etc.).'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName='Notes'; DisplayName='Notes'; Type='Note'; RichText=$false
        Description='Free-text pricing notes (e.g., bundle exceptions, discount conditions).'
    }
}
