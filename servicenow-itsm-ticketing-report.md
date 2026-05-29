# ServiceNow IT Ticketing & Request Management: A Detailed Reference

**Research date:** 2026-04-29
**Scope:** ServiceNow ITSM modules, table schemas, request taxonomy, common fields, priority matrix, workflow states, and integration points.
**Versions referenced:** Xanadu (Q3 2024) and Zurich (2025) product releases. Concepts are stable across releases unless flagged.
**Confidence (overall):** HIGH for OOB structure (vendor docs cross-confirmed); MODERATE for organization-specific customizations (which legitimately vary).

---

## Executive Summary

> **Key Finding:** ServiceNow's IT ticketing platform is an extensible task-record system anchored on the `task` parent table, from which `incident`, `problem`, `change_request`, `sc_request`, `sc_req_item`, and `sc_task` all inherit. Two distinct ticket families coexist: **break/fix** (Incident, Problem, Change) and **fulfillment** (Request, RITM, SCTASK driven by the Service Catalog). Both share core fields (number, caller, assignment_group, state, priority) but have separate state machines and resolution semantics.
>
> **Confidence:** HIGH
>
> **Action:** Use the schemas and state diagrams below as a blueprint. Distinguish "out-of-the-box" (OOB) behavior from organizational customization in any taxonomy you design.

