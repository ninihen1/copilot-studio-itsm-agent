# AI + Deterministic RITM Validation Triage

## Purpose

Plain text request details must not flow directly from RITM creation into SCTASK and Provisioning Job execution. The validation triage flow converts the plain text request into structured variables, verifies the entities against Microsoft Graph, and only then releases the RITM to Catherine's approval workflow.

## Flow Architecture

1. `ITSM-RITM-Generator`
   - Creates Request Items from approved Request tickets and catalog matches.
   - New behavior: creates RITMs in `Pending Validation`, not `Pending Approval`.
   - Stores the original request text in `RITM.Variables` until validation replaces it with structured JSON.

2. `ITSM-RITM-Validation-Triage`
   - New flow in `flows/ritm-validation-triage/definition.json`.
   - Trigger: new Request Item where `RitmState = Pending Validation`.
   - Structured fast path: when the portal supplied structured `RequestPayloadJson` (e.g. a license request from the owned-license dropdown + *Other (not listed)*), validation reads it directly and skips free-text AI extraction (`If_Structured_Payload` → `Parse_Structured_Payload` → `Compose_Structured_Validated` → patch to `Pending Approval`).
   - Free-text path: otherwise a Copilot Studio agent (via `ExecuteCopilotAsyncV2`, parsed by `Parse_AI_Intent`) extracts intent from the request text: `action`, `user`, `resource`, `justification`, and confidence.
   - Deterministic Graph steps resolve the extracted user and group.
   - Exact single-match + high-confidence validations patch the RITM to `Pending Approval`.
   - When it needs more detail, the flow asks the requester rather than guessing (see *Error, Clarification, and Hand-off*).
   - A request the automation can't fulfil is handed off to the IT Service Desk queue and logged to the Catalog Demand list.

3. `ITSM-RITM-Approval`
   - Existing approval flow.
   - New behavior: uses the SharePoint updated-item trigger, so it starts when validation promotes a RITM to `Pending Approval`.
   - Still creates SCTASK rows only after Catherine approves.

4. `ITSM-SCTASK-PJ-Bridge`
   - Existing bridge from approved SCTASK rows to Provisioning Jobs.
   - New guardrail: `groups.addMember` fails the SCTASK before PJ creation if `RITM.Variables.groupId` is missing or empty.

5. `ITSM-Executor-Groups`
   - Existing groups Provisioning Job executor.
   - New guardrail: `groups.addMember` fails the PJ before Graph execution if `TargetJson.id` is missing or empty.

## Hook Point

The hook is the RITM state transition:

`RITM created as Pending Validation` -> `ITSM-RITM-Validation-Triage` -> `RITM patched to Pending Approval` -> `ITSM-RITM-Approval` -> `SCTASK rows` -> `SCTASK-PJ bridge`.

This keeps approval workflows intact. Validation does not create tasks, dispatch jobs, or perform membership changes.

## RITM.Variables Contract

For `groups.addMember`, validation writes JSON like:

```json
{
  "triageStatus": "Validated",
  "action": "add",
  "groupId": "<actual-graph-group-id>",
  "groupName": "Lobster Team",
  "userId": "<actual-graph-user-id>",
  "userPrincipalName": "john.doe@contoso.com",
  "userDisplayName": "John Doe",
  "justification": "Requested in the original RITM text.",
  "validationConfidence": 0.93,
  "validatedAt": "2026-05-14T00:00:00Z",
  "validationSource": "AI extraction plus Microsoft Graph exact match",
  "originalText": "Add John to Lobster Team"
}
```

The bridge uses `groupId` for the target resource and the RITM requester as the user target. The user fields are persisted for audit and approval context.

## Error, Clarification, and Hand-off

The validation flow stops and asks the requester (`stop_and_ask`) when any of these are true:

- AI confidence is below `0.85`.
- The extracted action is not `add`.
- The user search returns zero or more than one Graph user.
- The group display name search returns zero or more than one Graph group.
- The AI step or Graph calls fail.

**Clarification.** Instead of dead-ending, the flow sends the requester an approval card with the agent's questions and puts the RITM On Hold. The requester answers in the card's comments and the RITM re-validates automatically (`ReValidate`) — this can repeat over several rounds — or they Cancel and it closes. The original text and a structured diagnostic JSON object are preserved on `RITM.Variables` throughout.

**Hand-off.** When a request can't be matched to anything the automation can fulfil, the flow hands it to the IT Service Desk queue instead of holding indefinitely: the RITM is routed to the service desk, a row is logged to the **Catalog Demand** list (the out-of-catalog demand log), and the requester is told it was received and passed on. A fulfiller clears it from the portal's Service desk page, and `ITSM-Handoff-Closure-Notify` tells the requester once the hand-off RITM closes.

## Testing Strategy

1. Happy path
   - Create a Request that generates a RITM with text like `Add John Doe to Lobster Team because he joined the project`.
   - Verify validation writes `groupId`, `groupName`, `userId`, and `userPrincipalName`.
   - Verify the RITM moves to `Pending Approval`, then Catherine approval creates SCTASK rows.

2. Ambiguous user
   - Use a first name that resolves to multiple users.
   - Verify the RITM moves to `On Hold`, the requester gets a clarification card, no approval starts, and no SCTASK/PJ is created. Answering in the card re-validates; Cancel closes it.

3. Ambiguous or missing group
   - Use a non-exact group name.
   - Verify the RITM moves to `On Hold` and the requester receives a clarification card. A request that matches nothing the automation can fulfil should hand off to the Service Desk queue and log a Catalog Demand row instead.

4. Guardrail regression
   - Force a `groups.addMember` SCTASK under a RITM whose Variables are plain text or `{}`.
   - Verify `ITSM-SCTASK-PJ-Bridge` closes the SCTASK incomplete and does not create a Provisioning Job.
   - Force a malformed PJ with `JobType=groups.addMember` and empty `TargetJson.id`.
   - Verify `ITSM-Executor-Groups` marks the PJ `Failed` without calling Graph.

5. Structured license intake (fast path)
   - Submit a license request from the portal's owned-license dropdown (or *Other (not listed)*).
   - Verify the RITM carries `RequestPayloadJson`, validation takes the structured fast path (no free-text AI extraction), and the RITM moves straight to `Pending Approval`.

## Deployment Notes

- AI intent extraction runs through a Copilot Studio agent (`ExecuteCopilotAsyncV2`), whose reply is parsed by `Parse_AI_Intent` — make sure that agent connection is in place and published before starting `ITSM-RITM-Validation-Triage`. There is no separate extraction endpoint or API key.
- Ensure the `Request Items.Status` choice set includes `Pending Validation` and `On Hold` before deploying the RITM generator change.
- Provision the `Catalog Demand` list (`infra/sharepoint/lists/18-catalog-demand.ps1`; columns Title, RequestedItem, ResourceName, JobTypeGuess, Requester, RitmRef, DemandStatus, DemandNotes) before enabling the hand-off branch, which writes to it.
- The Graph app behind `SP-IT-Groups-ClientSecret` must be allowed to read users and groups as well as perform the existing group membership writes.
