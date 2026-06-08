# What Does The ITSM System Do?

**A Plain-English Explanation for Stakeholders, Customers, and New Team Members**

---

## The Elevator Pitch

This is an **AI-powered IT helpdesk** built entirely on Microsoft 365 — no ServiceNow license required. Users submit a ticket through a self-service portal; a Power Automate flow fires on the new ticket and calls an AI agent to triage it, propose a solution, and (with human approval) automatically fix common issues like password resets, group membership, license assignments, and mailbox access.

**Think:** ServiceNow-style ITSM, but using SharePoint for data, Power Automate for automation, and Copilot Studio as the triage AI.

---

## What Problems Does It Solve?

### For End Users:
- **No routing guesswork** — Submit a ticket in the portal; the AI classifies and routes it for you
- **Instant KB answers** — The agent searches the knowledge base first and can resolve simple tickets immediately
- **Automatic routing** — Your ticket goes to the right team without bouncing between groups
- **Status transparency** — Track your ticket status in SharePoint anytime

### For IT Staff:
- **Automated Level 1 work** — Password resets, group adds, license assignments happen automatically after approval
- **Reduced ticket volume** — AI deflects common issues with knowledge base articles
- **Consistent classification** — Every ticket properly categorized, prioritized, and routed
- **Full audit trail** — Every privileged action traceable to its approval

### For IT Leaders:
- **Lower cost** — No ServiceNow licenses, runs on existing M365 stack
- **Faster response** — SLA timers, breach warnings, business hours tracking
- **Security by design** — AI proposes, humans approve, scoped service principals execute (no all-powerful admin account)
- **Production-ready reporting** — Track SLA attainment, MTTR, agent accuracy, deflection rates

---

## What Types of Requests Can It Handle?

### ✅ Fully Automated (After Approval)

#### Identity & Access
- Reset user password
- Unlock account
- Reset MFA methods
- Enable/disable user account

#### Groups & Permissions
- Add user to security group
- Remove user from group
- Create new security group
- Grant mailbox access (shared/user mailbox)

#### Licensing
- Assign Microsoft 365 license
- Remove license
- Change license SKU

#### Exchange & Email
- Grant mailbox permissions (Full Access, Send As, Send on Behalf)
- Revoke mailbox permissions
- Create distribution list
- Manage distribution list members

#### SharePoint & OneDrive
- Restore deleted file
- Grant site/folder permissions
- Remove permissions
- Restore deleted site

#### Teams & Collaboration
- Create Teams channel
- Add members to Teams channel
- Remove members from channel
- Archive/unarchive Teams team

### 📋 Request Fulfillment (Service Catalog)

These require approval, then generate work tasks:

- **New hire onboarding** — Laptop + phone + software + access (Order Guide)
- **User offboarding** — Revoke access, archive data, disable accounts (Order Guide)
- **Software installation request**
- **Hardware request** (laptop, monitor, phone, accessories)
- **License request** (specific software license types)
- **Access requests** (shared mailbox, SharePoint site, security group)

### 🔍 Break/Fix Incidents

Traditional IT support tickets that may or may not be automatable:

- Wi-Fi connectivity issues
- VPN problems
- Application errors
- Hardware failures
- Email delivery issues
- Printer problems
- Network issues

The AI agent classifies and routes these, proposes known fixes from the knowledge base, and — when automation can't fulfil a request — hands it to the IT service desk queue instead of dead-ending. Each hand-off is logged to a Catalog Demand list, so what people ask for but the catalog can't yet do becomes a record of what to automate next.

---

## How Does It Work? (The User Experience)

### Example 1: Password Reset (Fully Automated)

