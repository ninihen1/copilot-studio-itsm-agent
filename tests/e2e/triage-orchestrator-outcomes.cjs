const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const siteUrl = 'https://contoso.sharepoint.com/sites/ITSM';
const homeUrl = `${siteUrl}/SitePages/Home.aspx`;
const timeoutMs = Number(process.env.ITSM_TRIAGE_TIMEOUT_MS || 720000);
const pollIntervalMs = Number(process.env.ITSM_TRIAGE_POLL_INTERVAL_MS || 15000);
const edgeUserDataDir = process.env.EDGE_USER_DATA_DIR || 'C:/Users/ninih/AppData/Local/Microsoft/Edge/User Data/Profile 9';
const edgeExecutablePath = process.env.EDGE_EXECUTABLE_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';

async function launchPage() {
  const context = await chromium.launchPersistentContext(edgeUserDataDir, {
    executablePath: edgeExecutablePath,
    headless: true,
    viewport: { width: 1440, height: 1000 }
  });
  const page = await context.newPage();
  await page.goto(homeUrl, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(5000);
  const account = page.locator('text="catherine.han@flowstudio.app"').first();
  if (await account.isVisible().catch(() => false)) {
    await account.click();
    await page.waitForTimeout(10000);
  }
  await page.getByText('ITSM Service Portal').waitFor({ timeout: 60000 });
  return { context, page };
}

async function sp(page, method, relativeUrl, body) {
  const result = await page.evaluate(async ({ siteUrl, method, relativeUrl, body }) => {
    const headers = {
      Accept: 'application/json;odata=nometadata'
    };
    if (body !== undefined) {
      const contextInfo = await fetch(`${siteUrl}/_api/contextinfo`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: { Accept: 'application/json;odata=nometadata', 'Content-Length': '0' }
      });
      const contextJson = await contextInfo.json();
      headers['Content-Type'] = 'application/json;odata=nometadata';
      headers['X-RequestDigest'] = contextJson.FormDigestValue;
    }
    const response = await fetch(`${siteUrl}/_api/${relativeUrl}`, {
      method,
      credentials: 'same-origin',
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    const text = await response.text();
    let parsed = text;
    try { parsed = text ? JSON.parse(text) : undefined; } catch (_) {}
    return { status: response.status, body: parsed, raw: text };
  }, { siteUrl, method, relativeUrl, body });

  if (result.status < 200 || result.status >= 300) {
    throw new Error(`SharePoint REST ${method} failed ${result.status}: ${relativeUrl}\n${result.raw}`);
  }
  return result.body;
}

function itemsPath(listTitle, suffix = '') {
  return `web/lists/getbytitle('${encodeURIComponent(listTitle)}')/items${suffix}`;
}

async function createKbArticle(page, runId) {
  return sp(page, 'POST', itemsPath('Knowledge Base'), {
    Title: 'Day 4 E2E - Clear Microsoft Teams cache',
    ArticleNumber: `KB-D4-TRIAGE-${runId}`,
    Summary: 'Steps for clearing the Microsoft Teams desktop cache when Teams is slow or stale.',
    Body: 'Quit Teams completely. Clear the Teams cache folder. Restart Teams and sign in again. Use this article only for Teams cache cleanup questions.',
    CategoryId: 11,
    Audience: 'All Employees',
    ArticleStatus: 'Published',
    KbAuthorId: 17,
    PublishedDate: new Date().toISOString(),
    Keywords: 'Teams cache, clear Teams cache, Microsoft Teams cache, desktop cache',
    ResolvesJobType: ''
  });
}

async function createTicket(page, title, shortDescription, description) {
  return sp(page, 'POST', itemsPath('Tickets'), {
    Title: title,
    TicketType: 'Incident',
    CategoryRefId: 6,
    CallerId: 17,
    TicketState: 'New',
    Impact: '3 - Low',
    Urgency: '3 - Low',
    ShortDescription: shortDescription,
    Description: description,
    TicketSource: 'Portal',
    ConfidentialityLevel: 'Public'
  });
}

async function getItem(page, listTitle, id) {
  return sp(page, 'GET', itemsPath(listTitle, `(${id})`));
}

async function getChildrenByParent(page, listTitle, parentTicketItemId) {
  const result = await sp(page, 'GET', itemsPath(listTitle, `?$filter=ParentTicketId eq ${parentTicketItemId}`));
  return result.value || [];
}

async function pollUntil(label, fn) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await fn();
    if (last.done) return last.value;
    await new Promise(resolve => setTimeout(resolve, pollIntervalMs));
  }
  throw new Error(`Timed out waiting for ${label}. Last observed: ${JSON.stringify(last?.value || last)}`);
}

