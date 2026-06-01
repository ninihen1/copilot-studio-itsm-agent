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
   - AI step extracts intent from the plain text request: `action`, `user`, `resource`, `justification`, and confidence.
   - Deterministic Graph steps resolve the extracted user and group.
   - Exact single-match + high-confidence validations patch the RITM to `Pending Approval`.
   - Ambiguous or failed validations patch the RITM to `On Hold` and notify Catherine.

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

## Error And Ambiguity Handling

The validation flow puts the RITM on hold when any of these are true:

- AI confidence is below `0.85`.
- The extracted action is not `add`.
- The user search returns zero or more than one Graph user.
- The group display name search returns zero or more than one Graph group.
- The AI step or Graph calls fail.

On hold, the flow preserves the original text, writes a structured diagnostic JSON object to `RITM.Variables`, and sends Catherine a Teams clarification message with the RITM link and reason.

## Testing Strategy

1. Happy path
   - Create a Request that generates a RITM with text like `Add John Doe to Lobster Team because he joined the project`.
   - Verify validation writes `groupId`, `groupName`, `userId`, and `userPrincipalName`.
   - Verify the RITM moves to `Pending Approval`, then Catherine approval creates SCTASK rows.

2. Ambiguous user
   - Use a first name that resolves to multiple users.
   - Verify the RITM moves to `On Hold`, no approval starts, and no SCTASK/PJ is created.

3. Ambiguous or missing group
   - Use a non-exact group name.
   - Verify the RITM moves to `On Hold` and Catherine receives a clarification notification.

4. Guardrail regression
   - Force a `groups.addMember` SCTASK under a RITM whose Variables are plain text or `{}`.
   - Verify `ITSM-SCTASK-PJ-Bridge` closes the SCTASK incomplete and does not create a Provisioning Job.
   - Force a malformed PJ with `JobType=groups.addMember` and empty `TargetJson.id`.
   - Verify `ITSM-Executor-Groups` marks the PJ `Failed` without calling Graph.

## Deployment Notes

- Configure `aiExtractionEndpoint` and `aiExtractionApiKey` before starting `ITSM-RITM-Validation-Triage`; the endpoint must return the JSON schema parsed by `Parse_AI_Intent`.
- Ensure the `Request Items.Status` choice set includes `Pending Validation` and `On Hold` before deploying the RITM generator change.
- The Graph app behind `SP-IT-Groups-ClientSecret` must be allowed to read users and groups as well as perform the existing group membership writes.
