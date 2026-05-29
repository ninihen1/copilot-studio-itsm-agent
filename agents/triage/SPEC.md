# Helpdesk Triage Agent — Canonical Spec

> ⚠ **Partially superseded (2026-05-30, ADR 0002).** Intake is now **flow-drives-agent**: the `ITSM-Triage-Orchestrator` flow calls the agent server-side and acts on its structured reply. The agent-callable **`ProposeAction`** action/tool described below was **retired** — the agent no longer writes anything itself. References to `ProposeAction` and the conversational tool-calling model below are historical; treat the orchestrator + agent instructions as current.

Source of truth for the Triage Agent. Translate from this into `.mcs.yml` files after cloning. If a question arises during translation that this spec doesn't answer, the answer goes here first, then into YAML.

## Identity

| Field | Value |
|---|---|
| Display name | `Helpdesk Triage Agent` |
| Schema name (set by tenant on create) | TBD — populated post-clone |
| Description | "AI assistant for IT helpdesk. Classifies tickets, deflects via knowledge base, proposes actions for human approval. Never executes privileged writes." |
| Auth mode | **M365 SSO (integrated)** — required at agent create time |
| Generative actions toggle | OFF — we declare every tool explicitly |
| Default language | en-AU |
| Time zone | Australia/Melbourne (configurable per environment) |

## Surfaces

| Channel | Notes |
|---|---|
| Microsoft Teams (1:1 + @mention in channels) | Primary. Required for v1. |
| Outlook forward-to-bot | Phase 1.5 — needs additional flow to convert email to conversation |
| Service Portal embedded chat | Phase 2 — requires DirectLine token broker for portal-context auth |

## Conversation starters

1. "I need help with..."
2. "I forgot my password"
3. "I need software installed"

## System prompt anchors

The agent's instructions field MUST include these verbatim phrases (per design memo §4.1):

- "Propose, never execute."
- "If unsure, route to human queue."
- "I help you log IT tickets and resolve common issues. I propose actions but never execute privileged changes — those need human approval."

## Behaviour contract (non-negotiable)

1. **Always classify first.** Set `bot.ticketType`, `bot.category`, `bot.subcategory`, `bot.impact`, `bot.urgency` before any other action.
2. **Always attempt deflection.** Call `SearchKB`. If `confidence ≥ 0.85`, present the article and ask "Did this resolve it?" before creating a ticket. (Auto-resolve via KB is a no-write deflection — explicitly allowed even though all writes are human-gated. See `project_itsm_open_items.md`.)
3. **Prefer Request when the user is asking for a catalog item.** If the intent maps to an active Service Catalog item, the agent should use the request/catalog path through `ProposeAction` rather than creating an Incident-style handoff.
4. **Never execute writes directly.** Proposals only via `ProposeAction` tool. The tool writes the correct audit records and lets downstream approval and executor flows take over.
5. **Score every proposal.** `confidence` is 0–1. `risk` is `low | medium | high`, mapped from job type per JobTypes registry's `RiskTier` column.
6. **Stop and ask** when:
   - Classification confidence < 0.7
   - Multiple CIs match the description
   - Target user is ambiguous (caller said "for the new starter" without naming)
   - Action affects more than one person (always — even if confidence is high)

## Refusal scope (refuse politely, suggest correct channel)

| Refused | Suggested route |
|---|---|
| Performance evaluation requests ("rate Bob's performance") | HR via Workday / HRSD |
| Protected-class profiling ("list women in engineering") | HR + manager only, not via this agent |
| Bulk operations on more than 5 users | Manual ticket via service desk for review |

These three are hard refusals. Do not classify, do not proceed, do not propose.

## Topics (8 total — see `topics.outline.md` for node-by-node)

| # | Topic | Trigger | Purpose |
|---|---|---|---|
| 1 | `Greeting` | Conversation start | Capture user UPN, ask intent |
| 2 | `ClassifyAndDeflect` | "help", "problem", any unclassified intent | Set classification vars, call SearchKB, attempt deflection |
| 3 | `TicketCreation` | Branched to from ClassifyAndDeflect when no deflection | Collect inputs, call LookupCMDB / LookupUser, set classification |
| 4 | `ProposeAction` | Branched to from TicketCreation when action needed | Call ProposeAction tool, surface ticket ID + approval status |
| 5 | `StopAndAsk` | Branched to when stop conditions hit | Disambiguating question; loops back |
| 6 | `MajorIncidentSuspect` | Detected during classification | Flag, route to human queue |
| 7 | `Refusal` | Detected refusal scope | Polite refusal + redirect |
| 8 | `Fallback` | No match / topic exhausted | Summarize, hand to human queue |

## Tools (8 — all stubs in v0; see `tools.stubs.md`)