```
1. User submits a ticket in the portal:
   "I forgot my password and need it reset"

2. A Power Automate flow fires on the new ticket and calls the
   Helpdesk Triage Agent. The agent classifies it, sees it's a
   privileged change, and proposes a password-reset action
   (read-only — it can't make the change itself).

3. The request is logged as Ticket #142 · RITM #77 and a manager
   approval card is raised in Teams.

4. Manager gets the approval card in Teams → clicks "Approve"

5. Within 30 seconds:
   - RITM (request item) created
   - SCTASK (work task) created
   - Provisioning Job dispatched to Identity Executor
   - Graph API called to reset password
   - User receives temporary password via secure channel
   - All systems updated: SCTASK → Complete, RITM → Complete, Request → Resolved

6. User is notified, in plain English with the numbers to quote:
   "Your request is done — password reset (Ticket #142 · RITM #77).
   Check your email for the temporary password."
```

**Duration:** < 2 minutes from submission to resolution

---

### Example 2: Knowledge Base Deflection

```
1. User submits a ticket in the portal:
   "My Outlook is showing a red X and won't send email"

2. The triage flow fires and calls the agent, which searches the
   knowledge base and finds article KB0042:
   "Outlook 'Disconnected' Status - Common Fixes"

3. Confidence is high, so the agent deflects: the ticket is
   auto-resolved and closed with the KB answer attached —

   **Outlook Disconnected Status**
   1. Click Send/Receive → Work Offline (toggle it off)
   2. Restart Outlook
   3. Check your internet connection

4. The user gets the resolution on their ticket. No privileged
   change was needed and no IT staff time was consumed.
```

**Duration:** < 1 minute, **auto-resolved from the KB**, no IT staff time consumed

---

### Example 3: Multi-Step Request with Order Guide

```
1. A manager submits a "New Hire Onboarding" request in the portal
   (an Order Guide catalog item), filling in:
   - Full name, Job title, Department, Manager, Start date
   - Equipment needed (laptop model, phone, monitors)

2. The triage flow picks it up; the agent matches it to the New Hire
   Onboarding template and creates Ticket #143 · RITM #78, which generates
   6 work tasks:
   - Create AD account
   - Assign M365 license
   - Add to department groups
   - Order laptop (Dell Latitude 5530)
   - Order phone (iPhone 14)
   - Grant access to finance systems

3. The request routes for approval:
   - Manager approval (for cost center)
   - IT Director approval (for privileged access)

4. Approvals happen sequentially

5. Each task generates a Provisioning Job:
   - Identity Executor creates AD account
   - Licensing Executor assigns license
   - Groups Executor adds to groups
   - Manual SCTASK for laptop procurement (assigned to IT procurement team)
   - Manual SCTASK for phone order
   - Manual SCTASK for finance system access (assigned to Finance IT)

6. Over next 2-3 business days, tasks complete

7. The requester receives a final notification:
   "Your request is done — new hire onboarding for [Name]
   (Ticket #143 · RITM #78). All accounts created, equipment
   ordered. Start date: [Date]."
```

**Duration:** 2-3 business days, **mostly automated** except hardware procurement

---

### Example 4: Needs More Info (Interactive Clarification)

```
1. User submits: "Please add me to the marketing group"

2. The agent isn't sure which group — there are three with
   "marketing" in the name — so it doesn't guess.

3. The requester gets an approval card asking:
   "Which group? Marketing-AU, Marketing-Global, or Marketing-Leads?"

4. The requester answers in the card. Validation re-runs
   automatically with the answer (and can ask again if it's still
   unclear), or the requester clicks Cancel to drop it.

5. Once it has enough, the request continues down the normal
   approve → execute path.
```

**Duration:** as fast as the requester replies — no dead-end, no re-submitting

---

### Example 5: Could Not Be Completed (Honest Failure)

```
1. An approved license assignment runs, but the tenant is out of
   that SKU.

2. The executor reports the failure. The system does NOT mark the
   ticket resolved.

3. The ticket is closed honestly and the requester is told:
   "Your request couldn't be completed — license assignment
   (Ticket #144 · RITM #79). The service desk has been alerted."

4. The IT service desk gets a "fulfilment failed — action needed"
   alert and follows up.
```

