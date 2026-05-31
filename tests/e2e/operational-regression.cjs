const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const siteUrl = 'https://contoso.sharepoint.com/sites/ITSM';
const homeUrl = `${siteUrl}/SitePages/Home.aspx`;
const timeoutMs = Number(process.env.ITSM_OPERATIONAL_TIMEOUT_MS || 900000);
const pollIntervalMs = Number(process.env.ITSM_OPERATIONAL_POLL_INTERVAL_MS || 15000);
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
  await page.getByText('ITSM Service Portal', { exact: true }).first().waitFor({ timeout: 60000 });
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

async function createTicket(page, fields) {
  return sp(page, 'POST', itemsPath('Tickets'), {
    CategoryRefId: 6,
    CallerId: 17,
    Impact: '3 - Low',
    Urgency: '3 - Low',
    ConfidentialityLevel: 'Public',
    TicketSource: 'Portal',
    Archived: false,
    ...fields
  });
}

async function getTicket(page, id) {
  return sp(page, 'GET', itemsPath('Tickets', `(${id})`));
}

async function getArchiveForSource(page, sourceId) {
  const result = await sp(page, 'GET', itemsPath('Tickets-Archive', `?$filter=OriginalSourceId eq ${sourceId}&$top=5`));
  return result.value || [];
}

async function queryTickets(page, filter) {
  const result = await sp(page, 'GET', itemsPath('Tickets', `?$filter=${encodeURIComponent(filter)}&$top=20`));
  return result.value || [];
}

