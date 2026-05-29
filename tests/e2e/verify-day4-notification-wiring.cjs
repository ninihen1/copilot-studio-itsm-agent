const fs = require('fs');
const path = require('path');

const checks = [
  {
    task: 8,
    name: 'approval request',
    file: 'flows/ritm-approval/definition.json',
    mustContain: ['Create_Approval', 'shared_approvals', 'Approve', 'Reject']
  },
  {
    task: 9,
    name: 'approval granted',
    file: 'flows/ritm-approval/definition.json',
    mustContain: ['Post_Approval_Granted_Notification', 'PostMessageToConversation', 'Day 4 task 9']
  },
  {
    task: 10,
    name: 'approval denied',
    file: 'flows/ritm-approval/definition.json',
    mustContain: ['Post_Approval_Denied_Notification', 'PostMessageToConversation', 'Day 4 task 10']
  },
  {
    task: 11,
    name: 'ticket resolved',
    file: 'flows/sctask-orchestrator/definition.json',
    mustContain: ['Post_Ticket_Resolved_Notification', 'PostMessageToConversation', 'Day 4 task 11']
  },
  {
    task: 12,
    name: 'SLA breach',
    file: 'flows/sla-timer/definition.json',
    mustContain: ['Post_SLA_Breach_Notification', 'PostMessageToConversation', 'Day 4 task 12', 'first SLA breach']
  },
  {
    task: 13,
    name: 'major incident',
    file: 'flows/major-incident/definition.json',
    mustContain: ['Post_Major_Incident_Notification', 'PostMessageToConversation', 'Day 4 task 13']
  }
];

const results = checks.map(check => {
  const body = fs.readFileSync(check.file, 'utf8');
  const missing = check.mustContain.filter(text => !body.includes(text));
  return {
    task: check.task,
    name: check.name,
    file: check.file,
    status: missing.length === 0 ? 'PASS' : 'FAIL',
    missing
  };
});

const evidence = {
  testId: 'D4-051-Adaptive-Card-Notification-Wiring',
  capturedAt: new Date().toISOString(),
  results,
  verdict: results.every(result => result.status === 'PASS') ? 'PASS' : 'FAIL'
};

fs.mkdirSync('prompts', { recursive: true });
const outPath = path.join('prompts', 'day4_task51_notification_wiring.json');
fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence, null, 2));
if (evidence.verdict !== 'PASS') process.exit(1);
