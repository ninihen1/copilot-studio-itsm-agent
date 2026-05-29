**AI-Augmented ITSM on Microsoft 365**

*Design Memo — Agents, Architecture & Open Items*

Owner: **Catherine Han**   ·   Date: 29 April 2026   ·   Status: *Draft for review*

# **1. Overview**

We are designing an AI-assisted IT helpdesk on the Microsoft 365 stack — SharePoint as the system of record, Power Automate for orchestration, and Copilot Studio for the user-facing agents. The goal is a ServiceNow-style ticketing experience without the ServiceNow licence cost, with AI that triages and proposes actions but never executes privileged writes without a human approval.

This document covers the agent layer and gaps not already captured in the schema spreadsheet or the architecture flowchart.

### **Companion artefacts**

- **sharepoint-itsm-schema.xlsx** — 13 SharePoint lists, full column-level schema, choices, performance notes.

- **itsm-ai-workflow-flowchart.pdf** — six-stage architecture diagram (Intake → Triage → Approval → Dispatch → Execution → Audit).

- **servicenow-itsm-ticketing-report.md** — research on the ServiceNow modules we are mirroring.

# **2. Glossary**

Plain-language definitions of the terms used throughout this document.

| Term | What it means |
|---|---|
| ITSM | IT Service Management — the practice (and tooling) of running an IT helpdesk: tickets, incidents, requests, changes, knowledge, SLAs. |
| CMDB | Configuration Management Database. The inventory of everything tickets can be raised against — apps, services, servers, databases, SaaS subscriptions. Each entry is a "CI" (Configuration Item). Lets us answer "what is the user actually talking about?" and route automatically. |
| CI | Configuration Item — one entry in the CMDB. Examples: the Salesforce app, the corporate Wi-Fi service, the production SQL database. |
| HITL | Human-in-the-Loop. Pattern where AI proposes an action but a human approves before anything executes. Our default for every write action. |
| Service Principal | A non-human identity in Entra ID with its own permissions. We use one per category (Identity, Groups, Licensing, Exchange, SharePoint, Teams) so each flow has only the access it needs — no all-powerful admin account. |
| Idempotency | Property that running the same operation twice produces the same result as running it once. Critical when retries happen — prevents creating two users or assigning two licences. |
| Saga / Compensation | Pattern for multi-step operations. If step 3 fails after steps 1 and 2 succeeded, the saga runs "compensation" steps to undo them. Used when a request needs several writes that must all succeed or all roll back. |
| Approval Policy | A reusable, named approval workflow with one or more stages (Manager, IT Owner, CAB, etc.). Catalogue items and categories reference policies rather than hardcoding approvers. |
| Dispatcher | A single HTTP endpoint (POST /provisioning/jobs) that every agent calls. The dispatcher validates approval and idempotency, then routes to the right specialised flow. Single choke-point for audit and kill-switch. |
| Provisioning Job | One row in the audit list per privileged write. Captures who authorised it, what was attempted, what happened, and which service principal executed. |



# **3. Architecture at a Glance**

Six stages, top to bottom. The full diagram is in itsm-ai-workflow-flowchart.pdf.

| Stage | Layer | What happens |
|---|---|---|
| 1. Intake | Outlook · Teams · Portal · Voice | Ticket created in SharePoint Tickets list. All channels normalise to the same record. Portal intake validates Incident vs Request before save where possible. |
| 2. Triage | AI (read-only) | Ticket-type validation gate confirms the row should enter triage or request fulfillment. Triage Agent classifies, links to CI, matches KB, suggests assignee, proposes resolution. No writes. |
| 3. Approval | Human-in-the-loop | Confidence + risk gate. High-confidence/low-risk → auto-resolve. Write actions → Approval Policy stages (Manager / IT Owner / CAB). |
| 4. Dispatch | Single HTTP endpoint | POST /provisioning/jobs validates approval and idempotency, then routes by jobType. |
| 5. Execution | Specialised flows | Six categories: Identity, Groups, Licensing, Exchange, SharePoint/OneDrive, Teams/Endpoint. Each behind its own scoped service principal. |
| 6. Audit & Notify | Provisioning Jobs · Tickets · User comms | Result, work notes, status, notification — every write traceable to its approval. |



