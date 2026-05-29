# Documentation Audit - Complete Inventory

> **HISTORICAL SNAPSHOT** - This audit was from an earlier phase. Current status tracked in `flows/CURRENT-STATUS.md`. Actual file count is now 59 (not 31).

**Audit Date:** 2026-05-06  
**Purpose:** Map all documentation, identify duplicates, recommend cleanup

---

## Executive Summary

**Total Markdown Files:** 31  
**Status:**
- ✅ **Clean & Current:** 20 files
- ⚠️ **Needs Review:** 6 files (potential duplicates or outdated)
- ❌ **Should Remove:** 2 files (obsolete)
- 📋 **Working Docs (keep):** 3 files in prompts/

---

## 1. ROOT LEVEL DOCUMENTATION (6 files)

### ✅ **KEEP - Core Documentation**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **README.md** | 203 | Project overview, repo layout, documentation map | ✅ Current, well-organized |
| **WHAT_IT_DOES.md** | 533 | Plain-English stakeholder explanation | ✅ NEW (created today), excellent for non-technical audience |
| **IMPLEMENTATION-PLAYBOOK.md** | 553 | Canonical rebuild/extension guide for builders | ✅ Current, comprehensive |
| **DEPLOYMENT.md** | 485 | Step-by-step deployment runbook | ✅ Current, includes Phase 3/3.1 consolidation |
| **PROJECT_TIMELINE.md** | 317 | Detailed timeline with start/finish/durations | ✅ NEW (created today), tracks progress |
| **itsm-design-memo.md** | 184 | Original design intent, architecture rationale | ✅ Current, historical reference |

### ⚠️ **REVIEW - Potentially Redundant**

| File | Lines | Issue | Recommendation |
|---|---:|---|---|
| **PHASE-3-DEPLOYMENT.md** | 366 | Overlaps with DEPLOYMENT.md Phase 3 section | **MERGE INTO DEPLOYMENT.md or DELETE** — Phase 3 content already consolidated into DEPLOYMENT.md §Phase 3. This may be the PRE-consolidation version. |

### 📚 **KEEP - Reference Only**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **servicenow-itsm-ticketing-report.md** | 478 | ServiceNow research baseline | ✅ Reference document, not operational |

---

## 2. docs/ DIRECTORY (4 files)

### ✅ **KEEP - User-Facing Guides**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **docs/USER_GUIDE.md** | 235 | End-user instructions | ✅ Current, consolidated |
| **docs/ADMIN_GUIDE.md** | 277 | Admin operations guide | ✅ Current, architecture trimmed, operations kept |
| **docs/TROUBLESHOOTING_GUIDE.md** | 323 | Symptom-first debugging | ✅ Current, deduped limitations |
| **docs/DEPLOYMENT_GUIDE.md** | 3 | **POINTER FILE ONLY** | ✅ Correctly reduced to pointer to ../DEPLOYMENT.md |

**Status:** ✅ **CLEAN** — Consolidation complete, each doc has distinct purpose

---

## 3. agents/ DIRECTORY (3 files)

### ✅ **KEEP - Agent Specifications**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **agents/triage/SPEC.md** | 167 | Canonical Triage Agent spec | ✅ Current, source of truth |
| **agents/triage/README.md** | 96 | Triage Agent overview + push procedure | ✅ Current |
| **agents/resolver/README.md** | 48 | Self-Service Resolver (optional, deferred) | ✅ Current, clearly marked as deferred |

**Status:** ✅ **CLEAN**

---

## 4. flows/ DIRECTORY (12 files)

### ✅ **KEEP - Flow Specifications**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **flows/dispatcher/contract.md** | 338 | Production-grade Dispatcher contract | ✅ Current, clearly marked as v1 target |
| **flows/executors/contract.md** | 253 | Executor contract (symmetric across all 6) | ✅ Current |
| **flows/approval/spec.md** | 355 | Production-grade Approval flow spec | ✅ Current, v1 target |
| **flows/triage-orchestrator/SPEC.md** | 159 | Triage Orchestrator flow spec | ✅ Current |
| **flows/proposeaction/README.md** | 50 | ProposeAction flow overview | ✅ Current |
| **flows/permsync/README.md** | 39 | Item-level permissions flow | ✅ Current |
| **flows/license-costs-sync/README.md** | 92 | License SKU sync flow | ✅ Current |
| **flows/getsiteinfo/SPEC.md** | 109 | GetSiteInfo utility flow | ✅ Current |

