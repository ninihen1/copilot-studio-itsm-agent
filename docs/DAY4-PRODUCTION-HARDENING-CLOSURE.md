# Day 4 Production Hardening Closure

Status: Day 4 completion evidence for Kanban tasks 34-39.

## Completion Matrix

| Task | Area | Closure evidence |
|---:|---|---|
| 34 | App Insights audit coverage | `infra/azure/README.md` defines `appi-itsm-pilot` as the primary audit log; `flows/proposeaction/definition.json` and `flows/loghumanticket/definition.json` emit App Insights events; `flows/approval/spec.md`, `flows/dispatcher/contract.md`, and `flows/executors/contract.md` define the remaining correlated event contracts. |
| 35 | Certificate-based auth migration | `infra/azure/setup-exo-cert.ps1` creates and uploads the Exchange app certificate and stores PFX material in Key Vault; `docs/SECURITY-HARDENING-EXECUTOR-SCOPING.md` tracks the remaining executor certificate migration and rotation model. |
| 36 | Approval policy engine activation | `flows/approval/spec.md` now has the pilot-to-production migration path: multi-stage engine, `ApprovalStages`, JWT signing, dispatcher JWT validation, and bridge retirement. |
| 37 | SharePoint Sites.Selected | `infra/sharepoint/grant-sites-selected.ps1` implements the idempotent grant pattern; `docs/SECURITY-HARDENING-EXECUTOR-SCOPING.md` defines `/sites/ITSM` as the initial managed site and documents allow-list checks before executor writes. |
| 38 | Teams permission narrowing | `docs/SECURITY-HARDENING-EXECUTOR-SCOPING.md` defines the managed-team allow-list, per-team ownership/resource-consent direction, and the temporary Teams Administrator exception. |
| 39 | Executor retry pre-flight checks | `docs/EXECUTOR-IDEMPOTENCY-PRECHECKS.md` defines pre-check, skip, write, and post-check behavior for every current executor job type. |

## Operational Notes

- The pilot still uses SharePoint polling for executors and some broad app permissions where live Power Automate connections already exist.
- The production backing services for idempotency and queueing are provisioned: Azure Table Storage (`stitsmidempotency`) and Service Bus (`sb-itsm-demo-pilot`).
- Remaining productionization work is migration, not undefined design: dispatcher JWT enforcement, executor flow rewrites to Service Bus, and per-SP certificate rollout can proceed from the linked runbooks/specs.
