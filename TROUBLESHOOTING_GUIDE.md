# ITSM Level 1 Pilot Troubleshooting Guide

**Audience:** ITSM admins, flow owners, Power Platform admins, and implementation engineers

This guide covers known pilot issues, common bugs, and repeatable debugging steps.

## 1. Start Here

When something fails, identify the record and the flow stage:

1. Ticket number in **Tickets**.
2. RITM number in **Request Items**, if this is a service request.
3. SCTASK number in **Tasks**, if fulfillment began.
4. Job ID in **Provisioning Jobs**, if automation began.
5. Approval Session ID in **Approvals**, if approval is involved.
6. CorrelationId and GraphRequestId, if an executor called Microsoft Graph.

Then open Power Automate run history for the relevant flow.

## 2. Common Issues

### Plain-Text Variables Parsing

Symptom:

- RITM is created, but SCTASK -> PJ Bridge creates a malformed `TargetJson` or `ArgsJson`.
- Executor fails because required JSON fields are missing.
- Variables field contains plain text from a ticket description instead of valid JSON.

Cause:

- `Request Items.Variables` is a plain text Note field.
- RITM Generator currently stores user-supplied data from the ticket description.
- Automated flows that expect JSON must parse defensively.

Fix:

- For catalog items, ensure the request form or agent writes valid JSON matching Service Catalog `InputSchema`.
- Validate `Variables` before creating a Provisioning Job.
- If data is plain text, route the SCTASK to manual fulfillment instead of automation.
- In Power Automate, use a Compose guard before Parse JSON and create an explicit failure note when JSON is invalid.

Admin workaround:

1. Open the RITM.
2. Review `Variables`.
3. Replace with valid JSON only if the requester-provided data is clear and approved.
4. Re-run or re-create the SCTASK -> PJ step.

### SharePoint REST vs Microsoft Graph Differences

Symptom:

- A list item update works in PnP or SharePoint connector but fails through Graph.
- Lookup or user fields are not set correctly.
- Flow trigger does not fire after a script creates or edits a row.

Cause:

- SharePoint REST, PnP, Graph, and Power Automate use different field shapes.
- Power Automate SharePoint triggers can skip rows created or edited by app-only identities.

Fix:

- For Power Automate lookup fields, use `item/<Field>/Id` with the integer SharePoint item ID.
- For PnP user fields, pass an email string, not a lookup integer.
- For trigger tests, insert or edit rows with a user identity using Graph delegated auth or PnP Interactive.
- Avoid app-only PnP test rows for trigger validation.

### Ticket State Transition Problems

Symptom:

- RITM closes but parent Ticket remains In Progress.
- SCTASK closes but RITM remains Approved or In Progress.
- Provisioning Job succeeds but SCTASK remains open.
- Provisioning Job succeeds on the propose / Incident path, but the parent Ticket stays In Progress.

Cause:

- One of the orchestration flows did not run or failed:
  - SCTASK -> PJ Bridge
  - Executor
  - SCTASK Orchestrator
  - ITSM-PJ-Ticket-Resolver (propose / Incident path: resolves the parent Ticket when a non-SCTASK Provisioning Job reaches Succeeded)
- A task is not in a terminal state.
- Required SharePoint fields were omitted in PatchItem.

Fix:

1. Check the Provisioning Job state.
2. Check every SCTASK under the RITM.
3. Confirm each task is one of:
   - Closed Complete
   - Closed Incomplete
   - Closed Skipped
   - Cancelled
4. Open SCTASK Orchestrator run history (Request path). For an Incident or propose-path ticket with no SCTASK, open `ITSM-PJ-Ticket-Resolver` run history instead: it resolves the parent Ticket once the PJ, whose `IdempotencyKey` does not start with `SCTASK-`, reaches `Succeeded`.
5. If PatchItem failed, confirm the flow supplies all required SharePoint fields, not only changed fields.

### Mis-Cased JobType

Symptom:

- Dispatcher rejects a job or returns a rejected status even though the intended action exists.

Cause:

- JobTypes are camelCase and case-sensitive in practice.

Fix:

- Use `identity.resetPassword`, not `identity.reset_password`.
- Validate JobType against the JobTypes list.
- Keep Service Catalog `JobType`, Subcategory `JobTypeHint`, and executor filters aligned.

### Copilot Studio Cannot Find a Flow Action

Symptom:

- Copilot Studio publish fails after adding `InvokeFlowAction` or `InvokeFlowTaskAction`.
- Publish diagnostics report `InvalidReferenceError` / `CloudFlow ... not found`.
- The flow exists in Power Automate and may be started, but the agent still cannot bind it.

Cause:

- The cloud flow is only in `Active Solution`, `Default Solution`, or `Common Data Services Default Solution`.
- Copilot Studio binding requires the flow to be in a named unmanaged solution, such as `FS Demo`, or the named solution used for the agent.

Fix:

- For a truly non-solution flow, use Flow Studio MCP `add_live_flow_to_solution`.
- If Flow Studio MCP returns `AlreadyInSolution`, add the existing Dataverse workflow component to the named solution using `AddSolutionComponent`.
- Cloud flows are solution component type `29`.

