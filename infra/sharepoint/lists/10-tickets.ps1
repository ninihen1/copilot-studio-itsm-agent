#Requires -Version 7.0

# Tickets list — master ticket list (Incident / Request / Change / Problem inheritance via Type column)
# Source: sharepoint-itsm-schema.xlsx, sheet "1. Tickets"
# Plus 3 confidentiality columns added per item-level perms decision (2026-04-29).
# Versioning: 50 majors (audit trail).
# Append-only: WorkNotes, Comments.

. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-TicketsList {
    param([string]$ListTitle = 'Tickets')

    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Master ITSM ticket list. Type column distinguishes Incident / Request / Change / Problem.' `
        -Template GenericList `
        -EnableVersioning $true `
        -MajorVersionLimit 50 | Out-Null

    # Phase B dedupe: TicketNumber column dropped — Title now carries the ticket number.
    Set-PnPField -List $ListTitle -Identity 'Title' -Values @{ Title = 'Ticket Number' } | Out-Null

    # ===== Identity & classification =====

    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketType'; DisplayName = 'Type'; Type = 'Choice'
        Choices = @('Incident','Request','Change','Problem'); Required = $true; Indexed = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'CategoryRef'; DisplayName = 'Category'; Type = 'Lookup'
        LookupList = 'Categories'; LookupField = 'Title'; Required = $true; Indexed = $true
    }
    # Phase 3 — Subcategory upgraded from free-text to Lookup → Subcategories list (research §4.1 cascade pattern).
    # Power Apps form should cascade-filter on Tickets.CategoryRef → Subcategories.ParentCategory.
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Subcategory'; DisplayName = 'Subcategory'; Type = 'Lookup'
        LookupList = 'Subcategories'; LookupField = 'Title'; Indexed = $true
        Description = 'Subcategory roll-up — should match a row in Subcategories whose ParentCategory equals this ticket''s CategoryRef.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'CmdbCi'; DisplayName = 'Configuration Item'; Type = 'Lookup'
        LookupList = 'Configuration Items'; LookupField = 'Title'; Indexed = $true
    }

    # ===== People =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Caller'; DisplayName = 'Caller'; Type = 'User'
        Required = $true; Indexed = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'AssignmentGroup'; DisplayName = 'Assignment Group'; Type = 'User'
        Indexed = $true
        Description = 'Owning queue. Use a group, not an individual.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'AssignedTo'; DisplayName = 'Assigned To'; Type = 'User'; Indexed = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketFollowers'; DisplayName = 'Followers'; Type = 'UserMulti'
        Description = 'Users subscribed to ticket updates from the portal detail modal.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'RequestedForUser'; DisplayName = 'Requested For User'; Type = 'User'
        Indexed = $true
        Description = 'Person the request is for. Defaults to Caller for self-service requests; required for on-behalf-of access/provisioning requests.'
    }

    # ===== State =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketState'; DisplayName = 'Status'; Type = 'Choice'
        Choices = @('New','In Progress','On Hold','Resolved','Closed','Cancelled'); Required = $true; Indexed = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'HoldReason'; DisplayName = 'Hold Reason'; Type = 'Choice'
        Choices = @('','Awaiting Caller','Awaiting Change','Awaiting Problem','Awaiting Vendor')
        Description = 'Required when Status = On Hold (enforced via Power Apps form).'
    }

    # ===== Priority (derived from Impact x Urgency via Power Automate) =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Impact'; DisplayName = 'Impact'; Type = 'Choice'
        Choices = @('1 - High','2 - Medium','3 - Low'); Required = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Urgency'; DisplayName = 'Urgency'; Type = 'Choice'
        Choices = @('1 - High','2 - Medium','3 - Low'); Required = $true
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Priority'; DisplayName = 'Priority'; Type = 'Choice'
        Choices = @('1 - Critical','2 - High','3 - Moderate','4 - Low','5 - Planning')
        Indexed = $true
        Description = 'Derived from Impact x Urgency by priority-calc Power Automate flow. Not user-editable.'
    }

    # ===== Content =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ShortDescription'; DisplayName = 'Short Description'; Type = 'Text'
        Required = $true; MaxLength = 255
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Description'; DisplayName = 'Description'; Type = 'Note'; RichText = $false
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketSource'; DisplayName = 'Source'; Type = 'Choice'
        Choices = @('Portal','TriageAgent','ProposeAction','Email','Teams','Manual','System')
        Indexed = $true
        Description = 'Intake origin. Triage Orchestrator skips ProposeAction rows to prevent re-triage loops.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'WorkNotes'; DisplayName = 'Work Notes'; Type = 'Note'
        RichText = $false; AppendOnly = $true
        Description = 'Internal-only updates. Append-only audit trail.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Comments'; DisplayName = 'Comments'; Type = 'Note'
        RichText = $false; AppendOnly = $true
        Description = 'Customer-visible updates. Append-only audit trail.'
    }

    # ===== Resolution =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'CloseCode'; DisplayName = 'Close Code'; Type = 'Choice'
        Choices = @('Solved Permanently','Solved Workaround','Not Solved (Not Reproducible)','Closed/Resolved by Caller','Duplicate','No Action Required')
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'CloseNotes'; DisplayName = 'Close Notes'; Type = 'Note'; RichText = $false
    }

    # ===== Linkage =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ParentTicket'; DisplayName = 'Parent Ticket'; Type = 'Lookup'
        LookupList = 'Tickets'; LookupField = 'TicketNumber'
        Description = 'For Major Incident parent/child linkage.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'EscalationFlag'; DisplayName = 'Escalation Flag'; Type = 'Boolean'
        Indexed = $true; DefaultValue = '0'
        Description = 'Set when a ticket is manually escalated. Major Incident Detector also uses this to avoid duplicate clustering.'
    }
    # Major Incident (Day 3 — set by ITSM-Major-Incident-Detector)
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'MajorIncidentFlag'; DisplayName = 'Major Incident Flag'; Type = 'Boolean'
        Indexed = $true; DefaultValue = '0'
        Description = 'Set on the parent MI ticket by the Major Incident Detector.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'MajorIncidentClusterKey'; DisplayName = 'Major Incident Cluster Key'; Type = 'Text'
        Indexed = $true; MaxLength = 64
        Description = 'Cluster correlation key linking related incidents to one MI parent.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'MajorIncidentDetectedAt'; DisplayName = 'Major Incident Detected At'; Type = 'DateTime'
    }

    # ===== SLA =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaDue'; DisplayName = 'SLA Due'; Type = 'DateTime'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'MadeSla'; DisplayName = 'Made SLA'; Type = 'Boolean'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ReopenCount'; DisplayName = 'Reopen Count'; Type = 'Number'
    }

    # ===== SLA tracking (Day 3 — maintained by ITSM-Scheduled-SLA-Timer) =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaStatus'; DisplayName = 'SLA Status'; Type = 'Choice'
        Choices = @('Not Started','On Track','Warning','Breached','Met'); DefaultValue = 'Not Started'; Indexed = $true
        Description = 'Live SLA state maintained by the SLA Timer flow.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaTargetMinutes'; DisplayName = 'SLA Target Minutes'; Type = 'Number'
        Description = 'Priority-derived SLA target in business minutes.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaBusinessMinutesElapsed'; DisplayName = 'SLA Business Minutes Elapsed'; Type = 'Number'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaPercentElapsed'; DisplayName = 'SLA Percent Elapsed'; Type = 'Number'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaWarningAt'; DisplayName = 'SLA Warning At'; Type = 'DateTime'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SlaBreachedAt'; DisplayName = 'SLA Breached At'; Type = 'DateTime'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'OnHoldSince'; DisplayName = 'On Hold Since'; Type = 'DateTime'
        Description = 'Set when the ticket goes On Hold; the SLA Timer pauses the clock from here.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TotalPausedMinutes'; DisplayName = 'Total Paused Minutes'; Type = 'Number'
    }

    # ===== Timestamps (auto / flow-set) =====

    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ResolvedDate'; DisplayName = 'Resolved'; Type = 'DateTime'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ClosedDate'; DisplayName = 'Closed'; Type = 'DateTime'; Indexed = $true
        Description = 'Indexed for archival flow which queries Closed > 12 months.'
    }
    # Archival (Day 3 — set by ITSM-Scheduled-Archival on the source row when copied to Tickets-Archive)
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'Archived'; DisplayName = 'Archived'; Type = 'Boolean'
        Indexed = $true; DefaultValue = '0'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ArchivedAt'; DisplayName = 'Archived At'; Type = 'DateTime'
    }

    # ===== Confidentiality (item-level perms — added per 2026-04-29 decision) =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'ConfidentialityLevel'; DisplayName = 'Confidentiality'; Type = 'Choice'
        Choices = @('Public','Restricted','Confidential'); Required = $true; Indexed = $true
        DefaultValue = 'Public'
        Description = 'Drives item-level permission break by tickets-perm-sync flow. Public = inherit list perms. Restricted/Confidential = explicit readers only.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'PermSyncedAt'; DisplayName = 'Perm Synced At'; Type = 'DateTime'
        Description = 'Last time tickets-perm-sync flow ran. Used to detect drift.'
    }

    # ===== Ticket type validation gate =====
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketTypeValidated'; DisplayName = 'Ticket Type Validated'; Type = 'Boolean'
        Indexed = $true; DefaultValue = '0'
        Description = 'Set by ITSM-Ticket-Type-Validator after Request vs Incident classification is checked.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketTypeValidationStatus'; DisplayName = 'Ticket Type Validation Status'; Type = 'Choice'
        Choices = @('Pending','Validated','Reclassified','NeedsConfirmation','Skipped')
        Required = $true; Indexed = $true; DefaultValue = 'Pending'
        Description = 'Validation state used by downstream trigger guards.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TicketTypeValidationReason'; DisplayName = 'Ticket Type Validation Reason'; Type = 'Note'
        RichText = $false
        Description = 'Human-readable explanation from the ticket type validator.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SuggestedTicketType'; DisplayName = 'Suggested Ticket Type'; Type = 'Choice'
        Choices = @('Incident','Request','Change','Problem')
        Description = 'Suggested type when the validator cannot safely reclassify automatically.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'SelectedCatalogItem'; DisplayName = 'Selected Catalog Item'; Type = 'Lookup'
        LookupList = 'Service Catalog'; LookupField = 'Title'
        Description = 'Portal-selected catalog item for Request tickets. Used by validator and RITM Generator before falling back to SubcategoryHint.'
    }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{
        InternalName = 'TypeOverrideConfirmed'; DisplayName = 'Type Override Confirmed'; Type = 'Boolean'
        Indexed = $true; DefaultValue = '0'
        Description = 'Set when caller or service desk confirms the selected type despite validator recommendation.'
    }

    # ===== Compound indexes for common views =====
    # SP doesn't have a direct PnP cmdlet for compound indexes; managed via portal or REST.
    # Documented here as a follow-up admin task.
    Write-Host "  TODO (manual): create compound index (TicketState, AssignedTo) via Site Settings > Indexed Columns" -ForegroundColor DarkYellow
    Write-Host "  TODO (manual): create compound index (TicketType, ClosedDate) for archival flow" -ForegroundColor DarkYellow
}

# Export for use by master orchestrator