# **4. Agents to Build**

One primary agent is mandatory; two satellites are optional and can be deferred to phase 2.

## **4.1 Helpdesk Triage Agent (primary — required)**

### **Purpose**

The single user-facing agent. Receives a request from any channel, classifies it, attempts deflection via knowledge base, and either resolves directly (low-risk reads) or proposes an action for human approval. Never executes privileged writes itself.

### **Surfaces & identity**

- Teams: 1:1 chat with the bot, plus @mention in channels.

- Outlook: forward-to-bot mailbox creates a ticket from the email body.

- Service Portal: embedded chat widget on the internal portal.

- Caller identity: resolved from M365 SSO context. The agent must pass the caller UPN into every tool call — no anonymous tickets.

### **Tools (all read-only)**

| Tool | Purpose | Backing source |
|---|---|---|
| SearchKB(query, audience) | Find published articles | Knowledge Base list, filtered Status=Published & audience-aware |
| LookupCMDB(name) | Resolve affected CI / business service | Configuration Items list |
| LookupUser(query) | Resolve people (manager, delegate, named user) | Microsoft Graph /users |
| GetSimilarTickets(symptoms) | Find related or duplicate tickets | Tickets list, semantic search |
| MatchProblem(symptoms) | Link to known errors | Tickets list filtered Type=Problem |
| GetCategoryTaxonomy() | Return active categories + subcategories | Categories list |
| GetServiceCatalog(query) | Find catalogue item for a request | Service Catalog list |
| ProposeAction(...) | Write a proposal (not an execution) into Tickets and create a Provisioning Job in Queued status | SharePoint write — proposal only |



### **Behaviour contract**

- **Always classify first.** Set TicketType (Incident / Request / Change / Problem), Category, Subcategory, Impact, Urgency.

- **Validate request vs incident before automation.** If the selected subcategory maps to an active Service Catalog item, prefer Request and confirm mismatches before downstream flows create RITMs, Provisioning Jobs, or major incident links.

- **Always attempt deflection.** If SearchKB confidence ≥ 0.85, offer the article and ask "did this resolve it?" before creating a ticket.

- **Never execute writes directly.** Hand-off is via ProposeAction, which puts the job in front of the Approval flow.

- **Handle ticket comments as user signals.** When a caller comments on an Awaiting Caller ticket, resume the ticket and return it to the active helpdesk queue. When a caller comments on a Resolved ticket, reopen it for review. Comments on In Progress tickets notify the assigned IT staff without changing the ticket status. Internal work notes notify IT followers only and do not trigger caller-facing automation.

- **Score every proposal.** Confidence 0–1, risk = {low, medium, high} based on action type. Low-risk + high-confidence is eligible for auto-approve. Otherwise human gate.

- **Stop and ask** when classification confidence < 0.7, multiple CIs match, target user is ambiguous, or the action affects more than one person.

### **Output payload (every interaction)**

| ticketId, type, category, subcategory, impact, urgency, callerUpn, targetUserUpn, ciId, proposedAction { jobType, args }, confidence, risk, kbArticlesShown, rationale. |
|---|



### **System-prompt anchors**

- Least-privilege language: "propose, never execute".

- Safe-default language: "if unsure, route to human queue".

- Refusal scope: no performance evaluation, no protected-class profiling, no bulk operations on more than 5 users.

## **4.2 Self-Service Resolver (optional — deflection layer)**

A lighter agent that runs before Triage. Pure knowledge-base Q&A. If it cannot deflect within two turns, it hands off to Triage with conversation history attached.

Worth building if your knowledge base is mature. Skip for v1 if the KB is thin — deflection rate will be poor and the extra hop adds latency.

## **4.3 Major Incident Detector (optional — scheduled)**