Example `AddSolutionComponent` payload:

```powershell
$payload = @{
  ComponentId = '<dataverse-workflow-id>'
  ComponentType = 29
  SolutionUniqueName = '<named-solution-unique-name>'
  AddRequiredComponents = $true
  DoNotIncludeSubcomponents = $false
}
```

Verification:

- Query Dataverse `solutioncomponents` for the workflow ID.
- Resolve `_solutionid_value` against `solutions`.
- Confirm at least one membership points to a named unmanaged solution, not only `Active`, `Default`, or `Cr15280`.
- `ITSM-ProposeAction` was retired 2026-05-30 (see ADR 0002); the solution-membership notes here are historical.

## 3. Flow Debugging Checklist

### Triage Orchestrator

Check:

- Ticket was created by a user identity.
- Agent is published.
- Copilot Studio connection is valid.
- Agent topic triggers use natural language.
- The flow captured terminal agent outcome after the loop.

Common fixes:

- Publish the agent after YAML push.
- Set `aiSettings.useModelKnowledge: true` where the agent must compose JSON from instructions.
- Avoid braces such as `{placeholder}` in Copilot Studio instructions when Power Fx parses them.

### RITM Generator

Check:

- TicketType is `Request`.
- Ticket has a Subcategory lookup value.
- Service Catalog row has matching `SubcategoryHint`.
- Catalog item is active.
- Required RITM fields are present.

Common fixes:

- Run `seed-catalog-items.ps1`.
- Run `seed-subcategories.ps1`.
- Migrate `Tickets.Subcategory` from text to lookup if needed.

### Ticket Type Mismatch After Creation

Symptoms:

- A ticket stays in an early status after creation.
- RITM Generator ran but skipped all creation actions.
- Triage Orchestrator or Major Incident Detector processed the row when the owner expected a catalog request.
- The ticket is an Incident but the category or subcategory clearly maps to a Service Catalog request, or the ticket is a Request with no catalog match.

Check:

- `Tickets.TicketType`, `TicketSource`, `TicketState`, `Subcategory`, and `WorkNotes`.
- Whether the subcategory maps to exactly one active Service Catalog row through `SubcategoryHint`.
- Whether any RITM, SCTASK, Provisioning Job, Approval, or Major Incident link already exists.
- Flow run history for `ITSM-RITM-Generator`, `ITSM-Triage-Orchestrator`, and `ITSM-Major-Incident-Detector`.
- Once deployed, `TicketTypeValidated`, `TicketTypeValidationStatus`, `SuggestedTicketType`, and `TicketTypeValidationReason`.

Common fixes:

- If no downstream records exist and the catalog match is deterministic, correct `TicketType` and rerun the appropriate downstream flow.
- If downstream records already exist, do not manually flip `TicketType`; resolve or cancel the child records first.
- If multiple catalog items match the same subcategory, update the Service Catalog mapping or ask the caller to choose the intended catalog item.
- Add or verify the planned validator trigger guards so RITM, triage, and major incident flows wait for type validation.

### RITM Approval

Check:

- RequestedFor user has a manager in Entra ID.
- Office 365 Users connection can resolve the manager.
- Approval connector is licensed and signed in.
- RITM state is Pending Approval.

Common fixes:

- Set a manager for the test user.
- Use backup approver policy for users without managers.
- Confirm approval card delivery in Teams and email.

### SCTASK -> PJ Bridge

Check:

- `Tasks.JobType` is populated for automated tasks.
- Parent RITM and parent Ticket lookups resolve.
- RITM `Variables` is valid for the target job.
- Provisioning Job is created with `TargetJson`, `ArgsJson`, `IdempotencyKey`, and `CorrelationId`.

Common fixes:

- Re-run list 13 provisioning to add `Tasks.JobType`.
- Keep empty `JobType` for human tasks.
- Store structured JSON in RITM Variables.

### Dispatcher

Check:

- HTTP request body includes `pjId`, `jobType`, `idempotencyKey`, `callerUpn`, `approverUpn`, `approvalSessionId`, and `correlationId`.
- Provisioning Job exists.
- PJ `JobStatus` is `AwaitingApproval` (the legacy `Proposed` state was retired 2026-05-30; jobs now reach the Dispatcher only as `AwaitingApproval`).
- Inbound jobType matches the PJ row.
- Config `KillSwitch` is `false`.
- JobTypes row exists and is active.

Expected responses:

| Code | Meaning |
|---|---|
| 202 | Job accepted and marked Dispatched. |
| 200 | Idempotent replay; no second execution. |
| 400 | Invalid payload or jobType mismatch. |
| 409 | Invalid job state for dispatch. |
| 503 | Kill switch is active. |

### Executor Flows

Check:

- PJ status is `Dispatched`.
- JobType prefix matches executor filter, such as `identity.`.
- Key Vault connection can read the service principal secret.
- Token request succeeds.
- Graph or EXO call succeeds.
- PJ updates with StartedAt, CompletedAt, DurationMs, ServicePrincipal, GraphRequestId, ResultJson or ErrorJson.

