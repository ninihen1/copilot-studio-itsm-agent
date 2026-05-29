const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const siteUrl = 'https://contoso.sharepoint.com/sites/ITSM';
const homeUrl = `${siteUrl}/SitePages/Home.aspx`;
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
    const headers = { Accept: 'application/json;odata=nometadata' };
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

async function readSubmittedTicket(page, shortDescription) {
  const filter = `$filter=ShortDescription eq '${shortDescription.replace(/'/g, "''")}'`;
  const select = '$select=Id,Title,TicketType,TicketState,ShortDescription,TicketSource,CategoryRef/Title,Subcategory/Title,Caller/Title,Impact,Urgency';
  const expand = '$expand=CategoryRef,Subcategory,Caller';
  const response = await sp(page, 'GET', itemsPath('Tickets', `?${select}&${expand}&${filter}&$orderby=Created desc&$top=1`));
  return (response.value || [])[0];
}

async function main() {
  const { context, page } = await launchPage();
  try {
    const runId = new Date().toISOString().replace(/[-:.]/g, '').slice(0, 15);
    const shortDescription = `Day 4 frontend submit path ${runId}`;
    const description = `Browser E2E created this ticket through the SPFx Submit Ticket route for task 54 at ${new Date().toISOString()}.`;

    await page.getByRole('button', { name: /Submit ticket/i }).click();
    await page.getByLabel(/Title/i).fill(shortDescription);
    await page.getByLabel(/Description/i).fill(description);
    await page.getByLabel(/Impact/i).selectOption({ label: '3 - Low' });
    await page.getByLabel(/Urgency/i).selectOption({ label: '2 - Medium' });
    await page.locator('.form-footer').getByRole('button', { name: /^Submit ticket$/i }).click();
    await page.getByText('My tickets').first().waitFor({ timeout: 60000 });
    await page.getByText(shortDescription).waitFor({ timeout: 60000 });

    const submittedTicket = await readSubmittedTicket(page, shortDescription);
    if (!submittedTicket) {
      throw new Error('Submitted ticket was not found in SharePoint by ShortDescription.');
    }

    await page.getByRole('button', { name: /Service catalog/i }).click();
    await page.getByRole('heading', { name: /Order IT services/i }).waitFor({ timeout: 30000 });
    const catalogVisible = await page.getByText(/Password Reset|License Request|Add to Group|Service Catalog is empty/i).first().isVisible();

    await page.getByRole('button', { name: /Knowledge base/i }).click();
    await page.getByRole('heading', { name: /Find answers before logging a ticket/i }).waitFor({ timeout: 30000 });
    const kbVisible = await page.getByText(/Published articles|No published articles|KB-/i).first().isVisible();

    await page.getByRole('button', { name: /Admin/i }).click();
    await page.getByRole('heading', { name: /Service desk operations/i }).waitFor({ timeout: 30000 });
    const licenseCostsVisible = await page.getByText(/License Costs/i).first().isVisible();
    const licenseSkuCountVisible = await page.getByText(/License SKUs/i).first().isVisible();

    const evidence = {
      testId: 'D4-054-Frontend-Data-Entry-Display',
      startedAt: runId,
      completedAt: new Date().toISOString(),
      submittedTicket: {
        itemId: submittedTicket.Id,
        title: submittedTicket.Title,
        shortDescription: submittedTicket.ShortDescription,
        ticketType: submittedTicket.TicketType,
        ticketState: submittedTicket.TicketState,
        ticketSource: submittedTicket.TicketSource,
        category: submittedTicket.CategoryRef?.Title,
        subcategory: submittedTicket.Subcategory?.Title,
        caller: submittedTicket.Caller?.Title,
        impact: submittedTicket.Impact,
        urgency: submittedTicket.Urgency
      },
      displayChecks: {
        catalogVisible,
        knowledgeVisible: kbVisible,
        licenseCostsVisible,
        licenseSkuCountVisible
      },
      verdict: submittedTicket.TicketType === 'Incident' && submittedTicket.TicketSource === 'Portal' && catalogVisible && kbVisible && licenseCostsVisible && licenseSkuCountVisible ? 'PASS' : 'FAIL'
    };

    fs.mkdirSync('prompts', { recursive: true });
    const outPath = path.join('prompts', `day4_task54_frontend_data_entry_display_${runId}.json`);
    fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    console.log(`Evidence written to ${outPath}`);
    if (evidence.verdict !== 'PASS') {
      process.exitCode = 1;
    }
  } finally {
    await context.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