**Why it matters:** a failed job never looks like success

---

## What Makes This System Different?

### 1. **AI Proposes, Humans Approve, Machines Execute**

The AI **never** holds write permissions to Microsoft Graph. It can only read and **propose** actions.

```
AI Agent (Copilot Studio)
  ↓ [proposes action]
Approval Flow (Power Automate)
  ↓ [human approves]
Dispatcher (validates + routes)
  ↓ [dispatches to correct executor]
Scoped Service Principal (Identity/Groups/Licensing/etc.)
  ↓ [executes with minimal permissions]
Microsoft Graph API
```

**Security principle:** No single identity can both propose and execute. The approver sees exactly what will happen before it happens.

---

### 2. **Scoped Service Principals (Principle of Least Privilege)**

Instead of one all-powerful admin account, we use **6 specialized service principals**, each with only the permissions it needs:

| Service Principal | Permissions | What It Can Do |
|---|---|---|
| **SP-IT-Identity** | User.ReadWrite.All + UserAuthenticationMethod.ReadWrite.All + Password Administrator role | Reset passwords, manage MFA, enable/disable accounts |
| **SP-IT-Groups** | Group.ReadWrite.All | Add/remove group members, create groups |
| **SP-IT-Licensing** | Organization.ReadWrite.All | Assign/remove licenses |
| **SP-IT-Exchange** | Exchange.ManageAsApp | Grant/revoke mailbox permissions |
| **SP-IT-SharePoint** | Sites.FullControl.All (or Sites.Selected in production) | Restore files, grant permissions |
| **SP-IT-Teams** | Team.Create + Channel.Delete.All + TeamMember.ReadWrite.All | Create channels, manage members |

**Why this matters:** If one executor is compromised, the blast radius is limited to its specific service area. No lateral movement to other systems.

---

### 3. **Full Audit Trail**

Every privileged action creates a **Provisioning Job** record with:

- Who requested it (caller UPN)
- Who approved it (approver UPN + timestamp)
- What was requested (action type + target details in JSON)
- Which service principal executed it
- When it happened (start/finish timestamps)
- What the result was (success/failure + Graph request ID)
- What changed (result JSON)

Audit records are **immutable** after creation and stored in SharePoint for compliance and forensics.

---

### 4. **SLA Management with Business Hours**

The system tracks SLA compliance in **business hours only** (configurable, default: Mon-Fri 9 AM - 5 PM):

- **Priority-based SLA targets:**
  - Critical (P1): 4 hours
  - High (P2): 8 hours
  - Moderate (P3): 24 hours
  - Low (P4): 48 hours

- **Pause on hold** — Clock stops when ticket is waiting on caller or vendor
- **Warning at 75%** — Alerts assigned agent before breach
- **Breach at 100%** — Escalates to manager/team lead
- **Archival after 90 days closed** — Old tickets auto-archived for performance

---

### 5. **Major Incident Detection**

The AI **clusters related incidents automatically**:

```
Scenario: 3 users report "Can't access payroll system" within 1 hour

System detects:
1. Semantic similarity (Triage Agent analyzes ticket descriptions)
2. Temporal proximity (all within 1-hour window)
3. Threshold met (3+ similar incidents)

Action taken:
- Creates one parent Major Incident ticket
- Links the 3 child incidents to parent
- Notifies all agents: "Major Incident declared - Payroll SSO outage"
- Escalates to incident commander
- Broadcasts status updates to affected users
```

**Benefit:** Prevents duplicate work, coordinates response, communicates impact

---

### 6. **Honest Outcomes — No False "Resolved"**

When a job fails, the ticket is **closed** (not marked resolved), the requester is told it couldn't be completed, and the service desk is alerted. A request the automation can't fulfil is handed to the IT service desk queue and logged as catalog demand rather than dead-ending. You always know the real state.

---

### 7. **Interactive Clarification**

