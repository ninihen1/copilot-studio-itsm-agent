# Helpdesk Triage Agent

The triage brain of the AI-augmented ITSM build. It classifies tickets, attempts knowledge-base deflection, resolves identity/CMDB context, and **proposes** privileged actions for human approval. It **never executes a privileged write** — the only thing it produces is a structured triage decision.

## Architecture — flow-drives-agent

Intake is **server-side, not conversational** (ADR [0002](../../decisions/0002-triage-approval-reconciliation.md)). The agent does not wait for a user to chat:

```
New SharePoint Tickets row
   ↓
ITSM-Triage-Orchestrator (Power Automate)  ── builds a [TRIAGE_REQUEST] payload
   ↓  calls the agent server-side
Helpdesk Triage Agent · TriageFromFlow topic
   ↓  returns ONE tagged JSON block  <<<TRIAGE_BEGIN>>> … <<<TRIAGE_END>>>
ITSM-Triage-Orchestrator  ── parses the JSON, creates the ticket + Provisioning Job
   ↓
Approval flow → JWT on full approval → Dispatcher → Service Bus → executor flows (the 6 SPs do the writes)
```

The orchestrator parses the agent's reply by **substring extraction** between the two delimiters, so `TriageFromFlow` is built to emit the JSON block and nothing else — no preamble, no markdown fences, no suggested actions.

The agent is **not** a user-facing chatbot and does **not** create tickets itself. It is invoked only by `ITSM-Triage-Orchestrator`, classifies the incoming ticket, and returns the JSON decision — the orchestrator performs every write (ticket, Provisioning Job, approval routing). The non-`TriageFromFlow` topics still present in the published agent (`Greeting`, `CreateTicket`, `CheckTicketStatus`, `SearchKnowledge`, plus the system defaults) are vestigial scaffolding from the original conversational design; they are not on the operative path.

## Status

**Deployed and live** in the Flow Studio Demo environment. Schema name `cre79_agent`. All tenant-specific values in this public copy are placeholders — `contoso.onmicrosoft.com`, `https://contoso.sharepoint.com`, zero-GUID tenant/environment IDs.

The retired pre-deploy model — an agent-callable `ProposeAction`/`LogHumanTicket` flow-action pair that let the agent write its own audit records — was removed under ADR 0002. The agent no longer holds any flow action; it only returns a decision the orchestrator acts on.

## File layout

| File | What it is |
|---|---|
| `README.md` | This file |
| `SPEC.md` | Canonical agent spec — the single source of truth for behaviour |
| `Helpdesk Triage Agent/agent.mcs.yml` | Agent manifest: full instructions, tenant identity, Work IQ guardrails, triage protocol; model hint `opus4-1` |
| `Helpdesk Triage Agent/settings.mcs.yml` | Channels (Teams, M365 Copilot), Integrated (M365 SSO) auth, GroupMembership access, GenerativeAIRecognizer |
| `Helpdesk Triage Agent/connectionreferences.mcs.yml` | 4 connection references (3 Work IQ MCP + SharePoint Online) |
| `Helpdesk Triage Agent/topics/*.mcs.yml` | 17 topics — 13 system defaults + 4 custom (`TriageFromFlow`, `CreateTicket`, `CheckTicketStatus`, `SearchKnowledge`) |
| `Helpdesk Triage Agent/actions/*.mcs.yml` | 4 actions: `SearchKnowledgeBase` (flow) + 3 Work IQ MCP servers (SharePoint, Teams, User) — read-only lookups; no privileged ITSM writes |
| `Helpdesk Triage Agent/knowledge/*.mcs.yml` | 6 knowledge sources (KnowledgeBase, Tickets, ConfigurationItems, Categories, ServiceCatalog, JobTypes) |
| `Helpdesk Triage Agent/icon.png` | Agent icon |

## Auth posture

**M365 SSO (Integrated), GroupMembership access policy.** The caller's UPN is required in every Work IQ lookup, and the Work IQ MCP tools run **delegated as the calling user** — so they only ever return data that caller is already entitled to see. Surfaces are Teams / M365 Copilot, all inside the M365 perimeter.

## Tools

All four actions are **read-only** and run **delegated as the calling user** — they only return data that caller is already entitled to. The Work IQ SharePoint and Teams MCP tools are curated to explicit read-only allow-lists (`UseSpecificTools`); write operations (file move / share / delete, channel-membership updates) were deliberately removed. The User/Me MCP exposes only read tools. None of them performs a **privileged ITSM write** (identity, group, licensing, mailbox) — those go only through the propose → approve → executor pipeline below.

| Tool | Purpose |
|---|---|
| `SearchKnowledgeBase` | Query the published KB SharePoint list for deflection candidates |
| Work IQ **SharePoint** MCP | Verify a site exists, find owner/libraries/items before proposing or asking |
| Work IQ **User** MCP | Resolve a user by name/partial match → UPN, manager, department (identity + approval routing) |
| Work IQ **Teams** MCP | Verify a team/channel, identify owners (for `teams.addMember` and channel-access requests) |

The agent reasons against the 6 knowledge sources as **grounding** (built-in semantic search) rather than calling a topic to query them. See `SPEC.md` for the Work IQ governance guardrails (no bulk enumeration, no volunteered security info, minimal-PII, scope-to-ticket, refusal expansion, confidentiality cascade).

## Privileged write boundary

The agent holds **no** write permission. Every privileged change flows:

```
Agent (TriageFromFlow) → JSON decision { outcome: propose, proposedAction: {jobType, args}, … }
      ↓
ITSM-Triage-Orchestrator → writes Provisioning Job row (Status=Proposed)
      ↓
Approval flow (flows/approval/spec.md) → JWT issued on full approval
      ↓
Dispatcher POST /provisioning/jobs (flows/dispatcher/contract.md)
      ↓
Service Bus → executor flows (flows/executors/contract.md) — the 6 SPs do the actual writes
```

Valid `jobType` values are fixed (see `SPEC.md`); the agent must not invent any. In v1 there is **no auto-approve** — every privileged write goes through the full approval policy regardless of confidence. KB-only deflection (sending a published article and stopping) is allowed without approval because no write occurs.

## Cross-references

- Architecture decision: [`decisions/0002-triage-approval-reconciliation.md`](../../decisions/0002-triage-approval-reconciliation.md)
- Dispatcher contract: [`flows/dispatcher/contract.md`](../../flows/dispatcher/contract.md)
- Approval flow spec: [`flows/approval/spec.md`](../../flows/approval/spec.md)
- Executor contract: [`flows/executors/contract.md`](../../flows/executors/contract.md)
- Canonical agent spec: [`SPEC.md`](SPEC.md)
