# Azure Infrastructure

Azure resources required for the M365 ITSM build. Pilot deploys minimal scoped resources; production extends the same shape.

## Resources

| Resource | Pilot SKU | Purpose |
|---|---|---|
| Resource Group `rg-itsm-pilot` | n/a | All pilot resources colocated |
| Key Vault `kv-itsm-demo` | Standard | Stores SP certificates, JWT/function secrets, and connection strings |
| Storage Account `stitsmidempotency` | Standard_LRS | Tables: `IdempotencyKeys`, `JwtReplay` |
| Service Bus `sb-itsm-demo-pilot` | Standard | Topic `provisioning-jobs` + 6 subscriptions (sub-identity, sub-groups, sub-licensing, sub-exchange, sub-sharepoint, sub-teams) |
| Application Insights `appi-itsm-pilot` | Pay-as-you-go | Primary audit log + telemetry |
| Function App `func-itsm-dev` | Consumption | Hosts `jwt-sign` and `jwt-validate` Functions |

## Why these specifically

- **Key Vault HSM-backed key for JWT signing.** Per dispatcher contract §1.3, the Approval flow signs the JWT and the Dispatcher validates. Key never leaves Key Vault — both Functions call into KV via Managed Identity to sign / verify. HSM-backed because compromise = ability to mint approval tokens for arbitrary writes.
- **Azure Table Storage for idempotency.** Per ADR 0001, NOT SharePoint — SP eventual consistency lets two near-simultaneous calls both pass the duplicate check. ETag-based optimistic concurrency on Insert (`If-None-Match: *`) = strict deduplication.
- **Service Bus Standard.** Required for topics. Premium gives geo-DR; revisit before production. Duplicate detection ON (10-minute window) as defence in depth alongside Table Storage idempotency.
- **App Insights.** Per ADR 0001, this is the **primary** audit log, not the SP Provisioning Jobs list. SP is a searchable mirror.
- **Function App consumption tier.** Cold start ~1-3s acceptable for pilot; revisit if dispatcher latency matters at scale.

## What's NOT in Azure

The dispatcher itself is a Power Automate HTTP-triggered flow (per ADR 0001, not Functions+APIM for v1). Migration to Functions+APIM is documented as v1.1; Azure resources stay the same, only the dispatcher host swaps.

## Deployment

Bicep / Terraform not yet authored. Pilot deploys via `az` CLI per `DEPLOYMENT.md` Phase 2. When pilot stabilises, codify into Bicep at `infra/azure/main.bicep`.

### Idempotency storage

Production hardening provisions the dispatcher idempotency backing store with:

```powershell
./infra/azure/provision-idempotency-storage.ps1 -EnvFile .env.production
./infra/azure/test-idempotency-table.ps1 -EnvFile .env.production
```

Live pilot state as of 2026-05-07:

- Storage account: `stitsmidempotency`
- Resource group: `rg-itsm-pilot`
- Region: `australiaeast`
- SKU: `Standard_LRS`
- HTTPS only: enabled
- Minimum TLS: `TLS1_2`
- Tables: `IdempotencyKeys`, `JwtReplay`
- Key Vault references: `IdempotencyStorageAccountName`, `IdempotencyStorageConnectionString`

The test script inserts a disposable `IdempotencyKeys` row, attempts the same
`PartitionKey`/`RowKey` again with `--if-exists fail`, and requires the second insert
to fail. This proves the storage layer can enforce the dispatcher concurrency gate.

Power Automate dispatcher migration note: replace the current SharePoint
`Check_Idempotency` query with an Azure Table insert for `PartitionKey=jobType` and
`RowKey=idempotencyKey`, using create-if-not-exists semantics. A duplicate/conflict
response must return the existing job status without dispatching another executor write.

### Service Bus executor dispatch

Production hardening provisions the executor dispatch queueing topology with:

```powershell
./infra/azure/provision-servicebus-dispatch.ps1 -EnvFile .env.production
./infra/azure/test-servicebus-dispatch-topology.ps1 -EnvFile .env.production
```

