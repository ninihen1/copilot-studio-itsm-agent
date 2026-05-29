# Service Catalog Audit — 2026-05-03

## Question

Of 87 Subcategories across 18 Categories, which deserve a Service Catalog item, and which can route through the Incident → AI Triage path?

## Heuristic

A subcategory **deserves** a Catalog item if it meets **all three**:

1. **Has a stable JobType** in one of our 6 executor categories (`identity.*`, `licensing.*`, `groups.*`, `sharepoint.*`, `teams.*`, `exchange.*`) — i.e. an executor can fulfil it deterministically
2. **Has a stable approval policy** — manager / asset owner / automatic
3. **Has a stable input schema** — what data does the requester (or agent) need to provide

Otherwise leave it as an **Incident-only** subcategory and let Triage Agent + Triage Orchestrator handle it.

## Findings

### Existing catalog items (9)

| Title | Status | Action |
|---|---|---|
| CAT-PWD-RESET | ✓ Working end-to-end | Keep |
| CAT-LIC-REQUEST | JobType=`licensing.assign`, not yet tested | Rename to `CAT-LICENSE-CHANGE`, extend to cover Revoke too (N:1 pattern, see below) |
| CAT-GROUP-ADD | JobType=`groups.addMember`, untested | Extend to N:1: `CAT-GROUP-MEMBERSHIP` covering Add + Remove + Role |
| CAT-MBX-ACCESS | JobType=`exchange.grantFullAccess`, untested | Keep, possibly extend to revoke |
| CAT-SP-RESTORE | JobType=`sharepoint.restoreFile`, untested | Keep |
| CAT-SOFT-INSTALL | JobType=**empty** | Wire to executor or mark Incident-only |
| CAT-ONBOARD | JobType=**empty** | Composite flow (multiple JobTypes) — needs parent-job design, not a single executor call |
| CAT-OFFBOARD | JobType=**empty** | Same — composite |
| CAT-TEAMS-CHANNEL-MEMBER | JobType=`teams.addChannelMember` | Extend to N:1: `CAT-TEAMS-CHANNEL` covering create + add member |

### Recommended new catalog items (≈6 new + consolidation of existing 9)

Aim: **15 catalog items total** covering ~25 of 87 subcategories. The other ~62 stay Incident-only.

#### Tier 1 — 1:1 (one catalog per subcategory)

| Catalog item | Category | SubcategoryHint | JobType | Approval |
|---|---|---|---|---|
| CAT-PWD-RESET ✓ | Account & Access | Password Reset | identity.resetPassword | AP-PWD-RESET-V1 |
| CAT-USER-CREATE | IAM | Create New User | identity.createUser | AP-NEW-USER-V1 (manager) |
| CAT-USER-DISABLE | IAM | Disable User | identity.disableUser | AP-OFFBOARD-V1 (HR + manager) |
| CAT-USER-ENABLE | IAM | Enable User | identity.enableUser | AP-MGR-V1 |
| CAT-MFA-RESET | IAM | MFA Reset | identity.resetMfa* | AP-IDENTITY-V1 |
| CAT-SP-RESTORE ✓ | SharePoint & Files | File Restore | sharepoint.restoreFile | AP-AUTO |

\* MFA reset JobType may not exist in executor yet — verify.

#### Tier 2 — N:1 (multiple subcategories → one catalog with operation enum)

| Catalog item | Covers subcategories | Variants | InputSchema key |
|---|---|---|---|
| CAT-LICENSE-CHANGE | Assign License, Revoke License | `licensing.assign`, `licensing.revoke` | `operation: assign \| revoke` |
| CAT-GROUP-MEMBERSHIP | Add to Group, Remove from Group, Role Assignment | `groups.addMember`, `groups.removeMember`, `groups.assignRole` | `operation: add \| remove \| role` |
| CAT-MAILBOX-ACCESS | Calendar Permission, Shared Mailbox/Folder | `exchange.grantFullAccess`, `exchange.grantCalendar` | `permissionType: calendar \| fullAccess` |
| CAT-DISTRIBUTION-LIST | Distribution List | `exchange.addDistList`, `exchange.removeDistList` | `operation: add \| remove` |
| CAT-TEAMS-CHANNEL | Channel Creation, Add channel member (current CAT-TEAMS-CHANNEL-MEMBER) | `teams.createChannel`, `teams.addChannelMember` | `operation: create \| addMember` |
| CAT-SP-PERMISSION | Site Permission | `sharepoint.grantSitePermission` | `role: read \| contribute \| owner` |
| CAT-SP-PROVISION | Site Provisioning | `sharepoint.provisionSite` | `siteType: communication \| team` |
| CAT-SOFT-INSTALL ✓ | Software Install | `software.deploy`* | `appId, version` |

