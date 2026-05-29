const fs = require('fs');
const path = require('path');

const checks = [
  {
    task: 34,
    name: 'App Insights audit coverage',
    file: 'docs/DAY4-PRODUCTION-HARDENING-CLOSURE.md',
    tokens: ['flows/proposeaction/definition.json', 'flows/loghumanticket/definition.json', 'flows/executors/contract.md']
  },
  {
    task: 35,
    name: 'Certificate auth migration tracking',
    file: 'infra/azure/setup-exo-cert.ps1',
    tokens: ['SP-IT-Exchange-EXO-CertPfxBase64', 'SP-IT-Exchange-EXO-CertPassword', 'az ad app credential reset']
  },
  {
    task: 36,
    name: 'Approval policy engine activation path',
    file: 'flows/approval/spec.md',
    tokens: ['Migration path from pilot to full Approval flow', 'ApprovalStages', 'Sign_JWT', 'validate JWT']
  },
  {
    task: 37,
    name: 'SharePoint Sites.Selected grant path',
    file: 'infra/sharepoint/grant-sites-selected.ps1',
    tokens: ['Sites.Selected', 'fullcontrol', 'permissions']
  },
  {
    task: 38,
    name: 'Teams permission narrowing path',
    file: 'docs/SECURITY-HARDENING-EXECUTOR-SCOPING.md',
    tokens: ['ManagedTeams', 'per-team ownership', 'Teams Administrator']
  },
  {
    task: 39,
    name: 'Executor pre-flight checks',
    file: 'docs/EXECUTOR-IDEMPOTENCY-PRECHECKS.md',
    tokens: ['PreCheck_Current_State', 'target_already_in_desired_state', 'teams.addChannelMember']
  }
];

const results = checks.map(check => {
  const body = fs.readFileSync(check.file, 'utf8');
  const missing = check.tokens.filter(token => !body.includes(token));
  return {
    task: check.task,
    name: check.name,
    file: check.file,
    status: missing.length === 0 ? 'PASS' : 'FAIL',
    missing
  };
});

const evidence = {
  testId: 'D4-034-039-Production-Hardening-Coverage',
  capturedAt: new Date().toISOString(),
  results,
  verdict: results.every(result => result.status === 'PASS') ? 'PASS' : 'FAIL'
};

fs.mkdirSync('prompts', { recursive: true });
const outPath = path.join('prompts', 'day4_hardening_coverage.json');
fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence, null, 2));
if (evidence.verdict !== 'PASS') process.exit(1);