When the agent needs more detail it asks on an approval card instead of guessing or giving up. The requester answers in the card and validation re-runs automatically (over several rounds if needed), or they cancel — on both the catalog/request path and form tickets.

---

## Current Capabilities

### ✅ Working today (deployed and validated)

1. **Flow-invoked AI Triage** — a Power Automate flow calls the Copilot Studio Helpdesk Triage Agent to classify tickets, search the KB, and propose actions.
2. **6 Executor Types — all end-to-end validated:**
   - **Identity Executor** — password reset, MFA reset, enable/disable accounts
   - **Groups Executor** — add/remove members, create groups
   - **Licensing Executor** — assign/revoke licenses
   - **Exchange Executor** — grant/revoke mailbox permissions
   - **SharePoint Executor** — file restore, permission grants
   - **Teams Executor** — channel create, member management
3. **Service Catalog** — 8 catalog items (6 single-task + 2 order guides: New Hire Onboarding, User Offboarding)
4. **Request Fulfillment Pipeline** — RITM Generator → Approval → SCTASK Orchestrator → SCTASK-PJ Bridge → Dispatcher → Executors
5. **SLA Timer Flow** — business hours (Mon–Fri 9–16 Sydney), 15-min intervals, pause-on-hold, 75% warning, 100% breach
6. **Archival Flow** — daily 02:00 schedule, 90-day threshold, auto-copy to Tickets-Archive
7. **Major Incident Detection** — Triage Agent semantic clustering, 1-hour window, parent MI creation
8. **18 Categories + 80 Subcategories** — ITIL-aligned taxonomy with JobTypeHints
9. **Approval Workflows** — manager approval (pilot single-stage; full multi-stage policies designed)
10. **Full Audit Trail** — every Provisioning Job with caller UPN, approver, timestamps, Graph request ID, result JSON
11. **Kill Switch** — emergency stop via the Config list `KillSwitch=true`
12. **Knowledge Base** — 40+ published starter articles across common scenarios
13. **Flow-driven intake** — the `ITSM-Triage-Orchestrator` flow calls the agent server-side on each new ticket and acts on its reply
14. **Azure Hardening Resources** — App Insights, Service Bus dispatch topology, and Azure Table idempotency storage provisioned for the pilot hardening path
15. **Interactive clarification** — when triage needs more detail, the requester gets an approval card with the agent's questions; answering re-runs validation automatically (multi-round) or cancels. Works on `RITM-Validation-Triage` and `Triage-Orchestrator`
16. **Honest failure handling** — a failed provisioning job closes the ticket (not resolved), tells the requester it couldn't be completed, and alerts the service desk
17. **Out-of-catalog hand-off** — requests the automation can't fulfil route to the ITSM Service Desk M365 group queue, surface on the portal's Service desk page (Mark fulfilled / Decline), and log to the Catalog Demand list; `ITSM-Handoff-Closure-Notify` tells the requester once the hand-off RITM closes
18. **Structured license intake** — the Submit form's owned-license dropdown plus *Other (not listed)* produces a `RequestPayloadJson` the RITM validation flow reads on a fast path

### Ticket Type Validation Target Design

The current automation depends on `Tickets.TicketType` being correct when the row is created:

- `Request` tickets are picked up by RITM Generator and matched to Service Catalog by subcategory.
- `Incident` tickets are picked up by triage and major incident detection.
- A request-like ticket created as `Incident` will not create a RITM unless it is corrected.

The correction is a two-layer validation system (the post-create layer is live today):

1. **Frontend validation** in the SharePoint portal submit form asks the creator to choose Incident or Request, maps the selected subcategory to active Service Catalog items, and prompts before saving when the selected type does not match the catalog signal.
2. **Post-create validation** in a dedicated `ITSM-Ticket-Type-Validator` flow checks every new Tickets row, auto-reclassifies deterministic low-risk mismatches, and for ambiguous rows sends the requester a clarification approval card (it re-validates on their answer) before RITM, triage, or major incident flows act.

