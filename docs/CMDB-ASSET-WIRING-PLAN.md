# CMDB And Asset Wiring Plan

**Status:** Retained-deferred  
**Applies to:** `Configuration Items` and `Assets` SharePoint lists  
**Day 4 impact:** No blocker

The ITSM schema intentionally keeps the `Configuration Items` and `Assets` lists even though they are not yet wired to the SPFx frontend or active Copilot Studio agent flows. They are part of the ServiceNow-style target model and are ready for future CMDB and asset-management phases.

## Current State

| List | Provisioning file | Current pilot use | Day 4 decision |
|---|---|---|---|
| `Configuration Items` | `infra/sharepoint/lists/02-configuration-items.ps1` | Empty CMDB list. Ticket schema includes `Tickets.CmdbCi` lookup, but frontend and agent do not yet populate it. | Retain. Not a Day 4 blocker. |
| `Assets` | `infra/sharepoint/lists/03-assets.ps1` | Empty asset inventory list. Schema supports assignment and CI linkage, but no frontend or flow currently reads/writes it. | Retain. Not a Day 4 blocker. |

The lists exist to preserve the target data model:

- Tickets can eventually link to affected services, applications, infrastructure, or devices through `Configuration Items`.
- Assets can eventually link physical or licensed inventory to CIs through `Assets.LinkedCi`.
- Approval policies can eventually use CI ownership for routing.
- Major incident and triage logic can eventually use CI relationships for better clustering, routing, and impact analysis.

## What Is Not Wired Yet

The following are intentionally deferred:

- No SPFx frontend surface for creating, browsing, or selecting Configuration Items.
- No SPFx frontend surface for creating, browsing, or selecting Assets.
- No active Submit Ticket CI picker.
- No active agent grounding source that reliably looks up live CIs during triage.
- No active asset lookup during request fulfillment.
- No asset-to-user device view in My Tickets or Admin views.
- No automated Intune, Entra, SharePoint, or ServiceNow import into either list.

This means Day 4 work can proceed without seeding CIs or Assets.

## Future Wiring Target

### Configuration Items

Target use:

1. Seed or import CIs for core business services, applications, infrastructure, sites, and shared platforms.
2. Expose CI lookup in Submit Ticket for incidents and changes.
3. Ground the Triage Agent on active CIs so it can resolve phrases such as "payroll is down" or "SharePoint finance site" to a known service or application.
4. Populate `Tickets.CmdbCi` during triage when confidence is high.
5. Use CI owner fields for routing and approval:
   - `BusinessOwner`
   - `TechnicalOwner`
6. Use parent/child CI relationships for major incident impact analysis.

Minimum future frontend behavior:

- Add `ConfigurationItemService`.
- Load active CIs with ID, title/name, class, status, owners, environment, and endpoint fields.
- Add searchable CI picker to Submit Ticket.
- Show affected CI in ticket details and admin ticket grids.

Minimum future agent behavior:

- Add live CI grounding or tool lookup for active CIs.
- Ask a clarifying question when multiple CIs match.
- Avoid inventing CIs not present in the list.
- Populate `CmdbCi` only when the match is sufficiently confident.

### Assets

Target use:

1. Import or maintain hardware, software-license, and subscription assets.
2. Link assets to users through `AssignedTo`.
3. Link assets to CIs through `LinkedCi`.
4. Support request and incident context such as "my assigned laptop", "monitor asset tag", or "license subscription".
5. Use asset state during fulfillment and troubleshooting:
   - In Stock
   - In Use
   - In Maintenance
   - In Transit
   - Retired
   - Disposed
   - Lost / Stolen

Minimum future frontend behavior:

- Add `AssetService`.
- Add Admin inventory view for asset search and filters.
- Add assigned asset panel on user/ticket context where appropriate.
- Allow service desk agents to link a ticket to an asset.

Minimum future agent behavior:

- Lookup assets by asset tag, serial number, assigned user, or linked CI.
- Use asset context to improve routing and troubleshooting.
- Ask for asset tag or device name when required.

## Relationship Model

```text
Configuration Items
  -> ParentCi: optional self-lookup for service dependency hierarchy

Assets
  -> LinkedCi: optional lookup to Configuration Items
  -> AssignedTo: optional user field

Tickets
  -> CmdbCi: optional lookup to Configuration Items
```

Example future chain:

```text
Ticket: "Finance payroll site is unavailable"
  -> CmdbCi = Payroll Portal
  -> ParentCi = Finance SharePoint Service
  -> TechnicalOwner = SharePoint Platform Owner
  -> Assets linked to CI = related licenses, subscriptions, or devices where applicable
```

## Day 4 Guidance

Do not remove these lists.

Do not block Day 4 pilot readiness on these lists being empty.

For Day 4, treat both lists as retained-deferred schema:

- They are valid provisioned lists.
- They are not required for ProposeAction deployment.
- They are not required for Adaptive Card notifications.
- They are not required for KB import.
- They are not required for subcategory frontend wiring.
- They are not required for license cost frontend wiring.
- They are not required for executor hardening.

Future phases should decide whether to seed manually first or import from source systems such as Intune, Entra ID, SharePoint, or an existing ServiceNow export.

