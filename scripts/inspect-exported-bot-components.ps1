#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$InputPath = 'prompts/live_bot_components.json'
)

$rows = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$rows |
    Where-Object { $_.schemaname -in @('cre79_agent.topic.ProposeWriteAction','cre79_agent.topic.CreateTicket','cre79_agent.knowledge.KnowledgeBase') } |
    Select-Object name,schemaname,componenttype,content,data,description |
    ConvertTo-Json -Depth 20