async function main() {
  const { context, page } = await launchPage();
  try {
    const runId = new Date().toISOString().replace(/[-:.]/g, '').slice(0, 15);
    const startedAt = new Date().toISOString();
    const kb = await createKbArticle(page, runId);

    const cases = {
      deflect: await createTicket(
        page,
        `D4-TRIAGE-DEFLECT-${runId}`,
        'How do I clear the Microsoft Teams desktop cache?',
        'Please use the Day 4 E2E Clear Microsoft Teams cache KB article. I only need the self-service steps to clear the Teams desktop cache.'
      ),
      stopAndAsk: await createTicket(
        page,
        `D4-TRIAGE-ASK-${runId}`,
        'Need IT help with access',
        'Something is not working for someone. I do not know which app, user, error, or access is needed.'
      ),
      propose: await createTicket(
        page,
        `D4-TRIAGE-PROPOSE-${runId}`,
        'Reset password for arwen@contoso.onmicrosoft.com',
        'Please reset the password for arwen@contoso.onmicrosoft.com, force password change at next sign-in, and notify the user. This is a controlled Day 4 E2E triage proposal test.'
      )
    };

    const deflect = await pollUntil('deflect outcome', async () => {
      const item = await getItem(page, 'Tickets', cases.deflect.Id);
      return { done: item.TicketState === 'Resolved', value: item };
    });

    const stopAndAsk = await pollUntil('stop_and_ask outcome', async () => {
      const item = await getItem(page, 'Tickets', cases.stopAndAsk.Id);
      return { done: item.TicketState === 'On Hold' && item.HoldReason === 'Awaiting Caller', value: item };
    });

    const propose = await pollUntil('propose outcome', async () => {
      const item = await getItem(page, 'Tickets', cases.propose.Id);
      const jobs = await getChildrenByParent(page, 'Provisioning Jobs', cases.propose.Id);
      const approvals = await getChildrenByParent(page, 'Approvals', cases.propose.Id);
      return {
        done: item.TicketState === 'In Progress' && jobs.length > 0 && approvals.length > 0,
        value: { item, jobs, approvals }
      };
    });

    const evidence = {
      testId: 'D4-050-Triage-Orchestrator-Outcomes',
      startedAt,
      completedAt: new Date().toISOString(),
      seededKbArticle: {
        itemId: kb.Id,
        title: kb.Title,
        articleNumber: kb.ArticleNumber,
        status: kb.ArticleStatus
      },
      tickets: {
        deflect: summarizeTicket(deflect),
        stopAndAsk: summarizeTicket(stopAndAsk),
        propose: summarizeTicket(propose.item)
      },
      proposeArtifacts: {
        provisioningJobs: propose.jobs.map(item => ({
          itemId: item.Id,
          title: item.Title,
          jobType: item.JobType,
          jobStatus: item.JobStatus,
          parentTicketId: item.ParentTicketId,
          created: item.Created
        })),
        approvals: propose.approvals.map(item => ({
          itemId: item.Id,
          title: item.Title,
          linkedJobId: item.LinkedJobId,
          sessionState: item.SessionState,
          parentTicketId: item.ParentTicketId,
          created: item.Created
        }))
      },
      verdict: 'PASS'
    };

    fs.mkdirSync('prompts', { recursive: true });
    const outPath = path.join('prompts', `day4_task50_triage_outcomes_${runId}.json`);
    fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    console.log(`Evidence written to ${outPath}`);
  } finally {
    await context.close();
  }
}

function summarizeTicket(item) {
  return {
    itemId: item.Id,
    title: item.Title,
    ticketType: item.TicketType,
    ticketState: item.TicketState,
    holdReason: item.HoldReason,
    priority: item.Priority,
    impact: item.Impact,
    urgency: item.Urgency,
    description: item.Description,
    created: item.Created,
    modified: item.Modified
  };
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