async function getTicketByTitle(page, title) {
  const items = await queryTickets(page, `Title eq '${title.replace(/'/g, "''")}'`);
  if (items.length !== 1) {
    throw new Error(`Expected one ticket titled ${title}, found ${items.length}`);
  }
  return items[0];
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

function ticketEvidence(item) {
  return {
    itemId: item.Id,
    title: item.Title,
    ticketType: item.TicketType,
    ticketState: item.TicketState,
    priority: item.Priority,
    slaStatus: item.SlaStatus,
    slaTargetMinutes: item.SlaTargetMinutes,
    slaBusinessMinutesElapsed: item.SlaBusinessMinutesElapsed,
    slaPercentElapsed: item.SlaPercentElapsed,
    slaWarningAt: item.SlaWarningAt,
    slaBreachedAt: item.SlaBreachedAt,
    madeSla: item.MadeSla,
    onHoldSince: item.OnHoldSince,
    totalPausedMinutes: item.TotalPausedMinutes,
    archived: item.Archived,
    archivedAt: item.ArchivedAt,
    parentTicketId: item.ParentTicketId || item.ParentTicketLookupId,
    escalationFlag: item.EscalationFlag,
    majorIncidentFlag: item.MajorIncidentFlag,
    majorIncidentClusterKey: item.MajorIncidentClusterKey,
    majorIncidentDetectedAt: item.MajorIncidentDetectedAt,
    created: item.Created,
    modified: item.Modified
  };
}

async function main() {
  const { context, page } = await launchPage();
  try {
    const runKey = process.env.ITSM_OPERATIONAL_RUN_KEY || new Date().toISOString().replace(/[-:.]/g, '').slice(0, 15);
    const loadExisting = Boolean(process.env.ITSM_OPERATIONAL_RUN_KEY);
    const startedAt = new Date().toISOString();
    const closedDate = new Date(Date.now() - 92 * 24 * 60 * 60 * 1000).toISOString();

    const warning = loadExisting ? await getTicketByTitle(page, `D4-OPS-SLA-WARN-${runKey}`) : await createTicket(page, {
      Title: `D4-OPS-SLA-WARN-${runKey}`,
      TicketType: 'Request',
      TicketState: 'In Progress',
      Priority: '1 - Critical',
      ShortDescription: 'Day 4 SLA warning regression seed',
      Description: 'Controlled SLA warning seed. Initial elapsed 165 should become 180/240 and enter Warning.',
      SlaBusinessMinutesElapsed: 165,
      TotalPausedMinutes: 0
    });
    const breach = loadExisting ? await getTicketByTitle(page, `D4-OPS-SLA-BREACH-${runKey}`) : await createTicket(page, {
      Title: `D4-OPS-SLA-BREACH-${runKey}`,
      TicketType: 'Request',
      TicketState: 'In Progress',
      Priority: '1 - Critical',
      ShortDescription: 'Day 4 SLA breach regression seed',
      Description: 'Controlled SLA breach seed. Initial elapsed 225 should become 240/240 and breach.',
      SlaBusinessMinutesElapsed: 225,
      TotalPausedMinutes: 0
    });
    const hold = loadExisting ? await getTicketByTitle(page, `D4-OPS-SLA-HOLD-${runKey}`) : await createTicket(page, {
      Title: `D4-OPS-SLA-HOLD-${runKey}`,
      TicketType: 'Request',
      TicketState: 'On Hold',
      Priority: '3 - Moderate',
      ShortDescription: 'Day 4 SLA hold regression seed',
      Description: 'Controlled SLA hold seed. Flow should set OnHoldSince and avoid increasing elapsed minutes.',
      SlaBusinessMinutesElapsed: 30,
      TotalPausedMinutes: 7
    });
    const archive = loadExisting ? await getTicketByTitle(page, `D4-OPS-ARCH-${runKey}`) : await createTicket(page, {
      Title: `D4-OPS-ARCH-${runKey}`,
      TicketType: 'Request',
      TicketState: 'Closed',
      Priority: '4 - Low',
      ShortDescription: 'Day 4 archival regression seed',
      Description: 'Controlled old closed ticket for archival regression.',
      ClosedDate: closedDate,
      MadeSla: true,
      ReopenCount: 0,
      WorkNotes: 'Day 4 operational regression archive seed.'
    });
    const miTickets = [];
    for (const [index, symptom] of [
      'Microsoft Teams chat messages fail to send for multiple users with service unavailable errors',
      'Microsoft Teams users cannot send chat messages and see service unavailable errors',
      'Multiple users report Teams chat outage and failed message delivery'
    ].entries()) {
      miTickets.push(loadExisting ? await getTicketByTitle(page, `D4-OPS-MI-${index + 1}-${runKey}`) : await createTicket(page, {
        Title: `D4-OPS-MI-${index + 1}-${runKey}`,
        TicketType: 'Incident',
        TicketState: 'New',
        Priority: '3 - Moderate',
        ShortDescription: `Day 4 MI regression ${index + 1}: Teams chat outage`,
        Description: symptom,
        TicketSource: 'ProposeAction'
      }));
    }

    const seedEvidence = {
      runKey,
      startedAt,
      seededAt: loadExisting ? '(loaded existing rows)' : new Date().toISOString(),
      tickets: {
        slaWarning: ticketEvidence(warning),
        slaBreach: ticketEvidence(breach),
        slaHold: ticketEvidence(hold),
        archival: ticketEvidence(archive),
        majorIncidentChildren: miTickets.map(ticketEvidence)
      }
    };
    console.log(`SEEDED ${JSON.stringify(seedEvidence, null, 2)}`);
    console.log('Waiting for SLA and Archival resubmissions plus Major Incident trigger processing...');

    const slaWarning = await pollUntil('SLA warning update', async () => {
      const item = await getTicket(page, warning.Id);
      return { done: item.SlaStatus === 'Warning', value: item };
    });
    const slaBreach = await pollUntil('SLA breach update', async () => {
      const item = await getTicket(page, breach.Id);
      return { done: item.SlaStatus === 'Breached', value: item };
    });
    const slaHold = await pollUntil('SLA hold pause update', async () => {
      const item = await getTicket(page, hold.Id);
      return { done: item.SlaStatus === 'On Track' && Boolean(item.OnHoldSince), value: item };
    });
    const archivalSource = await pollUntil('archival source marker', async () => {
      const item = await getTicket(page, archive.Id);
      const archiveRows = await getArchiveForSource(page, archive.Id);
      return { done: item.Archived === true && archiveRows.length > 0, value: { item, archiveRows } };
    });
    const majorIncident = await pollUntil('major incident cluster', async () => {
      const children = await Promise.all(miTickets.map(ticket => getTicket(page, ticket.Id)));
      const parentIds = [...new Set(children.map(child => child.ParentTicketId || child.ParentTicketLookupId).filter(Boolean))];
      if (parentIds.length === 1 && children.every(child => child.EscalationFlag === true && child.MajorIncidentClusterKey)) {
        const parent = await getTicket(page, parentIds[0]);
        return { done: parent.MajorIncidentFlag === true, value: { parent, children } };
      }
      return { done: false, value: children.map(ticketEvidence) };
    });

    const evidence = {
      testId: 'D4-055-Operational-Regression',
      runKey,
      startedAt,
      completedAt: new Date().toISOString(),
      note: 'SLA Timer and Archival are recurrence-only flows; this harness expects live run resubmission while it polls. Major Incident uses the normal SharePoint create trigger.',
      before: seedEvidence.tickets,
      after: {
        slaWarning: ticketEvidence(slaWarning),
        slaBreach: ticketEvidence(slaBreach),
        slaHold: ticketEvidence(slaHold),
        archivalSource: ticketEvidence(archivalSource.item),
        archivalRows: archivalSource.archiveRows.map(row => ({
          itemId: row.Id,
          title: row.Title,
          originalSourceId: row.OriginalSourceId,
          ticketState: row.TicketState,
          archivedAt: row.ArchivedAt,
          archivedByFlow: row.ArchivedByFlow,
          madeSla: row.MadeSla,
          reopenCount: row.ReopenCount,
          closedDate: row.ClosedDate,
          workNotes: row.WorkNotes
        })),
        majorIncidentParent: ticketEvidence(majorIncident.parent),
        majorIncidentChildren: majorIncident.children.map(ticketEvidence)
      },
      verdict: 'PASS'
    };

    fs.mkdirSync('prompts', { recursive: true });
    const outPath = path.join('prompts', `day4_task55_operational_regression_${runKey}.json`);
    fs.writeFileSync(outPath, JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence, null, 2));
    console.log(`Evidence written to ${outPath}`);
  } finally {
    await context.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