Common fixes:

- Confirm Key Vault RBAC and secret name.
- Confirm service principal AppId in the flow.
- Confirm Graph application permissions and admin consent.
- Confirm matching Entra directory role.

## 4. Service Principal Permission Verification

For each executor SP:

1. Confirm app registration exists.
2. Confirm service principal exists.
3. Confirm Graph or EXO permissions are admin-consented.
4. Confirm matching directory role is assigned.
5. Wait 5-10 minutes after role assignment.
6. Request a token with client credentials.
7. Decode the token and check the `roles` claim.
8. Run the smallest safe Graph call for that executor.

For password reset:

- Required app permissions:
  - `User.ReadWrite.All`
  - `UserAuthenticationMethod.ReadWrite.All`
- Required directory role:
  - Password Administrator

Without the directory role, Graph can return `403 Authorization_RequestDenied` even when the token contains Graph app roles.

## 5. GraphRequestId Correlation

Executors write `GraphRequestId` to the Provisioning Jobs row when Graph responds.

Use it to correlate:

- Provisioning Job row.
- Power Automate action output.
- Microsoft Graph response headers.
- Tenant audit logs or Microsoft support cases.

Common header names:

- `request-id`
- `client-request-id`
- `x-ms-correlation-id`

When reporting a Graph issue, capture:

- Timestamp in UTC.
- GraphRequestId.
- Tenant ID.
- AppId of executor service principal.
- HTTP method and endpoint.
- Response status code.
- Sanitized ErrorJson.

Do not include access tokens, client secrets, temporary passwords, or full user data dumps.

## 6. Known Limitations And Workarounds

This section keeps only limitations that change troubleshooting decisions. For the full hardening backlog and implementation roadmap, see:

- [`IMPLEMENTATION-PLAYBOOK.md`](IMPLEMENTATION-PLAYBOOK.md) sections 9 and 9b for Phase 2/3 backlog.
- [`decisions/0001-dispatcher-host.md`](decisions/0001-dispatcher-host.md) for Dispatcher host, JWT, idempotency, Service Bus, and audit decisions.

| Troubleshooting-relevant limitation | What to do during incident response |
|---|---|
| Dispatcher trusts the pilot SAS URL rather than validating a JWT. | Treat Dispatcher URL exposure as a security incident. Rotate or recreate the trigger URL if exposed. |
| Idempotency uses a SharePoint list query in the pilot. | Do not test true parallel replay as proof of production idempotency. For duplicate jobs, compare `IdempotencyKey`, target state, and GraphRequestId before re-driving. |
| Executors poll Provisioning Jobs. | Allow normal 1-3 minute trigger latency before declaring a job stuck. Check whether the row was edited by a user identity. A rapid create-approve-dispatch sequence within one poll window could previously strand a `Dispatched` job on a stale trigger snapshot; fixed 2026-06-01: executors now re-read the PJ fresh (`Get_PJ_Fresh`) before gating. |
| Power Automate run history is time-limited. | Preserve Provisioning Job fields, ErrorJson, GraphRequestId, and flow run timestamps during incident review. |
| RITM approval is manager-centric in the pilot. | If a user has no manager, route through a backup approver or manually resolve the approval path. |
| App-only SharePoint edits may not trigger flows. | Use delegated Graph or PnP Interactive for trigger tests. Avoid app-only PnP rows as smoke tests unless followed by a user-identity edit. |
| Non-idempotent Graph operations can fail on replay. | Check current target state before re-drive. Create a new job only if the previous external action did not already succeed. |
| Exchange Full Access requires the EXO PowerShell Function path. | Troubleshoot the Azure Function, Key Vault cert, EXO app-only permission, and Function key before debugging Graph. |

## 7. Re-Drive Guidance

For a failed Provisioning Job:

1. Read `ErrorJson`.
2. Confirm whether the external action partially succeeded.
3. Check target state in Entra, Exchange, Teams, SharePoint, or Graph.
4. If no change occurred, create a new Provisioning Job with a new IdempotencyKey.
5. If partial change occurred, decide whether to mark the existing job Succeeded, Failed, or create a compensation job.
6. Add work notes explaining the manual decision.

Do not simply change a failed job back to `Dispatched` unless the executor is known to be idempotent for that job type.

## 8. Escalation Checklist

Escalate to the project owner or tenant admin when:

- Kill switch must be activated.
- A privileged write affected the wrong user, group, mailbox, team, or site.
- A service principal secret or cert may be exposed.
- Dispatcher URL may be exposed.
- Multiple duplicate jobs are created.
- Graph returns repeated 403, 429, or 5xx responses.
- Major Incident Detector creates repeated false positives.

Before escalation, collect:

- Ticket number.
- RITM and SCTASK numbers.
- Provisioning Job ID.
- Approval Session ID.
- CorrelationId.
- GraphRequestId.
- Flow run URL or run timestamp.
- Sanitized ErrorJson.