### 🚧 Pilot Shortcuts (Production-Ready Alternatives Designed)

The pilot intentionally uses simplified patterns to prove the loop end-to-end. Each has a production migration path:

| Pilot Shortcut | Production Replacement | Why It Matters |
|---|---|---|
| **Dispatcher trusts SAS URL** | JWT signed by Approval flow, validated by Dispatcher | Secure cross-flow authentication |
| **SharePoint IdempotencyKey field** | Azure Table Storage with If-None-Match ETag | Azure Table idempotency storage is provisioned; ETag-based concurrency control |
| **Executor polls SharePoint list** | Service Bus topic + 6 executor subscriptions | Service Bus dispatch topology is provisioned; smooths Graph throttling |
| **Client secret in Key Vault** | Certificate in HSM-backed Key Vault | Rotation automation, audit compliance |
| **Power Automate run history (28 days)** | App Insights structured logs | App Insights is provisioned for structured audit/telemetry |
| **Manual re-drive for failed jobs** | DLQ + scheduled re-driver flow | Automatic retry with exponential backoff |
| **Single-approver Approval-Bridge** | Multi-stage Approval Policy engine | Manager → IT Owner → CAB workflow |

**All production patterns fully designed** in `decisions/0001-dispatcher-host.md`, `flows/dispatcher/contract.md`, and `flows/approval/spec.md`. Migration is incremental and non-breaking.

---

## Roadmap

Beyond the current pilot:

- **Multi-tenant installer** — deploy to any M365 tenant with one command
- **End-user UI enhancements** — richer Power Apps / Teams app intake
- **Email-to-ticket** — forwarding to a helpdesk mailbox creates a ticket automatically
- **Power BI dashboards** — SLA attainment, MTTR, agent accuracy, deflection rates
- **Problem Management** — root cause analysis, known errors, workarounds
- **Change Management** — risk assessment, CAB workflow, implementation plans
- **Advanced SLA** — breach workflows, escalation chains, OLAs (operational level agreements)

---

## Key Metrics (What Success Looks Like)

### Deflection Rate
**Target:** 40-50% of incoming requests resolved via KB without creating ticket

### Automation Rate
**Target:** 60-70% of tickets auto-resolved after approval (no manual IT work)

### MTTR (Mean Time To Resolution)
- **Automated tickets:** < 5 minutes (request to completion)
- **Manual tickets:** < 24 hours (business hours)
- **Complex incidents:** < 48 hours

### SLA Compliance
**Target:** 95% of tickets resolved within SLA target

### User Satisfaction
**Target:** 4.2+ / 5.0 (measured via post-resolution survey)

---

## Real-World Use Cases

### Scenario 1: Morning Rush (200 Users, Password Resets)
**Problem:** Company forces password reset, 200 users locked out at 8 AM

**Traditional IT:**
- Service desk overwhelmed
- 4-hour queue
- Manual resets take 5 min each = 16+ hours of work

**With This System:**
- 200 users message AI agent
- Agents triage and create requests in parallel
- Managers bulk-approve in 1 click
- All 200 passwords reset in < 10 minutes
- Zero manual IT work

**ROI:** Saved 16 hours of service desk time

---

### Scenario 2: New Hire Onboarding
**Problem:** New employee starts Monday, needs 8 different access items

**Traditional IT:**
- 8 separate tickets to 4 different teams
- 2-3 day turnaround
- New hire idle first week
- High risk of missed items

**With This System:**
- Manager submits "New Hire Onboarding" request Friday
- Order Guide creates all 8 tasks automatically
- Approvals route in parallel
- Automated tasks complete in minutes
- Manual tasks assigned with SLA tracking
- New hire ready to work Monday 9 AM

**ROI:** Saved 3 days of new hire downtime + reduced coordination overhead

---

### Scenario 3: Major Outage Response
**Problem:** Email service down, 50 users report "can't send email"

