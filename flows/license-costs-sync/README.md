# ITSM-Scheduled-License-Costs-Sync

Scheduled Power Automate flow that keeps the SharePoint **License Costs** list aligned with Microsoft's official SKU reference.

## Source

The flow downloads Microsoft's official CSV from the Microsoft Entra licensing reference:

- Reference page: `https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference`
- CSV: `https://download.microsoft.com/download/e/3/e/00000000-0000-4000-8000-000000000050/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv`

Microsoft Graph `GET /subscribedSkus` is still useful for tenant inventory and seat counts, but it does not return portal-friendly product names. Microsoft documents the mapping separately in this CSV/reference table.

## Schedule

The flow runs weekly at 02:00 Sunday, Australia/Sydney time.

Weekly is deliberate. Microsoft describes the licensing reference as periodically updated reference data, not a real-time API. A daily run would work, but it adds connector churn without meaningful freshness benefit.

## SharePoint List Contract

Target list: `License Costs`

Existing columns used:

| Column | Purpose |
| --- | --- |
| `Title` | Tenant-facing display name. Preserved on existing rows so local naming overrides are not overwritten. |
| `SkuPartNumber` | Microsoft `String_Id`; same value Graph exposes as `subscribedSku.skuPartNumber`. |
| `LastVerified` | Updated to the sync run timestamp when a matching SKU is seen in the Microsoft CSV. |
| `Notes` | Preserved on existing rows. New rows get a short provenance note. |
| Pricing fields | Preserved. The Microsoft SKU CSV is not a pricing source. |

Additional sync metadata columns:

| Column | Type | Purpose |
| --- | --- | --- |
| `OfficialProductName` | Single line text | Current Microsoft product name from the CSV. |
| `SkuId` | Single line text | Microsoft GUID from the CSV; same value Graph exposes as `subscribedSku.skuId`. |

Run `infra/sharepoint/ensure-license-costs-sync-schema.ps1` before deploying the flow.

## Sync Behavior

The Microsoft CSV has one row per service plan, so the same SKU appears multiple times. The flow:

1. Downloads the CSV.
2. Splits rows and extracts:
   - `Product_Display_Name`
   - `String_Id`
   - `GUID`
3. Deduplicates by `String_Id`.
4. Looks for an existing `License Costs` row where `SkuPartNumber == String_Id`.
5. If found:
   - Updates `OfficialProductName`, `SkuId`, and `LastVerified`.
   - Preserves `Title`, `Notes`, `SourceUrl`, `ListPriceMonthly`, `NegotiatedPriceMonthly`, `Currency`, and `BillingCycle`.
6. If not found:
   - Creates a row with `Title = OfficialProductName`.
   - Sets `SkuPartNumber`, `OfficialProductName`, `SkuId`, `LastVerified`, and a provenance note.

This means tenant-specific overrides live in `Title`; Microsoft source-of-truth names live in `OfficialProductName`.

## Deployment

Deploy using the same Power Automate REST/FlowStudio process as the other flow definitions:

1. Ensure the SharePoint schema:

```powershell
./infra/sharepoint/ensure-license-costs-sync-schema.ps1 `
  -SiteUrl "https://contoso.sharepoint.com/sites/ITSM"
```

2. Create or update the Power Automate flow from `flows/license-costs-sync/definition.json`.

Suggested display name:

```text
ITSM-Scheduled-License-Costs-Sync
```

Required connection:

```text
shared_sharepointonline
```

The HTTP action does not require a custom connection.

## Follow-On Cleanup

`flows/license-lookup/definition.json` still contains `Compose_PartNumberToDisplayName`, a hardcoded SKU display-name map. After this sync flow is deployed and tested, refactor `license-lookup` to use `License Costs.OfficialProductName` / `Title` instead of that hardcoded map.
