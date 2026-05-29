# SPFx Deployment Guide - ITSM Frontend

This guide covers the build and deployment pipeline for the ITSM SharePoint Framework (SPFx) frontend package.

## Defaults

| Setting | Value |
|---|---|
| SPFx toolchain | SPFx `1.22.x`, Heft-based |
| Node.js | `22.14.x` or another Node `22` LTS version supported by SPFx `1.22.x` |
| CI/CD | GitHub Actions |
| Deployment trigger | Manual `workflow_dispatch` for app catalog deployment |
| Deployment scope | Tenant-wide, `skipFeatureDeployment=true` |
| Tenant | `contoso.sharepoint.com` |
| ITSM site | `https://contoso.sharepoint.com/sites/ITSM` |
| App catalog | `https://contoso.sharepoint.com/sites/appcatalog` |

## Local Development Setup

Install Node.js `22` LTS, then install dependencies from the repository root:

```bash
npm install
```

Trust the local SPFx developer certificate:

```bash
npm run trust-dev-cert
```

Set the local workbench target:

```bash
export SPFX_SERVE_TENANT_DOMAIN=contoso.sharepoint.com/sites/ITSM
```

Run the local workbench server:

```bash
npm run start
```

Build and package locally:

```bash
npm run ci
```

Expected package output:

```text
sharepoint/solution/*.sppkg
```

Before packaging ticket-type validation changes, verify the Submit Ticket route:

- `SubmitIncidentView` exposes an explicit Incident/Request choice.
- `TicketService.createTicket()` writes dynamic `TicketType` and `TicketSource=Portal`.
- `TicketService.createIncident()` remains as a compatibility wrapper.
- The deployed package can read active Service Catalog rows needed for subcategory-to-catalog validation.

## Package Scripts

The root `package.json` follows the SPFx `1.22.2` Heft pattern used by the `vibe-sharepoint` reference project.

| Script | Purpose |
|---|---|
| `npm run clean` | Removes Heft/SPFx build outputs |
| `npm run build` | Runs production Heft test/build path |
| `npm run bundle` | Runs production Heft build |
| `npm run package` | Runs `heft package-solution --production` |
| `npm run ci` | Clean, build, bundle, and package for CI |
| `npm run start` | Starts the local SPFx workbench server |
| `npm run trust-dev-cert` | Trusts the local development certificate |

## SPFx Package Configuration

When the SPFx project is scaffolded or updated, confirm `config/package-solution.json` contains:

```json
{
  "solution": {
    "includeClientSideAssets": true,
    "skipFeatureDeployment": true,
    "isDomainIsolated": false
  },
  "paths": {
    "zippedPackage": "solution/itsm-frontend.sppkg"
  }
}
```

Use `skipFeatureDeployment=true` for the pilot so the app is available tenant-wide after deployment from the app catalog.

## GitHub Actions Pipeline

Workflow:

```text
.github/workflows/spfx-build-deploy.yml
```

Build behavior:

- Runs on PRs and pushes to `main` when SPFx files change.
- Installs dependencies with `npm ci` when `package-lock.json` exists, otherwise `npm install`.
- Runs `npm run ci`.
- Uploads `sharepoint/solution/*.sppkg` as the `spfx-sppkg` artifact.

Deploy behavior:

- Runs only from manual `workflow_dispatch`.
- Requires `deploy=true`.
- Uses the selected GitHub environment (`pilot` or `production`) for approval and secrets.
- Downloads the packaged artifact.
- Logs in with certificate auth using CLI for Microsoft 365.
- Uploads the `.sppkg` to the tenant app catalog.
- Deploys with `--skipFeatureDeployment`.

## Required GitHub Secrets

Configure these in the GitHub environment used by the workflow, initially `pilot`.

| Secret | Description |
|---|---|
| `M365_TENANT_ID` | Tenant ID. For contoso: `00000000-0000-4000-8000-000000000009` |
| `M365_APP_ID` | Azure AD app registration client ID used for deployment |
| `M365_CERT_BASE64` | Base64-encoded PFX certificate for the deployment app |
| `M365_CERT_PASSWORD` | PFX certificate password |

The workflow input `appCatalogUrl` defaults to:

```text
https://contoso.sharepoint.com/sites/appcatalog
```

## Certificate Handling

Do not commit certificates or passwords.

For GitHub Actions:

```bash
base64 -w 0 deploy-cert.pfx
```

Store the output in `M365_CERT_BASE64`, and store the PFX password in `M365_CERT_PASSWORD`.

For local PowerShell deployment, either set:

```text
M365_CERT_PATH=/path/to/deploy-cert.pfx
```

or:

```text
M365_CERT_BASE64=<base64 pfx>
```

## Manual Deployment Fallback

Build the package:

```bash
npm run ci
```

Deploy with CLI for Microsoft 365:

```powershell
./scripts/deploy-spfx.ps1 `
  -Tool CLI `
  -TenantId "00000000-0000-4000-8000-000000000009" `
  -AppId "<deployment-app-id>" `
  -AppCatalogUrl "https://contoso.sharepoint.com/sites/appcatalog" `
  -PackagePath "sharepoint/solution/itsm-frontend.sppkg" `
  -CertificatePath "<path-to-pfx>" `
  -CertificatePassword "<pfx-password>"
```

Deploy with PnP.PowerShell:

```powershell
./scripts/deploy-spfx.ps1 `
  -Tool PnP `
  -TenantId "00000000-0000-4000-8000-000000000009" `
  -AppId "<deployment-app-id>" `
  -AppCatalogUrl "https://contoso.sharepoint.com/sites/appcatalog" `
  -PackagePath "sharepoint/solution/itsm-frontend.sppkg" `
  -CertificatePath "<path-to-pfx>" `
  -CertificatePassword "<pfx-password>"
```

## App Catalog Setup

Confirm the tenant app catalog exists:

```text
https://contoso.sharepoint.com/sites/appcatalog
```

If it does not exist, create it from the SharePoint admin center:

```text
https://contoso-admin.sharepoint.com
```

Then open **More features > Apps > App Catalog**.

## Deployment Identity

Recommended: create a dedicated deployment app registration for SPFx package deployment rather than reusing runtime executor identities.

Minimum decision points:

- Whether the app can upload/deploy to the tenant app catalog.
- Whether tenant admin approval is required for every package update.
- Whether `pilot` and `production` should use separate app registrations/certificates.

## Post-Deploy Smoke Test

After deployment:

1. Open `https://contoso.sharepoint.com/sites/ITSM`.
2. Add or refresh the ITSM frontend web part/page.
3. Confirm the frontend loads without console errors.
4. Confirm calls to SharePoint lists are read-only unless the UX explicitly performs a user action.
5. Confirm no privileged Graph writes exist in the frontend.

## Known Current Limitation

This repository did not contain an SPFx scaffold at the time this pipeline was added. The workflow and scripts are ready for the SPFx project structure, but CI will only pass once the SPFx `config/`, `src/`, and `sharepoint/solution` scaffold are present and `heft package-solution --production` emits an `.sppkg`.
