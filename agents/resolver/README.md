# Self-Service Resolver

Lightweight KB-only agent that runs in front of the Helpdesk Triage Agent. Per design memo §4.2 — optional deflection layer; skip for v1 if KB is thin.

## Status (2026-04-29)

Locally authored. 6 topics + 1 knowledge source + 1 agent file. Same placeholder substitution requirements as the Triage Agent (`cr1c2_resolver` schemaName placeholder, `https://CHANGE_ME...` SP URL).

## What it does

User -> Resolver. Single read source: published Knowledge Base. Two-turn budget. If a high-confidence article matches, summarise + link. Otherwise hand off to Helpdesk Triage Agent via `TransferConversationToAgent` (preserves conversation history).

## What it does NOT do

- No classification, no priority calculation, no action proposal — those are Triage's job.
- No SharePoint write. No Graph call. No Power Automate flow invocation.
- No knowledge sources beyond the one KB list.

## Files

```
Self-Service Resolver/
├── agent.mcs.yml                  # Instructions: KB-first, hand off in 2 turns, refusal scope
├── settings.mcs.yml               # Channels (Teams, M365 Copilot), Integrated SSO, isLightweightBot=true
├── connectionreferences.mcs.yml   # Empty — no flows
├── knowledge/
│   └── KnowledgeBase.mcs.yml      # Same KB list as Triage Agent
└── topics/
    ├── ConversationStart.mcs.yml
    ├── Greeting.mcs.yml
    ├── Goodbye.mcs.yml
    ├── Fallback.mcs.yml           # Searches KB, hands off after 2 attempts
    ├── Escalate.mcs.yml           # Immediate hand-off on user request
    ├── OnError.mcs.yml            # Logs + hands off
    └── HandOffToTriage.mcs.yml    # TransferConversationToAgent → cr1c2_helpdesktriage
```

## Skip-for-v1 decision criterion

The design memo says: *"Worth building if your knowledge base is mature. Skip for v1 if the KB is thin — deflection rate will be poor and the extra hop adds latency."*

Authoring the YAML is cheap; pushing it to the tenant is the decision. Recommendation:
- Pilot week 3 (when Triage Agent v1 goes live): **don't push the Resolver yet**. Get baseline KB deflection numbers from Triage's `SearchKnowledge` topic.
- Pilot week 6 review: if KB has > 50 published articles AND deflection rate from Triage exceeds 25%, push the Resolver as a front-line layer. Otherwise, leave it dormant.

## Cross-reference

- Hand-off target schemaName must match the Triage Agent's actual schemaName after Catherine creates it. Currently both use `cr1c2_helpdesktriage` placeholder. The find-and-replace step in `agents/triage/README.md` applies here too.