Live pilot state as of 2026-05-07:

- Namespace: `sb-itsm-demo-pilot`
- Resource group: `rg-itsm-pilot`
- Region: `australiaeast`
- SKU: `Standard`
- Topic: `provisioning-jobs`
- Topic TTL: `P1D`
- Duplicate detection: enabled, `PT10M` window
- Subscriptions: `sub-identity`, `sub-groups`, `sub-licensing`, `sub-exchange`, `sub-sharepoint`, `sub-teams`
- Subscription settings: sessions enabled, lock duration `PT5M`, max delivery count `5`
- Key Vault references: `ServiceBusNamespaceName`, `ServiceBusTopicName`, `ServiceBusConnectionString`

Routing uses SQL filters on brokered-message `sys.Label`, because Azure Service Bus SQL
filters reject `sys.Subject`. Modern SDKs expose the same brokered-message field as
`Subject`; Power Automate/dispatcher send actions must set the connector field that maps
to Service Bus Label/Subject with the `jobType` value.

Current pilot migration note: live dispatcher/executor flows still use the SharePoint
`Provisioning Jobs` polling path (`JobStatus=Dispatched`). To activate Service Bus
dispatch, add the dispatcher `Send message to topic` step after PJ creation/update and
rewrite each executor trigger to the Service Bus topic subscription trigger in peek-lock
mode with explicit complete/abandon/dead-letter handling.

## Functions: jwt-sign and jwt-validate

### jwt-sign

- **Trigger:** HTTP POST
- **Input:** `{ claims: object, keyId: string }`
- **Output:** `{ jwt: string }` — signed RS256 JWT with `kid` header set to keyId
- **Identity:** Managed Identity with Get + Sign on Key Vault key `itsm-approval-signing-dev`
- **Authentication:** Function-level key (only callable by the Approval flow)

### jwt-validate

- **Trigger:** HTTP POST
- **Input:** `{ jwt: string, jwksUrl: string, expectedIss: string, expectedAud: string }`
- **Output:** `{ valid: bool, claims: object | null, error: string | null }`
- **Identity:** None — pure compute, fetches JWKS from public endpoint
- **Authentication:** Function-level key (only callable by the Dispatcher flow)

Both Functions are stateless. Each `func-itsm-dev` instance can serve both. Failure modes:
- Key Vault unreachable: Function returns 5xx; flow retries
- JWKS endpoint unreachable: jwt-validate returns 5xx; dispatcher retries up to 3 with backoff before returning 401 to caller
- Key rotation: jwt-sign always uses current key; jwt-validate accepts both current + previous (7-day window)

Sample implementations should be added under `infra/azure/functions/` — placeholder for now.

## Cost estimate (pilot, monthly)

| Resource | Pilot cost (rough) |
|---|---|
| Key Vault Standard | ~$2 |
| Storage Account (Tables, low write volume) | <$1 |
| Service Bus Standard (under 1 GB throughput) | ~$10 |
| Application Insights (low telemetry volume) | ~$5 |
| Function App Consumption (pilot volume = a few hundred invocations/month) | <$1 |
| **Total pilot Azure cost** | **~$20/month** |

Production scaling: Service Bus dominates. At ~100k jobs/month, Service Bus Standard + Function consumption together come in under $100/month. Premium Service Bus + Function Premium for geo-DR adds $1k+/month.

## Open items

1. **Bicep / Terraform IaC.** Pilot is `az` CLI; codify before production.
2. **Function App code.** `jwt-sign` + `jwt-validate` not yet authored. Pilot Week 4 deliverable. Stub implementations acceptable in dev environment.
3. **Backup strategy.** Tables are LRS; consider GRS for production. App Insights data retention 90 days default; extend if SOC 2 audit demands longer.
4. **Monitoring alerts.** Wire App Insights -> Azure Monitor alerts for: `dispatcher.killed` rate, executor failure rate, Key Vault access denied, Service Bus DLQ depth.