A background agent (or a scheduled Power Automate flow) that runs every 5 minutes. Scans tickets opened in the last 30 minutes for clusters: same CI, same category, three or more unique callers. On match, it creates a parent Major Incident ticket, links the children via ParentTicket, and posts to a dedicated Major Incidents Teams channel.

Can be deferred to phase 2 if your incident volume is currently low.

# **5. Gaps & Open Items**

These are not blockers, but you will hit them in roughly this order. Build-time issues affect launch. Operational issues affect day-2 reliability. Governance issues affect long-term ownership.

## **5.1 Build-time gaps**

| Item | What it is and why it matters |
|---|---|
| CMDB seed data | Your Triage Agent is only as good as your CMDB. Plan a one-time import (Intune + ServiceNow export + manual entries for business services). Without this, CI linking is empty and routing fails. |
| KB seeding | At least 30–50 published articles before the agent goes live, otherwise deflection rate is zero. Articles often emerge from resolved tickets — but you need the starter set first. |
| SLA timer flow | Scheduled Power Automate that compares OpenedDate + Priority.ResolutionHours against now, and escalates at 75% and 100% of the SLA window. Not in the architecture diagram today. |
| Notification templates | Adaptive cards for: approval request, approval granted/denied, ticket resolved, SLA breach. Centralise these so the look-and-feel is consistent and changes happen in one place. |
| Secrets management | Store service principal certificates in Azure Key Vault, not in Power Automate connections directly. Define a per-SP cert rotation policy. |



## **5.2 Operational gaps**

| Item | What it is and why it matters |
|---|---|
| Global kill switch | A single Yes/No flag (SharePoint list or App Configuration) that the dispatcher checks before executing any write. Lets you pause all AI writes in 5 seconds if something goes wrong. Non-negotiable. |
| Per-SP rate limits | Microsoft Graph throttling will bite at scale. Add per-service-principal retry-with-backoff in each specialised flow, and surface throttling events to the dispatcher. |
| Phased rollout plan | Recommended sequence: (a) read-only triage for 2 weeks, (b) auto-resolve KB only, (c) password reset only, (d) full catalogue. Do not enable everything on day one. |
| Feedback loop | When a ticket is reopened or a proposed action is rejected, that signal must feed back to the agent (telemetry list + weekly review). Not in the architecture today, but required for the agent to improve. |
| Reporting layer | Power BI on top of Tickets, Provisioning Jobs, and Approvals. SLA attainment, agent accuracy, cost per ticket, top categories, top failures. |



## **5.3 Governance gaps**

| Item | What it is and why it matters |
|---|---|
| RACI | Who owns the agent prompt? Who can edit specialised flows? Who approves new job types being added to the dispatcher? Decide before launch. |
| Audit review cadence | Someone needs to spot-check Provisioning Jobs weekly for the first quarter. Pick the person, set a recurring meeting, define the checklist. |
| Cost monitoring | Copilot Studio messages, Power Automate runs, Microsoft Graph calls. Set tenant-level alerts so a runaway agent or flow does not produce a bill surprise. |



# **6. Next Steps**

Proposed sequence to get to a usable pilot in roughly six weeks.

| Week | Focus | Outcome |
|---|---|---|
| 1 | SharePoint lists | All 13 lists provisioned per the schema spreadsheet. CMDB and KB seed data loaded. |
| 2 | Dispatcher + first flow | POST /provisioning/jobs endpoint live. One specialised flow (Reset Password) end-to-end with idempotency and audit. |
| 3 | Triage Agent v1 | Read-only agent in Copilot Studio. Classify + KB deflection only. Available in Teams to a small pilot group. |
| 4 | Approval engine | Approval Policies and Stages working. Manager-approval path for Reset Password live. |
| 5 | Add 2–3 more flows | Add to Group, Assign Licence, Disable User. Each behind its own scoped service principal. |
| 6 | Pilot review + harden | Feedback loop, kill switch, SLA timer, reporting baseline. Decision: expand pilot or production cut-over. |



| Open questions for the team: Which tenant for the pilot? Who is the named owner for each of the six service principals? Do we want to ship v1 with auto-approve for any action, or is every write human-gated for the first quarter? |
|---|