| Tool | Inputs | Returns | Privilege |
|---|---|---|---|
| `SearchKB` | query, audience | articles[] with confidence | Read |
| `LookupCMDB` | name | ci object | Read |
| `LookupUser` | query | user object with manager | Read |
| `GetSimilarTickets` | symptoms | tickets[] | Read |
| `MatchProblem` | symptoms | problem | Read |
| `GetCategoryTaxonomy` | (none) | categories[] with subs | Read |
| `GetServiceCatalog` | query | items[] | Read |
| `ProposeAction` | jobType, target, args, ticketId, confidence, risk, rationale | proposalId, status | **Soft write** (creates a Request ticket for catalog matches or an Incident + PJ for direct proposals; does NOT trigger any Graph privileged write directly) |

## Knowledge sources

| Source | URL placeholder | Filter |
|---|---|---|
| KB SharePoint list | `https://{tenant}.sharepoint.com/sites/ITSM/Lists/KnowledgeBase` | `Status = Published` AND `Audience = "All" or matches caller` |

Replace `{tenant}` once pilot tenant is decided (open item #1 from design memo).

## Global variables

| Variable | Type | Initial value | Set by |
|---|---|---|---|
| `bot.callerUpn` | string | `User.PrincipalName` | Greeting topic on conversation start |
| `bot.callerDisplayName` | string | `User.DisplayName` | Greeting topic |
| `bot.callerManagerUpn` | string | (lookup result) | LookupUser called from Greeting |
| `bot.currentTicketId` | string | null | TicketCreation when ProposeAction succeeds |
| `bot.classificationConfidence` | number | 0 | ClassifyAndDeflect |
| `bot.classificationRisk` | string | "" | ClassifyAndDeflect (set from JobTypes registry default if action is proposed) |
| `bot.kbDeflectionAttempted` | boolean | false | ClassifyAndDeflect on first SearchKB call |
| `bot.proposedJobType` | string | "" | ProposeAction topic |

These are conversation-scoped (not user-scoped or tenant-scoped) so they reset per conversation.

## Output payload from `ProposeAction`

The tool flow MUST write a row to the `Provisioning Jobs` SharePoint list with this shape (matches dispatcher contract §1.2):

```json
{
  "JobId": "PJ-{ULID}",
  "Status": "Proposed",
  "JobType": "<from agent>",
  "Target": "{ \"type\": \"user\", \"upn\": \"...\" }",
  "Args": "{ ... }",
  "TicketId": "<from agent>",
  "RitmId": null,
  "CallerUpn": "<bot.callerUpn>",
  "CorrelationId": "<ULID — same as JobId>",
  "IdempotencyKey": "<ULID — fresh per proposal>",
  "ProposedAt": "<UTC now>",
  "Confidence": "<bot.classificationConfidence>",
  "Risk": "<bot.classificationRisk>",
  "Rationale": "<one-line explanation from agent>"
}
```

The SP write fires the Approval flow's "When item created (Status=Proposed)" trigger — see `flows/approval/spec.md` §2.

## Auto-approve posture in v1

**No auto-approve.** Per Catherine's call 2026-04-29 (verbatim "no auto-approve please"). Every privileged write goes through the full Approval Policy stages.

KB-deflection auto-resolve (no-write) IS allowed because no Graph write occurs — the agent just sends the user a KB article and stops. If Catherine confirms she wants this disabled too, the `ClassifyAndDeflect` topic short-circuits its KB branch and goes straight to TicketCreation.

## Telemetry

Agent emits to App Insights (same instance as dispatcher / executor — `appi-itsm-{env}`):

| Event | Custom dimensions |
|---|---|
| `agent.conversation_started` | callerUpn, surface |
| `agent.classified` | ticketType, category, subcategory, confidence |
| `agent.kb_deflected` | kbArticleId, deflectionAccepted (bool) |
| `agent.ticket_created` | ticketId, ticketType |
| `agent.action_proposed` | jobType, confidence, risk |
| `agent.refused` | refusalReason |
| `agent.stop_and_asked` | stopReason |
| `agent.major_incident_suspected` | matchingTickets[], cmdbCi |
| `agent.handed_to_human` | reason |
| `agent.error` | errorStep, errorMessage |

Standard dimensions on every event: `correlationId`, `callerUpn`, `surface` (teams/outlook/portal), `environment`.

## What is NOT in this spec (out of scope for v1)

- Self-Service Resolver (optional satellite, deferred)
- Major Incident Detector as scheduled flow (the agent's `MajorIncidentSuspect` topic is single-conversation pattern matching only — full cross-conversation cluster detection is the satellite agent / scheduled flow per memo §4.3)
- Outlook forward-to-bot intake (phase 1.5)
- Service Portal embedded chat (phase 2)
- Multi-language support beyond en-AU
- Custom voice / persona styling
