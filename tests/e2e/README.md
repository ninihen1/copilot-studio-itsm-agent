# ITSM Frontend E2E Tests

These Playwright tests smoke-test the deployed SPFx frontend:

```text
https://contoso.sharepoint.com/sites/ITSM/SitePages/Home.aspx
```

## One-Time Auth Setup

Run from Windows PowerShell so the headed browser can complete Microsoft sign-in:

```powershell
npm run test:e2e:auth
```

Complete the Microsoft login in the browser window. When the ITSM app loads, the script writes:

```text
.auth/sharepoint.json
```

This file contains browser auth state and must not be committed.

## Run Tests

Headless:

```powershell
npm run test:e2e
```

Headed:

```powershell
npm run test:e2e:headed
```

Open the HTML report:

```powershell
npm run test:e2e:report
```

## What The Smoke Tests Cover

- ITSM portal shell loads.
- SharePoint data renders without `SharePoint GET failed`.
- SharePoint chrome is hidden from the app experience.
- Primary navigation works: Home, My tickets, Service catalog, Knowledge base, Approvals, Admin.
- Submit Ticket validation covers Incident vs Request selection, catalog-mapped mismatch prompts, Request-without-catalog blocking, and backward-compatible Incident submission.
- A screenshot is saved to `test-results/itsm-home.png`.

Ticket-type validation regressions should also capture SharePoint row evidence for `TicketTypeValidated`, `TicketTypeValidationStatus`, `SuggestedTicketType`, and `TicketTypeValidationReason`, plus flow run IDs for validator and downstream guard behavior.

## Overrides

Use a different page URL:

```powershell
$env:ITSM_FRONTEND_URL = "https://contoso.sharepoint.com/sites/ITSM/SitePages/Home.aspx"
npm run test:e2e
```

Use a different auth-state file:

```powershell
$env:PLAYWRIGHT_STORAGE_STATE = ".auth/catherine-sharepoint.json"
npm run test:e2e
```
