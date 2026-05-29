# Adaptive Cards

Reusable card templates used by the Power Automate flows. All cards use Adaptive Cards 1.5 schema with `${variable}` placeholders that the calling flow's `Send adaptive card` action substitutes at send time.

| File | Purpose | Sent by |
|---|---|---|
| `approval-request.json` | The pending-approval card with Approve / Reject (with reason) / Defer / Open ticket | Approval flow, per stage |
| `approval-granted.json` | Confirmation to caller that their request was approved | Approval flow, on final approval |
| `approval-denied.json` | Notification to caller with rejection reason | Approval flow, on rejection |
| `ticket-resolved.json` | Resolution notification with reopen / satisfied / KB link | Triage flow on Tickets state -> Resolved |
| `sla-breach.json` | Escalation card for assignment group on SLA overrun | sla-timer flow at 100% elapsed |
| `major-incident-detected.json` | Alert for IT-Helpdesk Teams channel when cluster threshold met | major-incident flow |

## Variable substitution

Power Automate's "Post adaptive card" action accepts a JSON template with `${variable}` placeholders and a key/value object of substitutions. The calling flow builds the substitution object and passes both.

Example (in approval flow, `Send_Approval_Card` action):

```
"body": {
  "card": "@string(items('cards/approval-request.json'))",
  "variables": {
    "jobType":            "@triggerBody()?['JobType']",
    "callerUpn":          "@triggerBody()?['CallerUpn']",
    "targetUpn":          "@json(triggerBody()?['TargetJson'])?['upn']",
    "actionDescription":  "@body('Lookup_JobType')?['Description']",
    "stageNumber":        "@iterationIndexes('ForEach_Stage')",
    "totalStages":        "@length(body('Parse_PolicyStages'))",
    "stageName":          "@items('ForEach_Stage')?['name']",
    "risk":               "@triggerBody()?['Risk']?['Value']",
    "confidence":         "@triggerBody()?['Confidence']",
    "ticketNumber":       "@triggerBody()?['ParentTicket']?['Value']",
    "rationale":          "@triggerBody()?['Rationale']",
    "argsPretty":         "@triggerBody()?['ArgsJson']",
    "jobId":              "@triggerBody()?['JobId']",
    "ticketUrl":          "@concat(parameters('ItsmSiteUrl'),'/Lists/Tickets/DispForm.aspx?ID=',string(triggerBody()?['ParentTicket']?['Id']))"
  }
}
```

## Localisation

These templates ship in English only. Localisation is out of scope for v1. If multi-language is needed in v2, replicate the cards under `cards/{lang}/` and switch on user's preferred language in the flow.

## Accessibility

Cards use standard FactSet and TextBlock elements which Teams renders accessibly with screen readers. No images carry meaning that isn't also in text. Buttons have descriptive labels (not "OK" / "Cancel").
