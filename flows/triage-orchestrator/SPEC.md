# ITSM-Triage-Orchestrator

**Flow ID (Flow Studio Demo):** `00000000-0000-4000-8000-000000000030`
**Pattern source:** `Flow Failure Agent Handler` (Default env, `00000000-0000-4000-8000-000000000017`) per Catherine 2026-04-30
**Status:** Deployed pilot flow; ticket-source guard active; ticket-type validation gate pending

---

## Purpose

Bridge stage 1 (intake) and stage 2 (triage) of the ITSM architecture. The flow watches the `Tickets` SharePoint list for new rows, calls the **Helpdesk Triage Agent** (`cre79_agent`) to classify them, parses a tagged JSON block from the agent's reply, and either:

- **deflects** (KB match — closes the ticket as Resolved with the agent's rationale)
- **stops and asks** (low confidence / ambiguous — sets ticket On Hold, Awaiting Caller)
- **proposes** (privileged write — sets ticket In Progress and writes a `Provisioning Jobs` row Status=Proposed; the Approval flow §4 takes over)

This is the **flow-calls-agent** direction described in the architecture flowchart (Stage 1 → Stage 2 arrow), distinct from the conversational Teams path where the user calls the agent directly.

---

## Trigger

SharePoint `When an item is created`:
- Site: `https://contoso.sharepoint.com/sites/ITSM`
- List: `Tickets`
- Recurrence: 3 minutes
- splitOn: each new row processed independently

The live trigger is filtered to skip Request tickets and skip rows created by the ProposeAction handoff:

```text
TicketType != Request
and TicketSource != ProposeAction
```

After the ticket-type validator is implemented, add a validation guard so this flow only triages rows where validation is complete:

```text
TicketType != Request
and TicketSource != ProposeAction
and TicketTypeValidated = true
```

> **Conflict consideration:** this flow, RITM Generator, Major Incident Detector, and the planned Ticket Type Validator all subscribe to `Tickets` item-created events. Type validation should not be added as a simple parallel branch inside this flow because RITM Generator and Major Incident Detector can still race before the branch completes.

---

## Action sequence

```
1. Init variables: agentRawReply, parseError
2. Compose_TriagePrompt — builds [TRIAGE_REQUEST] block with ticketId, callerUpn,
   shortDescription, description, openedDate; appends instructions for the agent
   to emit a tagged ==TRIAGE_RESULT== JSON block.
3. Execute_Agent_Triage — OpenApiConnectionWebhook on shared_microsoftcopilotstudio,
   operation ExecuteCopilotAsyncV2, Copilot=cre79_agent, body/message=prompt.
4. Set_AgentRawReply from outputs('Execute_Agent_Triage')?['body/lastResponse']
5. Compose_ExtractedBlock — substring between '==TRIAGE_RESULT==' and '==END=='
   markers; empty string if either marker is missing.
6. Scope_ParseTriage — wraps Parse_TriageJson so we can branch on parse success.
7. Set_ParseError_OnFail — fires if Scope fails / skipped / timed out.
8. Compose_ImpactLabel + Compose_UrgencyLabel — converts integer 1-3 to
   '1 - High' / '2 - Medium' / '3 - Low' for SP choice columns.
9. Branch_Outcome (Switch on body('Parse_TriageJson')?['outcome']):
   - case "deflect": PatchItem Tickets — TicketState=Resolved, ResolvedDate=now,
     CloseCode='Closed/Resolved by Caller', Description=agent rationale.
   - case "stop_and_ask": PatchItem Tickets — TicketState='On Hold',
     HoldReason='Awaiting Caller', Description=moreInfoNeeded.
   - case "propose": PatchItem Tickets (TicketState='In Progress') →
     Generate JobId + IdempotencyKey → PostItem Provisioning Jobs Status=Proposed.
   - default: PatchItem Tickets TicketState='On Hold' Awaiting Caller, Description
     contains the unparseable agent reply.
```

---

## Agent prompt contract

The flow asks the agent to:

1. Classify per its standard instructions (TicketType, Category, Subcategory, Impact, Urgency).
2. Attempt deflection (KB match ≥ 0.85 confidence).
3. Stop-and-ask if confidence < 0.7 or ambiguity.
4. Otherwise propose with a `jobType` from the JobTypes registry and `args` matching the InputSchema.

The agent MUST end its reply with EXACTLY:

```
==TRIAGE_RESULT==
{
  "outcome": "deflect|stop_and_ask|propose",
  "ticketType": "Incident|Request|Change|Problem",
  "category": "string",
  "subcategory": "string",
  "impact": 1,
  "urgency": 2,
  "callerUpn": "string",
  "targetUserUpn": "string",
  "ciId": null,
  "kbArticleIds": [],
  "deflectionMessage": null,
  "moreInfoNeeded": null,
  "proposedAction": {"jobType": "identity.resetPassword", "args": {"forceChangeOnNextLogin": true, "notifyUser": true}},
  "confidence": 0.95,
  "risk": "low",
  "rationale": "string"
}
==END==
```

If the agent doesn't comply with the format, the parse fails and the ticket falls into the default branch (On Hold, human queue), with the raw agent reply preserved in the Description column for debugging.

---

## Field mappings (Tickets PatchItem)

PatchItem requires every SP-required field to be present even for partial updates. The flow passes through unchanged required fields from `triggerOutputs()?['body/...']` and overrides only the ones the agent decided. Required-and-passed-through:
- `Title`, `TicketNumber`, `Caller/Claims`, `OpenedDate`, `BusinessKey`, `ShortDescription`
- `Impact/Value`, `Urgency/Value`, `ConfidentialityLevel/Value` (defaults to Public)

Override per case:
- `TicketState/Value` → Resolved / On Hold / In Progress
- `TicketType/Value` → from `body('Parse_TriageJson')?['ticketType']`
- `Description` → agent rationale (deflect) / moreInfoNeeded (stop_and_ask)
- `CloseCode/Value` → 'Closed/Resolved by Caller' (deflect)
- `HoldReason/Value` → 'Awaiting Caller' (stop_and_ask, default)

---

## Provisioning Jobs PostItem (propose case)

Generates `JobId = PJ-{GUID}` and `IdempotencyKey = IK-{GUID}` per proposal. Writes:
- `JobType`, `JobStatus/Value=Proposed`
- `CallerUpn`, `TargetJson` (`{"type":"user","upn":"..."}`), `ArgsJson`
- `Confidence`, `Risk/Value`, `Rationale`
- `CorrelationId` = ticket's TicketNumber (matches `flows/dispatcher/contract.md` §1.2)
- `ProposedAt = utcNow()`

This insert fires the existing Approval flow trigger (`Status eq 'Proposed'` filter on Provisioning Jobs).

---

## Connections

| Connector | connectionName | Purpose |
|---|---|---|
| `shared_sharepointonline` | `f1550c57e913479793d6de83b61fa1b0` | SP triggers + writes |
| `shared_microsoftcopilotstudio` | `shared-microsoftcopi-00000000-0000-4000-8000-000000000041` | Agent invocation |

If either connection's token is stale, the flow run will surface an `Unauthorized` error in the Set_AgentRawReply or PatchItem steps. Re-auth in the Power Automate portal.

---

## Known gaps and TODOs

1. **No structured agent topic.** The agent currently has no `TriageFromFlow` topic — the prompt relies on the agent's main instructions to follow the protocol. If the agent doesn't reliably emit the JSON block, add a topic that detects `[TRIAGE_REQUEST]` prefix and explicitly enforces the format.
2. **No deflect-message-to-caller.** A successful deflect closes the ticket but does NOT send the KB article to the caller. Future: add a Teams or Outlook send-message action in the deflect branch.
3. **No multi-turn stop_and_ask.** Currently stop_and_ask sets the ticket On Hold and waits for a human. The Failure Handler pattern uses Approvals + Do_Until to re-prompt the agent — port this when ready.
4. **Ticket-type validation gate pending.** The current trigger skips Request and ProposeAction rows, but it does not yet wait for the planned validator. Add the `TicketTypeValidated` guard when the validator columns and flow are deployed.
5. **No App Insights instrumentation.** Add `triage.agent_called`, `triage.outcome_deflect`, `triage.outcome_stop_and_ask`, `triage.outcome_propose`, `triage.parse_failed` events when AppInsights is provisioned.
6. **HoldReason on default branch may not surface.** The default branch sets HoldReason='Awaiting Caller' but the issue is actually that the agent failed — reword to 'Awaiting Caller' is wrong. Add a 'Triage Failed' choice to the HoldReason column or use a different state.

---

## Test plan

Manual smoke test (no automation yet):
1. Insert a validated non-Request Tickets row via PowerShell or SharePoint UI with `ShortDescription='I forgot my password'`, valid Caller, BusinessKey, ConfidentialityLevel='Public', and `TicketTypeValidated=true` once the validator is live.
2. Wait up to 3 minutes for the trigger to fire.
3. Check the run history at https://make.powerautomate.com (env Flow Studio Demo).
4. Verify: Ticket row updated with classification + TicketState=In Progress; new Provisioning Jobs row with Status=Proposed.
5. The existing Approval flow (when wired) should pick up the Provisioning Job.
