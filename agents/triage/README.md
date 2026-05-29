# Helpdesk Triage Agent

The triage agent for the AI-augmented ITSM build. It classifies tickets, attempts knowledge-base deflection, and proposes actions for human approval. **Never executes privileged writes.**

> ⚠ **Partially superseded (2026-05-30, ADR 0002).** Intake is **flow-drives-agent**: the `ITSM-Triage-Orchestrator` flow calls the agent server-side on each new ticket and acts on its reply — the agent is not a user-facing chatbot. The agent-callable **`ProposeAction`** flow/action was **retired**; references to it below are historical.

## Status (2026-04-29, late evening — overnight build)

**Locally authored.** All `.mcs.yml` files have been authored from `SPEC.md` and live under `Helpdesk Triage Agent/`. Schema name placeholder = `cr1c2_helpdesktriage`. SharePoint URLs in knowledge sources contain `https://contoso.sharepoint.com/...` placeholders. Connection reference logical names in `actions/*.mcs.yml` end in `.PLACEHOLDER`.

**Cannot be pushed as-is.** Three substitutions are required first (in this order):
1. Catherine creates the agent in the **Flow Studio Demo** environment via https://make.powerapps.com → Copilot Studio → New agent → name "Helpdesk Triage Agent". She notes the assigned schemaName (e.g., `crXXX_helpdesktriage`).
2. SharePoint provisioning script has run and the real tenant URL is known.
3. The two Power Automate flows (`ITSM-ProposeAction`, `ITSM-LogHumanTicket`) are deployed and connection references generated in the agent's environment.

Power Automate flow actions must also be in a named unmanaged solution before Copilot Studio can bind them. Default solution containers are not enough. If publish reports `CloudFlow ... not found` for an `InvokeFlowAction` / `InvokeFlowTaskAction`, check the flow's Dataverse `solutioncomponents` membership and add the workflow component to a named solution such as `FS Demo`. Cloud flows are solution component type `29`; for `ITSM-ProposeAction`, the Dataverse workflow ID is `00000000-0000-4000-8000-000000000036`.

After those three are in place, run a one-shot find-and-replace across all `.mcs.yml` files:
- `cr1c2_helpdesktriage` → real schemaName from step 1
- `https://contoso.sharepoint.com` → real tenant URL from step 2
- `cr1c2_helpdesktriage.shared_powerautomate_proposeaction.PLACEHOLDER` → real connection reference logical name from step 3
- `cr1c2_helpdesktriage.shared_powerautomate_loghumanticket.PLACEHOLDER` → real connection reference logical name from step 3

Then validate with `/copilot-studio:validate` and push with `/copilot-studio:Copilot Studio Manage` sync push.

## File layout

| File | What it is | Status |
|---|---|---|
| `README.md` | This file | Done |
| `SPEC.md` | Canonical agent spec (single source of truth — translate to YAML from here) | Done |
| `topics.outline.md` | Node-by-node sketches of all 8 topics with Power Fx and conditions | Done |
| `tools.stubs.md` | 8 tool contracts + canned stub responses | Done |
| `evals/*.json` | 5 eval scenarios in Copilot Studio Kit format | Done |
| `Helpdesk Triage Agent/agent.mcs.yml` | Agent manifest with full instructions | Authored (placeholder schemaName) |
| `Helpdesk Triage Agent/settings.mcs.yml` | Channels (Teams, M365 Copilot), auth (Integrated SSO), schemaName | Authored (placeholder schemaName) |
| `Helpdesk Triage Agent/topics/*.mcs.yml` | 14 topics (9 system + 5 custom) | Authored |
| `Helpdesk Triage Agent/actions/*.mcs.yml` | 2 actions: `ProposeAction`, `LogHumanTicket` | Authored (placeholder connection refs) |
| `Helpdesk Triage Agent/knowledge/*.mcs.yml` | 6 knowledge sources (KB, Tickets, CIs, Categories, Service Catalog, JobTypes) | Authored (placeholder URLs) |

## How to clone (do this before asking me to author YAML)

1. **Create empty agent in the portal:**
   - https://make.powerapps.com → switch to dev environment → Copilot Studio → New agent → Configure
   - Name: `Helpdesk Triage Agent`
   - Enable **Authenticate with Microsoft** at creation time
   - Save (no need to add anything yet — empty agent is fine)
2. **Clone via VS Code Copilot Studio extension:**
   - Open the extension panel
   - Clone agent → select `Helpdesk Triage Agent` → target `c:/Users/ninih/GitHub/Copilot Studio/agents/triage/`
3. **Notify Claude.** Once `agent.mcs.yml` exists in this folder, the YAML can be authored from `SPEC.md` and validated.

## Auth posture

**M365 SSO (integrated).** Reasons:
- Caller UPN is required in every tool call (per design memo §4.1) — only available with M365 SSO
- Surfaces are Teams / Outlook / Service Portal — all in the M365 perimeter
- DirectLine would require manual UPN passing and lose the Conditional Access integration

## Privileged write boundary

The agent **never** holds Graph write permissions. All proposed writes flow:

```
Agent → ProposeAction tool → Request ticket/RITM path or Incident + Provisioning Job path
      ↓
   Approval flow (separate Power Automate flow — see flows/approval/spec.md)
      ↓
   JWT issued on full approval
      ↓
   Dispatcher (POST /provisioning/jobs) — see flows/dispatcher/contract.md
      ↓
   Service Bus → executor flows (the 6 SPs do the actual writes)
```

The agent's 8 tools are read-only or proposal-write only. None call Microsoft Graph for privileged operations. `ProposeAction` stamps `TicketSource=ProposeAction`; downstream ticket-type validation and triage guards must preserve that source-specific behavior.

## What's stubbed today

All 8 tools return canned data. The SP lists they will eventually read from (`Tickets`, `Categories`, `Configuration Items`, `Knowledge Base`, `Service Catalog`) are scripted in `infra/sharepoint/` but not yet provisioned to a tenant. See `tools.stubs.md` for each tool's stub shape and the swap-to-real-data plan.

## Eval test cases

5 scenarios in `evals/`. Run via the Copilot Studio Kit eval harness (Dataverse-backed) or via `/copilot-studio:run-tests` once the agent is published.

| # | File | Scenario |
|---|---|---|
| 1 | `evals/01-password-reset-deflected.json` | KB deflection succeeds, no ticket created |
| 2 | `evals/02-password-reset-not-deflected.json` | KB tried but failed, ticket created and reset proposed |
| 3 | `evals/03-bulk-refusal.json` | Reset for 50 users → refused (>5 user limit) |
| 4 | `evals/04-ambiguous-ci.json` | "system is down" → agent asks which system |
| 5 | `evals/05-major-incident-pattern.json` | Outage symptoms → routes to human queue |

## Cross-references

- Design memo: `../../itsm-design-memo.docx` §4.1
- Dispatcher contract: `../../flows/dispatcher/contract.md`
- Approval flow spec: `../../flows/approval/spec.md`
- Executor contract: `../../flows/executors/contract.md`
- Identity model: `C:/Users/ninih/.claude/projects/c--Users-ninih-GitHub-Copilot-Studio/memory/project_itsm_identity_model.md`