\* `software.*` JobType family doesn't exist yet — would need an Intune executor or similar.

#### Tier 3 — Composite (parent flow, spawns multiple child JobTypes)

| Catalog item | Subcategory | Approach |
|---|---|---|
| CAT-ONBOARD ✓ | Onboarding | Parent flow spawns: `identity.createUser` → `groups.addMember` (default groups) → `licensing.assign` (default SKU) → `exchange.createMailbox` → `teams.addChannelMember` (welcome channel). Design as orchestrated multi-SCTASK. |
| CAT-OFFBOARD ✓ | Offboarding | Parent: `identity.disableUser` → `licensing.revoke` (all SKUs) → `groups.removeMember` (all) → `exchange.forwardMailbox` → `sharepoint.transferOwnership`. |

#### Incident-only (no catalog item — Triage Agent handles)

**These 62 subcategories submit as Incidents and rely on the AI Triage Agent + Triage Orchestrator to propose actions:**

- **Account & Access (8)**: Account Unlock¹, Group / Role Membership¹, MFA Reset¹, New Account Creation¹, Privileged Access (RBAC), Shared Mailbox / Folder¹, VPN Access
  *(¹ duplicates of IAM/Groups subcategories — see "Taxonomy issue" below)*
- **Hardware (9)**: All — physical fulfilment, no executor
- **Network & Connectivity (7)**: All — needs security review
- **Facilities (3)**: All — non-IT
- **HR Cross-Over (5)**: Address Change, Benefits Enrollment, Leave of Absence, Name Change, Tuition Reimbursement — non-IT (Onboarding + Offboarding stay Tier 3)
- **Mobile & Endpoint (4)**: All — needs MDM executor (not built)
- **Security & Compliance (5)**: All — human review required
- **Reporting & Analytics (4)**: All — bespoke
- **Telecom & Mobile (6)**: All — carrier-specific
- **Database & Storage (4)**: All — DBA team
- **Software (4 of 5)**: License Request (→ falls to CAT-LICENSE-CHANGE), Software Bug, Software Removal, Software Upgrade — variable scope
- **Email & Messaging (4)**: Email Rules, Mailbox Size Increase, New Mailbox, Teams/Slack Channel
- **Teams & Collaboration (3)**: Meeting Issue, Team Provisioning, Teams App Issue
- **Licensing (1)**: License Audit — reporting, not a fulfilment

## Taxonomy issue to fix (separate from catalog)

The Subcategories list has **duplicate names across categories**:

| Subcategory | Appears in |
|---|---|
| Password Reset | Account & Access, **IAM** |
| MFA Reset | Account & Access, **IAM** |

This is Phase 3 vocabulary alignment debt (see `project_itsm_categories_vocabulary_alignment_2026-05-01.md` in memory). Recommend deprecating the Account & Access duplicates in favour of IAM, since IAM is the agent's working vocabulary. Keep Account & Access for the non-IAM items (VPN, Shared Mailbox, Privileged Access, Group/Role Membership — though those are also covered by Groups).

**This is a separate cleanup task.** Doing it now would block licensing testing; defer.

## Recommendation summary

- **Build 7 new + reshape 4 existing catalog items.** Net: 13 catalog items covering 25 subcategories.
- **62 subcategories stay Incident-only.**
- **Defer:** subcategory taxonomy dedupe + MDM/software executors + composite onboard/offboard flows.

## Order of operations if Catherine approves

1. **Today (~30 min):**
   - Create CAT-LICENSE-CHANGE (Tier 2) — covers her current Revoke License test case. Reshape existing CAT-LIC-REQUEST or create new.
   - Add an Approval Policy `AP-LICENSE-V1`
   - Verify Licensing Executor handles both `assign` + `revoke` JobTypes (check `flows/executors/licensing/definition.json`)
2. **Next session:**
   - CAT-GROUP-MEMBERSHIP (N:1) + reshape CAT-GROUP-ADD
   - CAT-TEAMS-CHANNEL (N:1) + reshape CAT-TEAMS-CHANNEL-MEMBER
   - Tier 1 IAM catalog items
3. **Later:**
   - Composite Onboarding / Offboarding flows
   - Subcategory taxonomy dedupe
   - MDM + Software executors

## Key insight

Catalog items are a **commitment to deterministic fulfilment**. Each one means: this flow is templated, the args are known, the approval is fixed, the executor is wired. That's expensive to build and maintain. Every subcategory does NOT need this — most should fall through the Incident path where the AI Triage Agent's flexibility is the point.

A heavy-handed "one catalog per subcategory" would force IT to maintain ~87 stale Service Catalog rows when 60+ of them are best handled by an agent on the fly.
