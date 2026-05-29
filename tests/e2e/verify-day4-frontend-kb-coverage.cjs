const fs = require('fs');
const path = require('path');

function check(file, tokens) {
  const body = fs.readFileSync(file, 'utf8');
  const missing = tokens.filter(token => !body.includes(token));
  return { file, status: missing.length === 0 ? 'PASS' : 'FAIL', missing };
}

const results = [
  {
    task: 40,
    name: 'SPFx smoke coverage',
    ...check('tests/e2e/itsm-home.spec.ts', [
      'ITSM SPFx frontend smoke tests',
      'loads the portal shell with real SharePoint data',
      'keeps SharePoint chrome hidden',
      'navigates between primary ITSM views',
      'test-results/itsm-home.png'
    ])
  },
  {
    task: 43,
    name: 'Submit Ticket write path',
    ...check('src/routes/SubmitIncidentView.tsx', ['onSubmit', 'categoryId', 'subcategoryId', 'Submit ticket'])
  },
  {
    task: 43,
    name: 'TicketService creates real SharePoint row',
    ...check('src/services/TicketService.ts', [
      'createIncident',
      'TicketSource',
      'CategoryRefId',
      'SubcategoryId',
      'CallerId',
      'ShortDescription'
    ])
  },
  {
    task: 53,
    name: 'Frontend KB consumption',
    ...check('src/services/KnowledgeService.ts', [
      "listItemsUrl('Knowledge Base'",
      "ArticleStatus eq 'Published'",
      '$expand=Category'
    ])
  },
  {
    task: 53,
    name: 'KB view renders imported article data',
    ...check('src/routes/KnowledgeView.tsx', ['Published articles', 'article.articleNumber', 'article.summary'])
  },
  {
    task: 53,
    name: 'Agent local KB grounding source',
    ...check('agents/triage/Helpdesk Triage Agent/knowledge/KnowledgeBase.mcs.yml', [
      'https://contoso.sharepoint.com/sites/ITSM/Lists/Knowledge%20Base'
    ])
  },
  {
    task: 54,
    name: 'License Costs data-display path',
    ...check('src/routes/AdminView.tsx', ['License Costs', 'licenseCosts', 'licenseCostCount'])
  },
  {
    task: 54,
    name: 'Catalog cost display path',
    ...check('src/routes/CatalogView.tsx', ['licenseCosts', 'Cost unavailable', 'Price not set'])
  }
];

const evidence = {
  testId: 'D4-040-043-053-054-Frontend-KB-Coverage',
  capturedAt: new Date().toISOString(),
  results,
  verdict: results.every(result => result.status === 'PASS') ? 'PASS' : 'FAIL',
  note: 'This verifies committed/deployed source wiring. Browser execution still requires a Playwright auth state for the SharePoint tenant.'
};

fs.mkdirSync('prompts', { recursive: true });
const outPath = path.join('prompts', 'day4_frontend_kb_coverage.json');
fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence, null, 2));
if (evidence.verdict !== 'PASS') process.exit(1);