ServiceNow ITSM ships seven core processes ([ServiceNow ITSM product page](https://www.servicenow.com/products/itsm.html)): Incident, Problem, Change, Request, Knowledge, Configuration (CMDB), and Service Level. The most-used end-user surface is the **Service Catalog** (orderable items) plus the **Incident form** (break/fix). HR Service Delivery (HRSD) is a separate but architecturally similar product that uses the `hr_case` table family and shares the Employee Center portal ([HRSD docs](https://www.servicenow.com/docs/bundle/zurich-employee-service-management/page/product/human-resources/concept/c_LifecycleEventsHRSD.html)).

The **3x3 Impact x Urgency priority matrix** producing Priority 1-5 (Critical, High, Moderate, Low, Planning) is OOB and is implemented via Data Lookup Rules on the `incident` table ([ServiceNow Community OOB matrix](https://www.servicenow.com/community/virtual-agent-forum/incident-priority-matrix-current-oob/m-p/3413018), [The Snowball: Priority Matrix](https://thesnowball.co/the-servicenow-priority-matrix-impact-and-urgency)). The **incident lifecycle** (New → In Progress → On Hold → Resolved → Closed, plus Canceled) is documented verbatim by ServiceNow's Xanadu docs ([Life cycle of an Incident](https://www.servicenow.com/docs/r/xanadu/it-service-management/incident-management/c_IncidentManagementStateModel.html)). The **change lifecycle** (New → Assess → Authorize → Scheduled → Implement → Review → Closed, plus Canceled) and three change types (Standard, Normal, Emergency) are documented by ServiceNow's Zurich docs ([Change State Model](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html)).

---

## 1. Architecture: The Task Inheritance Model

ServiceNow's ticketing primitives are all extensions of a common parent table called `task`. A child table inherits every field of its parent and may add its own ([The Snowball: Task table](https://thesnowball.co/the-servicenow-task-table)).

```
task (parent)
├── incident                     -- break/fix, restore service
├── problem                      -- root-cause investigation
├── change_request               -- planned modification
├── sc_request        (REQ)      -- container/order header
│   └── sc_req_item   (RITM)     -- one fulfillment line per catalog item
│       └── sc_task   (SCTASK)   -- worker tasks against a RITM
└── hr_case (HRSD)               -- separate but parallel structure
```

**Why this matters:** any field defined on `task` (e.g., `number`, `sys_id`, `opened_at`, `opened_by`, `assigned_to`, `assignment_group`, `state`, `priority`, `short_description`, `description`, `work_notes`, `comments`, `sla_due`, `closed_at`, `closed_by`, `close_notes`) appears on every ticket type ([Snowball: task table](https://thesnowball.co/the-servicenow-task-table)). Reporting, SLAs, and notifications can therefore be designed once and reused.

**Confidence:** HIGH. Confirmed by vendor schema and multiple practitioner references.

---

## 2. Module-by-Module Detail

### 2.1 Incident Management (`incident`)

**Purpose:** Restore normal service operation as quickly as possible after an unplanned interruption, quality reduction, or CI failure ([ServiceNowGyan: Incident Management](https://servicenowgyan.com/incident-management-in-servicenow/)).

#### Lifecycle (OOB)

| State | Description |
|-------|-------------|
| **New** | Incident is logged but not yet investigated. |
| **In Progress** | Incident is assigned and is being investigated. |
| **On Hold** | Responsibility shifts temporarily for further info, evidence, or resolution. Sub-reason required. |
| **Resolved** | A satisfactory fix is provided. |
| **Closed** | Marked Closed after Resolved for a specific duration and resolution is confirmed. |
| **Canceled** | Triaged but found to be a duplicate, unnecessary, or not an incident. |

Source: [ServiceNow Xanadu docs - Life cycle of an Incident](https://www.servicenow.com/docs/r/xanadu/it-service-management/incident-management/c_IncidentManagementStateModel.html), corroborated by [ServiceNowGyan](https://servicenowgyan.com/incident-management-in-servicenow/) and [UnoGeeks](https://unogeeks.com/incident-states-in-servicenow/).

**On Hold sub-reasons (OOB):** Awaiting Caller, Awaiting Change, Awaiting Problem, Awaiting Vendor. If reason is "Awaiting Caller", `Additional comments` becomes mandatory; when the caller updates the incident, state automatically returns to In Progress ([Xanadu docs](https://www.servicenow.com/docs/r/xanadu/it-service-management/incident-management/c_IncidentManagementStateModel.html)).

**Customization caveat:** Many customer instances rename or extend states. UC Berkeley's instance, for example, has Assigned, Work in Progress, Waiting on Customer, Waiting on Vendor, Customer Responded, Customer Reopened, Resolved, Closed (auto after 5 days) ([Berkeley KB0012297](https://berkeley.service-now.com/kb_view.do?sys_kb_id=c511fa5d1b57ef40bc27feeccd4bcb23)). Any taxonomy you design should explicitly choose between staying close to OOB (recommended for upgrade safety) vs. branching.

#### Core Fields (incident table)

| Field | Type | Notes |
|-------|------|-------|
| `number` | string | Auto-numbered, prefix `INC` |
| `sys_id` | GUID | Internal unique key |
| `caller_id` | reference (sys_user) | Who reported |
| `opened_by` | reference | Often = system or service desk agent |
| `opened_at` / `closed_at` | datetime | Timestamps |
| `category` / `subcategory` | string (choice) | Drives subcategory cascade |
| `business_service` / `service_offering` | reference | Service-portfolio CIs |
| `cmdb_ci` | reference (cmdb_ci) | Configuration Item |
| `impact` | choice 1-3 (High/Medium/Low) | Driver for priority |
| `urgency` | choice 1-3 (High/Medium/Low) | Driver for priority |
| `priority` | choice 1-5 (read-only, derived) | Critical/High/Moderate/Low/Planning |
| `assignment_group` | reference (sys_user_group) | Owning queue |
| `assigned_to` | reference (sys_user) | Individual owner |
| `state` | integer choice | See lifecycle above |
| `incident_state` | integer | Mirrors state (legacy, often used by SLAs) |
| `hold_reason` | choice | Required when state=On Hold |
| `short_description` | string | One-line summary |
| `description` | string (large) | Full detail |
| `work_notes` | journal | Internal-only updates |
| `comments` | journal | Customer-visible updates |
| `close_code` | choice | Resolution categorization (e.g., Solved Permanently, Solved Workaround, Not Solved (Not Reproducible), Closed/Resolved by Caller, Duplicate) |
| `close_notes` | string | Resolution narrative |
| `caused_by` | reference (change_request) | If a change caused the incident |
| `problem_id` | reference (problem) | If linked to a known problem |
| `parent_incident` | reference (incident) | For major-incident children |
| `made_sla` | boolean | SLA met flag |
| `reopen_count` | integer | How many times reopened |

Source: [ServiceNowGyan field overview](https://servicenowgyan.com/incident-management-in-servicenow/), corroborated by [The Snowball: Task table](https://thesnowball.co/the-servicenow-task-table) and [UCSD field reference](https://blink.ucsd.edu/_files/technology-tab/servicenow/servicenow-fields-2.pdf).

#### OOB Incident Categories

The shipped Category choice list is intentionally generic so customers tailor it. Defaults seen across multiple references:

- **Inquiry / Help**
- **Software**
- **Hardware**
- **Network**
- **Database**

Subcategories cascade from category (the Subcategory field's choices depend on the selected Category) ([ServiceNowGyan](https://servicenowgyan.com/incident-management-in-servicenow/)). Most enterprise deployments expand this to 8-15 categories; see Section 5 for a recommended request taxonomy.

**Confidence:** HIGH on lifecycle and field set. MODERATE on default category list (vendor allows customization, defaults vary slightly across releases).

---

### 2.2 Problem Management (`problem`)

**Purpose:** Identify and manage root causes of one or more incidents, prevent recurrence, document workarounds and known errors ([ServiceNow Problem Management product page](https://www.servicenow.com/products/itsm/what-is-problem-management.html)).

#### Lifecycle (OOB - 6 states)

| State | Description |
|-------|-------------|
| **New** | Problem record created |
| **Assess** | Initial triage / qualification |
| **Root Cause Analysis** | Investigation underway |
| **Fix in Progress** | Permanent fix being implemented (often a change_request) |
| **Resolved** | Root cause eliminated |
| **Closed** | Final state; lessons documented |

Source: [ServiceNow Problem Management product page](https://www.servicenow.com/products/itsm/what-is-problem-management.html) and [community articles](https://www.servicenow.com/community/itsm-articles/problem-management-overview/ta-p/2378152).

#### Key Fields (in addition to inherited task fields)

| Field | Notes |
|-------|-------|
| `number` | Prefix `PRB` |
| `problem_state` | Mirrors state (integer) |
| `known_error` | boolean - flips to true when workaround/root cause documented |
| `workaround` | string - temporary mitigation |
| `cause_notes` / `fix_notes` | Root cause and fix narrative |
| `major_problem` | boolean |
| `rfc` | reference (change_request) - the "Request for Change" implementing the fix |
| `first_reported_by_task` | reference - first incident that surfaced it |

Problems often spawn a `change_request` (the RFC field) and are linked from many incidents via `incident.problem_id` ([ServiceNow Problem product page](https://www.servicenow.com/products/itsm/what-is-problem-management.html)).

**Confidence:** HIGH on lifecycle (vendor product page + community); MODERATE on every field (some named fields are scoped/optional).

---

### 2.3 Change Management (`change_request`)

**Purpose:** Add, modify, or remove anything that could affect IT services, with controlled risk ([ServiceNow Zurich Change docs](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html)).

#### Three Change Types

| Type | Definition | Approval path |
|------|-----------|---------------|
| **Standard** | Pre-approved, low-risk, repeatable. Driven by Standard Change Catalog templates. | Pre-approved; bypasses CAB |
| **Normal** | Non-standard changes requiring assessment, approval, scheduling. | Goes through CAB (Change Advisory Board) review |
| **Emergency** | Unplanned, high-urgency change to fix major incident or vulnerability. | Reduced flow; jumps to Authorize, often using ECAB |

Source: [Standard Change Catalog (Zurich docs)](https://www.servicenow.com/docs/bundle/zurich-it-service-management/page/product/change-management/concept/c_StandardChangeCatalog.html) and [State Model and Transitions](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html).

#### Lifecycle (OOB)

```
New → Assess → Authorize → Scheduled → Implement → Review → Closed
                                                          ↘ Canceled (any stage)
```

State transitions trigger email notifications to stakeholders at Scheduled, Implement, Review, and Canceled. Change type can be modified only while in **New** ([Zurich docs](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html)).

For Emergency changes, the state machine collapses Assess and skips directly toward Authorize so urgent fixes are not blocked by full CAB review ([Zurich Change Management docs](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html)).

#### Key Fields (change_request)

| Field | Notes |
|-------|-------|
| `number` | Prefix `CHG` |
| `type` | Standard / Normal / Emergency |
| `risk` | High / Moderate / Low (often calculated from risk assessment) |
| `risk_impact_analysis` | text narrative |
| `category` / `chg_model` | choice / reference (chg_model) |
| `cmdb_ci` / `cmdb_ci_class` | what's being changed |
| `start_date` / `end_date` | planned implementation window |
| `work_start` / `work_end` | actual times |
| `reason` | business justification |
| `implementation_plan` / `backout_plan` / `test_plan` | required text fields for Normal |
| `cab_required` | boolean |
| `cab_date` / `cab_recommendation` | CAB scheduling and outcome |
| `approval` | derived from `sysapproval_approver` records (see Section 4.3) |
| `state` | integer; matches lifecycle above |

Source: [ServiceNow Zurich docs](https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html), [CAB Workbench](https://www.servicenow.com/docs/bundle/zurich-it-service-management/page/product/change-management/concept/c_CABWorkbench.html), [Standard Change Catalog](https://www.servicenow.com/docs/bundle/zurich-it-service-management/page/product/change-management/concept/c_StandardChangeCatalog.html).

**Confidence:** HIGH (vendor docs primary source).

---

### 2.4 Service Request (Request Fulfillment) — REQ / RITM / SCTASK

**Purpose:** Fulfill standard, repeatable user requests via the Service Catalog (e.g., new laptop, software install, access grant). Distinct from Incident: requests are **expected, planned work**, incidents are **unplanned interruptions**.

#### Three-tier hierarchy

| Tier | Table | Prefix | Role |
|------|-------|--------|------|
| Order header | `sc_request` | **REQ** | One per shopping-cart submission. Holds approvals at the order level, requested-for, total cost. |
| Line item | `sc_req_item` | **RITM** | One per catalog item ordered. Holds the variables (the user's choices) and item-level state. |
| Worker task | `sc_task` | **SCTASK** | One or many per RITM, generated by the workflow/Flow Designer. Each task is assigned to a fulfillment group. |

A single submission with three different items produces 1 REQ + 3 RITMs, and each RITM may spawn one or several SCTASKs (e.g., "Provision laptop", "Create AD account", "Ship to address") ([The Snowball: Service Catalog tables](https://thesnowball.co/the-servicenow-service-catalog-request-tables)).

#### RITM State Values (integer-encoded)

| Integer | Label |
|---------|-------|
| -5 | Pending Approval |
| 1 | Open |
| 2 | Work in Progress |
| 3 | Closed Complete |
| 4 | Closed Incomplete |
| 7 | Closed Skipped |

Source: [Broadcom KB on RITM states](https://knowledge.broadcom.com/external/article?articleNumber=247519), corroborated by [The Snowball: Catalog tables](https://thesnowball.co/the-servicenow-service-catalog-request-tables). Confidence: MODERATE (only one fully-numeric source; semantics confirmed by multiple).

#### Variables (the dynamic form data)

Catalog item variables are stored not as columns on `sc_req_item` but in a **many-to-many** join table `sc_item_option_mtom` linking each RITM row to one or more `sc_item_option` rows (the user's answers). Definitions live in `item_option_new` and grouped definitions in `sc_variable_set` ([ServiceNow Variables and Variable Sets docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/build/service-creator/concept/c_VariablesAndVariableSets.html), [Snowball](https://thesnowball.co/the-servicenow-service-catalog-request-tables)).

Variable types include: Single Line Text, Multi Line Text, Select Box, Multiple Choice, Reference, List Collector, Lookup Select Box, Date, Date/Time, Checkbox, Container Start/End, Macro, HTML, Attachment ([Variables docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/build/service-creator/concept/c_VariablesAndVariableSets.html)).

#### Catalog Building Blocks

| Construct | Purpose |
|-----------|---------|
| **Catalog Item** (`sc_cat_item`) | Single orderable thing. Has variables, workflow/flow, price, picture. |
| **Variable Set** (`sc_variable_set`) | Reusable group of variables (e.g., "Address Block") shared across items. |
| **Record Producer** (`sc_cat_item_producer`) | Catalog UX that creates a non-task record (e.g., creates an `incident` from a guided form). The "Submit a Get Help" form is typically a record producer. ([Record Producers docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/service-catalog-management/concept/c_RecordProducer.html)) |
| **Order Guide** (`sc_cat_item_guide`) | Bundles multiple catalog items into a single guided experience (e.g., "New Hire" orders Laptop + Phone + Software in one flow). ([Order Guides docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/service-catalog-management/concept/c_OrderGuides.html)) |
| **Flow Designer / Workflow** | Orchestrates approvals, SCTASK creation, integrations. |

**Confidence:** HIGH on architecture (vendor docs), MODERATE on integer state values (single direct source but semantics confirmed elsewhere).

---

### 2.5 Knowledge, CMDB & Asset Management Integration

#### CMDB (`cmdb_ci` and class table per CI type)

The CMDB stores **operational** records of every Configuration Item (CI) and their relationships. Key tables: `cmdb_ci` (root, with class-specific descendants like `cmdb_ci_computer`, `cmdb_ci_app_server`, `cmdb_ci_service`, etc.), and `cmdb_rel_ci` (relationships) ([Configuration Management docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/configuration-management/concept/c_ITILConfigurationManagement.html)).

Tickets reference CIs via the `cmdb_ci` field on each task table - this is how ServiceNow correlates outages to services and identifies impact.

#### Asset Management (`alm_asset` and class-specific descendants)

Asset Management tracks the **financial and lifecycle** properties of assets: procurement cost, depreciation, vendor, warranty, lease, stockroom location, asset state (in stock, in use, retired, disposed) ([Asset vs Configuration Management - ServiceNow Community](https://www.servicenow.com/community/asset-management-articles/the-difference-between-asset-and-configuration-management/ta-p/2308716), [Snowball: Asset tables](https://thesnowball.co/the-servicenow-asset-management-tables)).

| Aspect | CMDB (cmdb_ci) | Asset (alm_asset) |
|--------|----------------|-------------------|
| Purpose | Operational, "is it working?" | Financial, "what does it cost / who owns it?" |
| Lifecycle | tied to service | tied to procurement → disposal |
| Owner | Service Owner / TSC | IT Asset Manager / Finance |
| Examples | server.example.com, ERP service | Dell laptop SN#XYZ, Oracle license #123 |

The two are linked: an `alm_hardware` row will typically reference its corresponding `cmdb_ci_computer` row via the `ci` field, providing a unified view ([Asset/CMDB community article](https://www.servicenow.com/community/asset-management-articles/the-difference-between-asset-and-configuration-management/ta-p/2308716)).

**Confidence:** HIGH.

---

### 2.6 HR Service Delivery (HRSD) - the cross-over

HRSD is sold as a separate product but uses the same task-record paradigm. Primary tables: `hr_case` (parent), with derivative case types (e.g., `sn_hr_core_case_payroll`, `sn_hr_core_case_benefits`). HRSD adds **Lifecycle Events** for orchestrated multi-team flows: onboarding, offboarding, leave of absence, return-to-work, transfer, retirement ([HRSD Lifecycle Events docs](https://www.servicenow.com/docs/bundle/zurich-employee-service-management/page/product/human-resources/concept/c_LifecycleEventsHRSD.html), [HRSD product page](https://www.servicenow.com/products/hr-service-delivery.html)).

**Crucial cross-over:** Onboarding kicks off both HR cases AND IT requests (laptop, accounts, software access). The integration is typically wired via a Lifecycle Event activity that creates the IT order through an Order Guide. The **Employee Center** is the unified portal that surfaces both HR and IT catalogs to employees.

**Confidence:** HIGH on architecture, MODERATE on specific table names (HRSD evolves quickly across releases).

---

## 3. The Priority Matrix (Impact x Urgency → Priority)

ServiceNow's OOB priority is **derived**, not directly set by the user. The `priority` field on the incident form is read-only and is computed from `impact` and `urgency` via Data Lookup Rules in `dl_u_priority` (System Policy > Rules > Priority Data Lookups) ([The Snowball: Priority Matrix](https://thesnowball.co/the-servicenow-priority-matrix-impact-and-urgency)).

### OOB 3 x 3 Matrix

|  | **Urgency 1 (High)** | **Urgency 2 (Medium)** | **Urgency 3 (Low)** |
|---|---|---|---|
| **Impact 1 (High)** | **1 - Critical** | 2 - High | 3 - Moderate |
| **Impact 2 (Medium)** | 2 - High | 3 - Moderate | 4 - Low |
| **Impact 3 (Low)** | 3 - Moderate | 4 - Low | **5 - Planning** |

Sources: [ServiceNow Community OOB priority matrix](https://www.servicenow.com/community/virtual-agent-forum/incident-priority-matrix-current-oob/m-p/3413018), [UC Berkeley Impact/Urgency/Priority Guide KB0010891](https://berkeley.service-now.com/kb_view.do?sysparm_article=KB0010891), [The Snowball Priority Matrix](https://thesnowball.co/the-servicenow-priority-matrix-impact-and-urgency).

### Definitions (illustrative, derived from Berkeley KB0010891)

**Impact** (extent of damage / number affected):
- **High (1):** Large number of staff affected; financial impact > $10K (illustrative); reputational damage high; possible injury.
- **Medium (2):** Moderate staff/customer impact; $1K-$10K range; moderate reputational impact.
- **Low (3):** Minimal staff affected; <$1K; minimal reputational impact.

**Urgency** (how rapidly damage increases):
- **High (1):** Damage increases rapidly; work highly time-sensitive; minor incident risks becoming major; multiple VIPs affected.
- **Medium (2):** Damage increases considerably over time; one VIP affected.
- **Low (3):** Damage increases marginally; not time sensitive.

Source: [UC Berkeley KB0010891 (illustrative customer adaptation)](https://berkeley.service-now.com/kb_view.do?sysparm_article=KB0010891). These thresholds are deployment-specific; OOB ServiceNow ships labels only.

### Practitioner caveat

A widely-cited pattern: end users tend to over-report Priority 1, with significant "false alarm" rates (>50% in some shops) ([The Snowball](https://thesnowball.co/the-servicenow-priority-matrix-impact-and-urgency)). Mitigations include:

- Restricting Impact/Urgency choices for end-user portal forms
- Triaging P1 through service desk before auto-paging on-call
- Periodic post-mortem reviews of P1 categorization

**Confidence:** HIGH on matrix mechanics (3 sources). MODERATE on definitions (deployment-specific).

---

## 4. Common Service Catalog Items, Categories, and Variables

### 4.1 Recommended Top-Level Request Categories (industry-standard taxonomy)

Synthesized from [Beyond20: Service Catalog Best Practices](https://www.beyond20.com/blog/servicenow-service-catalog-best-practices/), [ServiceNow Community discussions](https://www.servicenow.com/community/itsm-forum/incident-category-and-subcategory-list/m-p/1232444), and HRSD docs:

| # | Category | Common Subcategories / Items |
|---|----------|------------------------------|
| 1 | **Hardware** | New laptop / desktop, Monitor, Keyboard/mouse, Printer, Headset, Mobile device, Docking station, Hardware repair, Hardware return |
| 2 | **Software** | New software install, License request, Software upgrade, Removal, Software bug |
| 3 | **Account & Access** | New account creation, Password reset, Account unlock, Group/role membership, MFA reset, Access to shared mailbox/folder, VPN access, RBAC role change |
| 4 | **Network & Connectivity** | Wi-Fi access, Wired port activation, VPN setup, Firewall rule change, DNS change, Static IP, Proxy bypass |
| 5 | **Email & Messaging** | New mailbox, Distribution list, Mailbox size increase, Calendar permission, Teams/Slack channel, Email rules |
| 6 | **Telecom / Mobile** | Cell phone, Number port, International access, Plan change, Conference bridge, Desk phone |
| 7 | **Security** | Phishing report, Suspicious activity, Certificate request, Privileged access, Security exception |
| 8 | **Facilities (cross-over)** | Desk move, Badge / physical access, Parking |
| 9 | **HR (HRSD cross-over)** | Onboarding, Offboarding, Name change, Address change, Leave of absence, Benefits enrollment, Tuition reimbursement |
| 10 | **Database & Storage** | Schema change, DB access grant, File share quota increase, Restore from backup |
| 11 | **Reporting & Analytics** | New report, Power BI access, Dashboard share, Data extract |
| 12 | **General Inquiry / Help** | "I don't know what to ask" - typically routes to service desk |

### 4.2 Worked Example: "New Laptop Request" Catalog Item

A typical New Laptop catalog item ships with these variables (synthesizing [Beyond20](https://www.beyond20.com/blog/servicenow-service-catalog-best-practices/), [Variables docs](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/build/service-creator/concept/c_VariablesAndVariableSets.html), and [UCSD field reference](https://blink.ucsd.edu/_files/technology-tab/servicenow/servicenow-fields-2.pdf)):

| Variable name | Type | Mandatory | Notes |
|---------------|------|-----------|-------|
| `requested_for` | Reference (sys_user) | Y | Default = current user; managers can request for direct reports |
| `business_justification` | Multi-line Text | Y | Free text |
| `model_choice` | Lookup Select Box | Y | E.g., "Standard 14-inch", "Engineering 16-inch", "MacBook Pro 14" |
| `os_preference` | Multiple Choice | Y | Windows / macOS / Linux (driven by RBAC) |
| `memory_size` | Select Box | N | 16 GB / 32 GB / 64 GB |
| `storage_size` | Select Box | N | 512 GB / 1 TB / 2 TB |
| `peripherals` | List Collector | N | Dock, monitor, headset checkboxes |
| `ship_to_address` | Variable Set: "Address Block" | Y | Reusable variable set |
| `cost_center` | Reference (cmn_cost_center) | Y | Triggers cost-center-manager approval |
| `delivery_date` | Date | N | Earliest acceptable date |
| `attachments` | Attachment | N | Manager email approving exception |

**Workflow generated by submission:**

1. REQ + RITM created. RITM state = -5 (Pending Approval).
2. Approvals dispatched to manager and cost center owner (rows in `sysapproval_approver`).
3. On approval, RITM state moves to 1 (Open) → 2 (Work in Progress).
4. SCTASKs created: "Procurement order", "Imaging", "AD account update", "Asset tag and ship".
5. As each SCTASK closes, fulfillment workflow updates the RITM. When all SCTASKs closed_complete, RITM → 3 (Closed Complete).
6. When all RITMs closed, REQ → Closed Complete.

Sources: [Variables and Variable Sets](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/build/service-creator/concept/c_VariablesAndVariableSets.html), [Order Guides](https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/service-catalog-management/concept/c_OrderGuides.html), [Beyond20](https://www.beyond20.com/blog/servicenow-service-catalog-best-practices/).

### 4.3 Approval Engine

Approvals are not embedded in the request tables. Instead, ServiceNow generates rows in `sysapproval_approver` (one per approver per ticket). Each row has `state` (Requested, Approved, Rejected, Cancelled, Not Required), `approver`, `source_table`, `document_id`. Ticket workflows wait on aggregate approval states (Any approver, All approvers, Majority, etc.) ([The Snowball: Approval Engine](https://thesnowball.co/the-servicenow-approval-engine)).

This generic approval table handles approvals for **any** task (changes, requests, RITMs, even custom apps), which is why approval reporting can be unified.

**Confidence:** HIGH for table architecture, MODERATE for organization-specific catalog item shapes (these legitimately vary per customer).

---

## 5. SLAs, OLAs, and Underpinning Contracts

ServiceNow ships an SLA engine using `contract_sla` (definitions) and `task_sla` (running timers, one row per applicable SLA per task). Three classic ITIL contract layers ([BMC: SLA, OLA, UC](https://www.bmc.com/blogs/sla-ola-underpinning-contract/)):

| Layer | Between | Example |
|-------|---------|---------|
| **SLA** | IT and the business / customer | "P1 incidents resolved within 4 hours, 99% of the time" |
| **OLA** | Internal IT teams | "Network team responds to escalations within 30 minutes" |
| **UC (Underpinning Contract)** | IT and external vendor | "Cloud provider restores VM within 2 hours" |

In ServiceNow, all three are typically modeled with the same `contract_sla` definitions but with different scope conditions and stakeholders. The `incident.made_sla` boolean is set false on breach, fueling reports.

**Confidence:** HIGH (mature, stable feature).

---

## 6. ITIL 4 Alignment and Major Process Coverage

ServiceNow's process suite maps cleanly to ITIL 4 practices ([Atlassian ITIL 4 reference](https://www.atlassian.com/itsm/itil-4)):

| ITIL 4 Practice | ServiceNow product/module | Primary table |
|-----------------|---------------------------|---------------|
| Incident Management | Incident Management | `incident` |
| Service Request Management | Service Catalog | `sc_request`, `sc_req_item`, `sc_task` |
| Problem Management | Problem Management | `problem` |
| Change Enablement | Change Management | `change_request` |
| Service Configuration Management | CMDB | `cmdb_ci` |
| IT Asset Management | Asset Management | `alm_asset` |
| Knowledge Management | Knowledge | `kb_knowledge` |
| Service Level Management | SLA | `contract_sla`, `task_sla` |
| Service Desk | Agent Workspace, Service Portal | various |

**Confidence:** HIGH.

---

## 7. Pre-Mortem: Why This Research Could Be Wrong (in 6 months)

> 1. **Vendor releases drift.** ServiceNow ships two major releases a year. State models or default categories in Yokohama (2026) could shift names. Mitigation: cited specific release versions (Xanadu, Zurich) and used vendor docs for primary claims.
> 2. **Customer customization is the norm.** Real instances diverge heavily from OOB - especially state names, category lists, and priority thresholds. Anyone adopting this report as a literal blueprint without inspecting their target instance would be misled. Section 5 explicitly flags Berkeley as a customized exemplar.
> 3. **Integer state values are partly single-sourced.** RITM integer states (-5, 1, 2, 3, 4, 7) are confirmed by Broadcom KB and Snowball but not directly viewable in vendor docs without authenticated access. Treat as MODERATE confidence; verify in your own instance before hard-coding.

**Residual risks:** OOB defaults vary across releases; vendor doc URLs may shift; HRSD architecture evolves faster than core ITSM.

---

## Conclusion

ServiceNow's IT ticketing system is, beneath its many product names, a remarkably uniform task-record platform. Every ticket type - incident, problem, change, request, RITM, SCTASK, even HR case - is a row in a child table of `task`, with the same skeleton of fields and the same patterns for approvals, SLAs, work notes, and CI linkage. The differentiation between modules lies in **state machines** (each module has its own lifecycle), **type-specific fields** (e.g., `cause_notes` on problems, `risk` on changes, `variables` on RITMs), and **workflow orchestration** (Flow Designer / legacy Workflow generates SCTASKs, escalates approvals, posts notifications).

**Why this matters for designing your own ticketing taxonomy:** the most important architectural decision is whether to **stay close to OOB** or fork. Staying close gives you upgrade safety and a much larger pool of partners, integrations, and pre-built content. Forking lets you express organizational nuance but mortgages every future release. The detailed schemas, state diagrams, and category taxonomies in this report are the OOB starting point; map them against your business needs before customizing.

Two specific recommendations for any new ticketing taxonomy modeled on ServiceNow's:

1. **Separate break/fix from fulfillment from the start.** Conflating "I need a new laptop" with "my laptop is broken" creates reporting and SLA pain forever after. ServiceNow's two-track design (incident vs. catalog request) is the proven pattern.
2. **Compute priority from impact and urgency, do not let users set it directly.** This single decision eliminates the most common source of P1 inflation and aligns with how SLAs are calibrated against priority.

---

## Sources

1. ServiceNow. *Life cycle of an Incident.* (Xanadu docs, 2024-08-01.) https://www.servicenow.com/docs/r/xanadu/it-service-management/incident-management/c_IncidentManagementStateModel.html
2. ServiceNow. *State model and transitions (Change Management).* (Zurich docs, 2025-07-31.) https://www.servicenow.com/docs/r/zurich/it-service-management/change-management/c_ChangeStateModel.html
3. ServiceNow. *What is Problem Management?* https://www.servicenow.com/products/itsm/what-is-problem-management.html
4. ServiceNow Community. *Incident Priority Matrix - Current OOB.* (2025-10-26.) https://www.servicenow.com/community/virtual-agent-forum/incident-priority-matrix-current-oob/m-p/3413018
5. UC Berkeley. *IT - Incident Impact, Urgency, and Priority Guide (KB0010891).* (Rev. 2025-03-06.) https://berkeley.service-now.com/kb_view.do?sysparm_article=KB0010891
6. UC Berkeley. *ServiceNow - Status Definitions (KB0012297).* https://berkeley.service-now.com/kb_view.do?sys_kb_id=c511fa5d1b57ef40bc27feeccd4bcb23
7. The Snowball. *The ServiceNow Priority Matrix - Impact and Urgency.* https://thesnowball.co/the-servicenow-priority-matrix-impact-and-urgency
8. ServiceNowGyan. *Incident Management in ServiceNow.* https://servicenowgyan.com/incident-management-in-servicenow/
9. UnoGeeks. *Incident States in ServiceNow.* https://unogeeks.com/incident-states-in-servicenow/
10. The Snowball. *The ServiceNow Service Catalog Request Tables.* https://thesnowball.co/the-servicenow-service-catalog-request-tables
11. Broadcom. *KB on ServiceNow RITM state values.* https://knowledge.broadcom.com/external/article?articleNumber=247519
12. UCSD. *ServiceNow Service Catalog field reference (PDF).* https://blink.ucsd.edu/_files/technology-tab/servicenow/servicenow-fields-2.pdf
13. ServiceNow Community. *The difference between asset and configuration management.* https://www.servicenow.com/community/asset-management-articles/the-difference-between-asset-and-configuration-management/ta-p/2308716
14. The Snowball. *The ServiceNow Asset Management Tables.* https://thesnowball.co/the-servicenow-asset-management-tables
15. ServiceNow. *Variables and Variable Sets (Zurich platform docs).* https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/build/service-creator/concept/c_VariablesAndVariableSets.html
16. ServiceNow. *Record Producers (Zurich platform docs).* https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/service-catalog-management/concept/c_RecordProducer.html
17. ServiceNow. *Order Guides (Zurich platform docs).* https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/service-catalog-management/concept/c_OrderGuides.html
18. ServiceNow. *HR Service Delivery product overview.* https://www.servicenow.com/products/hr-service-delivery.html
19. ServiceNow. *HRSD Lifecycle Events (Zurich docs).* https://www.servicenow.com/docs/bundle/zurich-employee-service-management/page/product/human-resources/concept/c_LifecycleEventsHRSD.html
20. Atlassian. *ITIL 4 reference.* https://www.atlassian.com/itsm/itil-4
21. ServiceNow. *Standard Change Catalog (Zurich docs).* https://www.servicenow.com/docs/bundle/zurich-it-service-management/page/product/change-management/concept/c_StandardChangeCatalog.html
22. ServiceNow. *Configuration Management (CMDB) (Zurich platform docs).* https://www.servicenow.com/docs/bundle/zurich-servicenow-platform/page/product/configuration-management/concept/c_ITILConfigurationManagement.html
23. The Snowball. *The ServiceNow Task Table.* https://thesnowball.co/the-servicenow-task-table
24. BMC. *SLA, OLA, and Underpinning Contracts: Differences Explained.* https://www.bmc.com/blogs/sla-ola-underpinning-contract/
25. Beyond20. *ServiceNow Service Catalog Best Practices.* https://www.beyond20.com/blog/servicenow-service-catalog-best-practices/
26. ServiceNow Community. *Incident Category and Subcategory list.* https://www.servicenow.com/community/itsm-forum/incident-category-and-subcategory-list/m-p/1232444
27. ServiceNow. *CAB Workbench (Zurich docs).* https://www.servicenow.com/docs/bundle/zurich-it-service-management/page/product/change-management/concept/c_CABWorkbench.html
28. The Snowball. *The ServiceNow Approval Engine.* https://thesnowball.co/the-servicenow-approval-engine
29. ServiceNow Community. *Problem Management Overview.* https://www.servicenow.com/community/itsm-articles/problem-management-overview/ta-p/2378152
30. ServiceNow. *ITSM product page.* https://www.servicenow.com/products/itsm.html
31. LinkedIn / Pooja Dole. *Incident Lifecycle Stages in ServiceNow.* https://www.linkedin.com/posts/pooja-dole-9104ba19b_servicenow-itsm-incidentmanagement-activity-7452197737384607744-yEhD
32. XAZA Tech. *ServiceNow Incident Priority Matrix Setup Guide.* https://xaza.tech/tips/servicenow-incident-priority-matrix-setup-guide
