# ADR 0001 — Dispatcher host

**Status:** Accepted
**Date:** 2026-04-29
**Owner:** Catherine Han

## Context

The dispatcher is a single HTTP endpoint (`POST /provisioning/jobs`) that every approved write request flows through. It validates approval, enforces idempotency, persists an audit row, and routes to a specialised executor flow per `jobType`. It is the kill-switch and audit choke point for all privileged Graph writes in the system.

Three viable hosts were considered:

1. Power Automate HTTP-request-triggered flow
2. Azure Functions + API Management
3. Logic Apps Standard

## Decision

**Host = Power Automate HTTP-request-triggered flow** for the pilot, with four hardening items (below) that bring it to SOC-2-readiness without leaving the M365 ecosystem.

The dispatcher's **API contract is the load-bearing artefact**, not the host. The contract is designed so the host can be swapped to Azure Functions + APIM as a v1.1 migration — same JWT, same Azure Table Storage idempotency store, same Service Bus topology, same executor inputs.

## Rationale

- Team expertise is in Power Automate (FlowStudio MCP). Pilot ships faster.
- M365-native admin governance (Power Platform Admin Center) over separate Azure subscription governance during pilot.
- Real customer / SOC-2 / audit pressure has not yet arrived. Don't pre-build infra not needed.
- Contract-first design preserves the option to migrate the host later without breaking callers.

## Hardening items (non-negotiable for production; pilot status added 2026-05-01)

1. **App Insights export on every run.** PA run history caps at 28 days and is not structured for audit queries. The dispatcher emits two structured events per request: `dispatcher.received` (on first action) and `dispatcher.completed` (on last action). Both go to App Insights via the HTTP connector with an instrumentation key in Key Vault. App Insights is the audit log; Provisioning Jobs SharePoint list is a searchable mirror populated downstream.
   - **Pilot status (2026-05-01): NOT IMPLEMENTED.** Pilot uses PA run history (28-day cap) + SP audit row in `Provisioning Jobs`. Acceptable for first-quarter spot-checks. Production must add App Insights before SOC 2 timeline starts.

2. **JWT signature validation as the first action.** The Approval flow signs a token after final approval: `{ jobType, target, args-hash, approvers[], exp, jti }`. The dispatcher's first action validates the signature against the approval engine's public key (Key Vault), checks `exp` and `jti` (replay protection), and confirms `args-hash` matches the inbound payload. Reject before enqueueing on any failure.
   - **Pilot status (2026-05-01): NOT IMPLEMENTED.** Dispatcher trusts the SAS URL on its trigger. Approval-Bridge calls dispatcher with no JWT. Critical when accepting calls from outside PA — for now, only `ITSM-Approval-Bridge` calls the dispatcher, and that flow lives in the same env.

3. **Idempotency in Azure Table Storage with ETag.** SharePoint's eventual consistency permits two near-simultaneous calls with the same `idempotencyKey` to both pass the duplicate check. Idempotency keys live in `IdempotencyKeys` Azure Table with `PartitionKey = jobType`, `RowKey = idempotencyKey`. Dispatcher inserts with `If-None-Match: *` — duplicate inserts return 409 and the dispatcher returns the original job's status without enqueueing.
   - **Pilot status (2026-05-01): SP-FALLBACK IMPLEMENTED.** Dispatcher queries `Provisioning Jobs` for matching `IdempotencyKey` field. Race-vulnerable under truly-concurrent calls (verified working for sequential replays in PJ 14 → PJ 15 idempotent test). Acceptable single-tenant; production needs Table Storage.

4. **Service Bus queue between dispatcher and executors.** Dispatcher enqueues to topic `provisioning-jobs` with subject = `jobType`. Six executor flows subscribe with subscription filters on their own `jobType` values. Buffers Graph throttling spikes; per-subscription `MaxConcurrentCalls` caps each executor's parallelism. Dead-letter queue per subscription captures failures for investigation.
   - **Pilot status (2026-05-01): NOT IMPLEMENTED.** Identity-Executor polls `Provisioning Jobs` directly with a 3-min trigger filtered on `JobStatus=Dispatched AND JobType startsWith 'identity.'`. Removes throttling smoothing and FIFO-per-ticket session ordering. Acceptable at pilot volumes (single executor, low throughput). Production needs Service Bus topic + per-executor subscriptions.

## Migration path to Functions+APIM (v1.1)

Triggering events for migration:
- First contracted customer requiring SOC 2 Type II evidence
- Sustained > 5,000 jobs/week (PA throttling becomes a real cost)
- Multi-tenant deployment (PA flows are single-tenant per environment)

Migration scope (estimated 2 weeks of work):
- Replace PA HTTP trigger flow with an Azure Function exposed through APIM
- APIM enforces Entra-token auth on the public surface (replaces SAS URL)
- Function reuses the same JWT validation, Table Storage idempotency, and Service Bus enqueue logic — the four hardening items are already at this contract level
- Approval flow's POST URL changes; that's the only caller-side change
- Executor flows are unchanged — they read from Service Bus, not from the dispatcher

## Anti-patterns explicitly rejected

- **Privileged writes as Copilot Studio agent tools.** Collapses HITL, smears audit chain, couples approval with turn timing, requires re-publishing the agent for every new job type, and provides no queueing layer. Reads and reversible soft writes (post comment, set status to "Pending User") are agent tools — privileged writes are not.
- **Idempotency on a SharePoint list.** SP's eventual consistency makes the duplicate check unsafe under concurrent load.
- **Approval reference as a SharePoint record ID.** Caller-supplied IDs are not auth. Signed JWT or no go.
- **Run-history-as-audit.** PA's 28-day cap and unstructured payload are not auditable.

## Out of scope for this ADR

- Approval timeout / delegation / escalation policy — separate ADR
- Saga / compensation pattern for multi-step provisioning — separate ADR
- Service principal certificate rotation calendar — separate ADR