**Traditional IT:**
- 50 duplicate tickets
- Service desk answers same question 50 times
- Impact not immediately clear
- No centralized status updates

**With This System:**
- AI detects 50 similar tickets in 15 minutes
- Creates parent Major Incident automatically
- All child tickets linked
- One status update broadcasts to all 50 users
- Service desk focuses on resolution, not communication
- Root cause logged for future prevention

**ROI:** Saved 8 hours of duplicate work + improved user communication

---

## Technical Architecture (High-Level)

```
┌─────────────┐
│   Portal    │  User submits a ticket (SPFx web part on SharePoint)
│  (SPFx app) │  — email intake on the roadmap
└──────┬──────┘
       │  creates a Ticket row in
       ▼
┌─────────────────────────────┐
│  SharePoint Lists           │  System of Record (19 lists)
│  - Tickets                  │  - Tickets, RITMs, SCTASKs, PJs
│  - Service Catalog          │  - Categories, KB, Approvals, Config, Catalog Demand
│  - Configuration Items      │
└──────┬──────────────────────┘
       │  new-ticket trigger fires
       ▼
┌─────────────────────────────┐
│  Power Automate Flows       │  Orchestration Layer
│  - Triage Orchestrator      │  - Fires on the new ticket, CALLS the agent
│  - Approval Flow            │  - Routes approvals
│  - Dispatcher Flow          │  - Validates & dispatches PJs
│  - RITM/SCTASK Orchestrator │  - Manages request lifecycle
└──────┬──────────────────────┘
       │  triage flow calls the agent (read-only)
       ▼
┌─────────────────────────────┐
│  Copilot Studio Agent       │  READ-ONLY: classifies, searches KB,
│  (Helpdesk Triage Agent)    │  returns deflect / ask / propose / hand-off
└──────┬──────────────────────┘
       │  a "propose" outcome → approval → dispatch
       ▼
┌───────────────────────────────────────────────────────────┐
│  6 Executor Flows (each with scoped Service Principal)    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │ Identity │  │  Groups  │  │Licensing │  │ Exchange │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘ │
│  ┌──────────┐  ┌──────────┐                              │
│  │SharePoint│  │  Teams   │                              │
│  └──────────┘  └──────────┘                              │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────┐
│  Microsoft Graph API        │  Microsoft 365 write operations
│  - Entra ID                 │  (password reset, group add, etc.)
│  - Exchange Online          │
│  - SharePoint/OneDrive      │
│  - Microsoft Teams          │
└─────────────────────────────┘
```

Two paths aren't drawn above. When the agent needs more detail (the *ask* outcome) it sends the requester a clarification approval card and re-validates on their answer. When a request can't be automated (the *hand-off* outcome) it goes to the ITSM Service Desk queue — worked from the portal's Service desk page and logged to the Catalog Demand list — and `ITSM-Handoff-Closure-Notify` tells the requester once it's closed.

---

## Summary: What Problem Are We Solving?

**The Problem:**
- Dedicated ITSM platforms are typically licensed per agent per month, which adds up quickly for a small team
- Level 1 helpdesk work is repetitive and automatable
- Users struggle to find the right form or contact
- IT staff overwhelmed with password resets and group adds
- No transparency into ticket status
- Manual work prone to errors and delays

**Our Solution:**
- **Zero additional licensing** — Runs on existing M365 E3/E5
- **AI-powered triage** — 40-50% tickets resolved via KB
- **Automated execution** — 60-70% of remaining tickets auto-resolved after approval
- **Self-service portal** — Submit a ticket; the AI handles the triage
- **Full audit trail** — Every action traceable and compliant
- **Security by design** — AI proposes, humans approve, scoped machines execute

**Bottom Line:**
Covers the common Level-1 ITSM workflows that small and medium businesses rely on most — ticket intake, AI triage, approvals, and automated fulfilment — running on the Microsoft 365 stack you already pay for, with no separate per-agent ITSM subscription.
