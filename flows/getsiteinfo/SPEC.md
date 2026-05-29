# ITSM-Helper-GetSiteInfo

**Flow ID (Flow Studio Demo):** `00000000-0000-4000-8000-000000000052`
**Status:** Deployed + verified 2026-05-01T00:15 UTC
**Connector:** `shared_sharepointonline` (delegated user auth via existing `f1550c57...` connection)
**Purpose:** Give the Triage Agent a structured way to verify that a SharePoint site is internal and identify its owner, instead of guessing from URL patterns.

## Trigger

Anonymous HTTP request:
```json
POST <triggerUrl>
Content-Type: application/json
{ "siteUrl": "https://contoso.sharepoint.com/sites/DevJohn" }
```

The trigger URL is captured in the Power Automate portal under the flow's HTTP trigger details — bind it as an action in the agent or call from another flow.

## Response

```json
{
  "siteUrl": "https://contoso.sharepoint.com/sites/ITSM",
  "exists": true,
  "isInternal": true,
  "title": "ITSM",
  "description": "AI-augmented ServiceNow-style ITSM on M365",
  "ownerName": "ITSM Owners",
  "ownerEmail": "ITSM@contoso.onmicrosoft.com",
  "ownerUpn": null,
  "ownerLoginName": "c:0o.c|federateddirectoryclaimprovider|<groupId>_o",
  "errorMessage": ""
}
```

Field semantics:
- `exists` — true if the site responded to `_api/web`, false on 4xx/5xx.
- `isInternal` — `siteUrl` matches `contoso.sharepoint.com` OR contains `flowstudio.app` (verified tenant domains). Computed locally — does NOT require the SP call to succeed.
- `title`, `description` — from `_api/web?$select=Title,Description`.
- `ownerName`, `ownerEmail`, `ownerUpn`, `ownerLoginName` — from `_api/site/Owner`. For Group-connected sites the owner is an M365 group, not a user (so `ownerUpn` will be null and `ownerName` will be the group's name).
- `errorMessage` — populated on partial failure (Web succeeded, Owner failed) or full failure (Web failed).

## Action sequence

```
1. Compose IsInternal flag (string match on URL — independent of SP call)
2. GET /_api/web?$select=Title,Url,Description (delegated user auth)
   on success → step 3
   on failure → Response { exists: false, isInternal, errorMessage }
3. GET /_api/site/Owner?$select=Title,Email,LoginName,UserPrincipalName
   on success → Response with full payload
   on failure → Response with site basics + ownerName=null + errorMessage
```

## Why two REST calls

- `_api/web` returns Web object (Title, Description) but NOT Owner — Owner is a property of the SP **Site** (collection), not the Web.
- `_api/site/Owner` returns the Site's Owner User. For Group-connected sites this resolves to the M365 group (Title="<Group> Owners", Email=<group@tenant>).

## Response field handling — `body['d']` vs root

SharePoint REST returns `application/json; odata=verbose` by default, which wraps the payload under a `d` property. The flow uses `coalesce(body('Get_Web')?['d']?['Title'], body('Get_Web')?['Title'])` so it works whether the server replies in verbose or nometadata mode.

## Permissions

The flow runs as the SharePoint connection's authenticated user (`f1550c57...` = catherine.han@flowstudio.app). It can read any site that user has access to. Sites the user can't see return 4xx → `exists: false`. This is the desired behaviour — the agent should only see metadata for sites the caller could see anyway.

## Integration options for the Triage Agent

### Option 1: Add as connector action in Copilot Studio portal (recommended, ~5 min UI step)

1. Open Copilot Studio → Helpdesk Triage Agent → **Actions** → **Add an action**
2. Pick **Power Automate flow** → select `ITSM-Helper-GetSiteInfo`
3. Save. The agent's GenerativeActions orchestrator can now call it as a tool.
4. Add to agent instructions: *"When a caller mentions a SharePoint URL and you need to confirm it's internal or find its owner, call GetSiteInfo with the URL. Use the response's isInternal/ownerEmail/ownerName fields in your reasoning."*

### Option 2: Pre-process in the orchestrator flow (autonomous, requires flow changes)

Update `ITSM-Triage-Orchestrator` to detect SharePoint URLs in the ticket Description and accumulatedContext via regex, call GetSiteInfo for each, and prepend the metadata to the agent's prompt. No agent-side configuration needed.

This option duplicates effort if multiple URLs appear, and the agent doesn't get the lookup-on-demand semantics. Use only if Option 1 is blocked.

### Option 3: Manual portal connector action with ad-hoc binding

Same as Option 1 but bound at the topic level — wire it into a specific topic (e.g. `TriageFromFlow`) as a sub-action. More limited but cleaner if you want to control when the lookup fires.

## Test plan (manual)

```powershell
$url = '<trigger url from portal>'
$body = @{ siteUrl = 'https://contoso.sharepoint.com/sites/ITSM' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType 'application/json'
```

Expected: `exists=true, isInternal=true, title="ITSM", ownerName="ITSM Owners"`.

```powershell
$body2 = @{ siteUrl = 'https://microsoft.sharepoint.com/sites/random' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $url -Body $body2 -ContentType 'application/json'
```

Expected: `exists=false, isInternal=false`.

## Known limitations

1. **Group-connected sites** return the M365 group as Owner, not an individual user. To find the actual humans who can grant access, follow up with Graph `/groups/{id}/owners`. Future enhancement.
2. **The flow runs as one identity** (the connection's user). For accurate "can this caller access this site" checks, the flow would need to run delegated as the calling user — that requires either passing a user token through or building the action as agent-callable so Copilot Studio injects the caller's context.
3. **No caching.** Each call hits SP. For production, add a SharePoint list cache (siteUrl → metadata, TTL 1h).
4. **isInternal is hardcoded** to `contoso.sharepoint.com` and `flowstudio.app`. Update this list when verified tenant domains change. Long-term move to Config SP list.