### ⚠️ **REVIEW - Potentially Obsolete**

| File | Lines | Issue | Recommendation |
|---|---:|---|---|
| **flows/approval/SPEC-v1.md** | 117 | Pilot simplified version | **CLARIFY:** Is this the pilot version or obsolete? If obsolete, DELETE. If pilot, RENAME to `SPEC-pilot.md` for clarity. |
| **flows/proposeaction/DEPLOYED-DEVIATIONS.md** | 52 | MVP slice notes from 2026-04-30 | **REVIEW:** If ProposeAction has been updated since, this is stale. DELETE or move to prompts/ as historical. |

### ⚠️ **REVIEW - Historical Status**

| File | Lines | Issue | Recommendation |
|---|---:|---|---|
| **flows/WEEK2-README.md** | 242 | Week 2 status (2026-05-01) | **REVIEW:** We're now at Day 3 (2026-05-06). Is this still relevant or historical? Consider: (1) DELETE if superseded by DEPLOYMENT.md, (2) RENAME to `WEEK2-STATUS-HISTORICAL.md`, or (3) UPDATE to current status. |

**Status:** ⚠️ **NEEDS REVIEW** — 3 files may be outdated or duplicate

---

## 5. decisions/ DIRECTORY (1 file)

### ✅ **KEEP - Architecture Decision Records**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **decisions/0001-dispatcher-host.md** | 69 | ADR for Dispatcher host decision | ✅ Current, production hardening tracked |

**Status:** ✅ **CLEAN**

---

## 6. infra/ DIRECTORIES (3 files)

### ✅ **KEEP - Infrastructure Documentation**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **infra/sharepoint/README.md** | 104 | SharePoint provisioning runbook | ✅ Current |
| **infra/azure/README.md** | 75 | Azure infrastructure overview | ✅ Current |
| **infra/azure/functions/README.md** | 115 | Azure Functions (Phase 3.1 wrappers) | ✅ Current |

**Status:** ✅ **CLEAN**

---

## 7. notifications/ DIRECTORY (1 file)

### ✅ **KEEP - Adaptive Card Templates**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **notifications/cards/README.md** | 48 | Adaptive Cards template documentation | ✅ Current |

**Status:** ✅ **CLEAN**

---

## 8. prompts/ DIRECTORY (2 files)

### 📋 **KEEP - Working Documentation (Local Only)**

| File | Lines | Purpose | Status |
|---|---:|---|---|
| **prompts/day3_testing_results.md** | 157 | Day 3 test matrix by Testing worker | 📋 Working doc, keep for reference |
| **prompts/documentation_consolidation_analysis.md** | ~1200 (35KB) | Consolidation analysis by Docs worker | 📋 Working doc, keep for reference |

**Note:** Per CLAUDE.md, `prompts/` is local-only scratch space and should NEVER be committed to source control.

**Status:** ✅ **APPROPRIATE** — Working docs in correct location

---

## CLEANUP RECOMMENDATIONS

### Priority 1: Remove Duplicates/Obsolete

```bash
# Check if PHASE-3-DEPLOYMENT.md is duplicate of DEPLOYMENT.md Phase 3
# If yes, DELETE:
rm "PHASE-3-DEPLOYMENT.md"

# Check flows/approval/SPEC-v1.md
# If obsolete: DELETE
# If pilot version: RENAME to SPEC-pilot.md
rm "flows/approval/SPEC-v1.md"  # OR: mv to SPEC-pilot.md

# Check flows/proposeaction/DEPLOYED-DEVIATIONS.md
# If stale (from April 30): DELETE or move to prompts/
rm "flows/proposeaction/DEPLOYED-DEVIATIONS.md"
```

### Priority 2: Review Historical Status

```bash
# Check flows/WEEK2-README.md
# Decision:
# Option A: DELETE if superseded by DEPLOYMENT.md
# Option B: RENAME to WEEK2-STATUS-HISTORICAL.md
# Option C: UPDATE to current Week 3/Day 3 status
```

---

## DOCUMENT HIERARCHY (Recommended Reading Order)

### For Stakeholders / Executives:
1. **WHAT_IT_DOES.md** ⭐ START HERE
2. **README.md** — Overview + doc map
3. **itsm-design-memo.md** — Design rationale

### For End Users:
1. **docs/USER_GUIDE.md** ⭐ START HERE

### For Admins:
1. **docs/ADMIN_GUIDE.md** ⭐ START HERE
2. **docs/TROUBLESHOOTING_GUIDE.md** — When things break

### For Deployment Engineers:
1. **DEPLOYMENT.md** ⭐ START HERE
2. **infra/sharepoint/README.md** — SharePoint provisioning
3. **infra/azure/README.md** — Azure resources

### For Implementation Engineers / AI Agents:
1. **IMPLEMENTATION-PLAYBOOK.md** ⭐ START HERE
2. **agents/triage/SPEC.md** — Triage Agent canonical spec
3. **flows/dispatcher/contract.md** — Dispatcher production contract
4. **flows/executors/contract.md** — Executor contract
5. **flows/approval/spec.md** — Approval flow production contract

### For Project Tracking:
1. **PROJECT_TIMELINE.md** — Detailed timeline with durations
2. **PROJECT_KANBAN.html** — Visual board (open in browser)

---

## MISSING DOCUMENTATION (Consider Creating)

### High Priority:
1. **CHANGELOG.md** — Track version history, breaking changes
2. **CONTRIBUTING.md** — How to contribute (if open-sourcing)
3. **flows/CURRENT-STATUS.md** — Replace WEEK2-README with current deployment status

### Medium Priority:
4. **docs/FAQ.md** — Common user questions
5. **docs/ONBOARDING-CHECKLIST.md** — For new pilot users
6. **infra/azure/COST-ESTIMATE.md** — Azure resource costs

### Low Priority:
7. **SECURITY.md** — Security disclosure policy
8. **LICENSE.md** — License terms (if applicable)

---

## ACTION PLAN

### Immediate (Do Now):

1. **Verify PHASE-3-DEPLOYMENT.md redundancy:**
   - Compare with DEPLOYMENT.md Phase 3 section
   - If duplicate → DELETE
   - If has unique content → MERGE into DEPLOYMENT.md, then DELETE

2. **Review flows/approval/SPEC-v1.md:**
   - Clarify if pilot version or obsolete
   - If obsolete → DELETE
   - If pilot → RENAME to `SPEC-pilot.md`

3. **Review flows/proposeaction/DEPLOYED-DEVIATIONS.md:**
   - Check if ProposeAction updated since April 30
   - If stale → DELETE or move to prompts/

4. **Decide on flows/WEEK2-README.md:**
   - Update to current status OR
   - Rename to historical OR
   - Delete if superseded

### Next Session:

5. **Create CHANGELOG.md** — Track Day 1-3 work + upcoming Day 4
6. **Create flows/CURRENT-STATUS.md** — Current deployment state
7. **Review all READMEs** for outdated flow IDs or statuses

---

## FINAL VERIFICATION CHECKLIST

After cleanup, verify:

- [ ] No duplicate content across docs
- [ ] Each doc has clear, distinct purpose
- [ ] README.md documentation map is accurate
- [ ] All cross-references work (no broken links)
- [ ] No stale status dates (2026-05-01 when we're at 2026-05-06)
- [ ] prompts/ not committed to source control
- [ ] All "✅ done" status markers are actually true

---

## DOCUMENTATION QUALITY SCORE

**Before Consolidation:** 6/10
- Duplication between DEPLOYMENT_GUIDE and DEPLOYMENT.md
- Architecture duplicated across multiple docs
- Status scattered across multiple README files

**After Consolidation:** 7.5/10
- ✅ Core guides consolidated
- ✅ Clear hierarchy
- ⚠️ Still have 3-4 potentially obsolete/duplicate files
- ⚠️ Historical status docs may be outdated

**Target After Cleanup:** 9/10
- Remove identified duplicates
- Update or archive historical status docs
- Add missing high-priority docs (CHANGELOG, CURRENT-STATUS)
