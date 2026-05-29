import { expect, test, type Page } from '@playwright/test';

const appUrl = process.env.ITSM_FRONTEND_URL || 'https://contoso.sharepoint.com/sites/ITSM/SitePages/Home.aspx';

test.describe('ITSM SPFx frontend smoke tests', () => {
  test.beforeEach(async ({ page }) => {
    const consoleErrors: string[] = [];
    const failedRequests: string[] = [];

    page.on('console', message => {
      if (message.type() === 'error') {
        const text = message.text();
        if (!isIgnoredConsoleError(text)) {
          consoleErrors.push(text);
        }
      }
    });

    page.on('requestfailed', request => {
      const url = request.url();
      if (!isIgnoredRequestFailure(url)) {
        failedRequests.push(`${request.failure()?.errorText || 'request failed'} ${url}`);
      }
    });

    await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
    await expect(page.getByText('ITSM Service Portal')).toBeVisible();
    await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => undefined);

    await page.evaluate(() => document.fonts?.ready).catch(() => undefined);

    test.info().attachments.push({
      name: 'console-errors',
      contentType: 'application/json',
      body: Buffer.from(JSON.stringify(consoleErrors, null, 2))
    });
    test.info().attachments.push({
      name: 'failed-requests',
      contentType: 'application/json',
      body: Buffer.from(JSON.stringify(failedRequests, null, 2))
    });

    expect(consoleErrors, 'Unexpected browser console errors').toEqual([]);
    expect(failedRequests, 'Unexpected failed network requests').toEqual([]);
  });

  test('loads the portal shell with real SharePoint data and no data error', async ({ page }) => {
    await expect(page.getByText('Good morning')).toBeVisible();
    await expect(page.getByText('My open tickets')).toBeVisible();
    await expect(page.getByText('Pending actions')).toBeVisible();
    await expect(page.getByText('Recent activity')).toBeVisible();
    await expect(page.getByText(/MI\d|D3-|INC|RITM/)).toBeVisible();

    await expect(page.getByText(/SharePoint data unavailable/i)).toHaveCount(0);
    await expect(page.getByText(/SharePoint GET failed/i)).toHaveCount(0);
    await expect(page.getByText(/Loading/i)).toHaveCount(0);

    await page.screenshot({ path: 'test-results/itsm-home.png', fullPage: true });
  });

  test('keeps SharePoint chrome hidden for the app experience', async ({ page }) => {
    await expect(page.locator('#SuiteNavWrapper')).toBeHidden();
    await expect(page.locator('#spLeftNav')).toBeHidden();
    await expect(page.locator('#spCommandBar')).toBeHidden();
    await expect(page.locator('[data-automation-id="pageHeader"]')).toBeHidden();

    const appBox = await page.locator('text=ITSM Service Portal').first().boundingBox();
    expect(appBox?.y ?? 999, 'ITSM app should start near the top of the viewport').toBeLessThan(80);
  });

  test('navigates between primary ITSM views', async ({ page }) => {
    await clickNav(page, 'My tickets');
    await expect(page.getByRole('heading', { name: /My tickets/i })).toBeVisible();
    await expect(page.getByText(/Recent tickets|No recent tickets/i)).toBeVisible();

    await clickNav(page, 'Service catalog');
    await expect(page.getByRole('heading', { name: /Order IT services/i })).toBeVisible();
    await expect(page.getByText(/Add to Group|Password Reset|Service Catalog is empty/i)).toBeVisible();

    await clickNav(page, 'Knowledge base');
    await expect(page.getByRole('heading', { name: /Find answers before logging a ticket/i })).toBeVisible();
    await expect(page.getByText(/Published articles|No published articles/i)).toBeVisible();

    await clickNav(page, 'Approvals');
    await expect(page.getByRole('heading', { name: /Review pending requests/i })).toBeVisible();
    await expect(page.getByText(/Approval queue|No pending approvals/i)).toBeVisible();

    await clickNav(page, 'Admin');
    await expect(page.getByRole('heading', { name: /Service desk operations/i })).toBeVisible();
    await expect(page.getByText(/Failed provisioning jobs|No failed jobs/i)).toBeVisible();

    await clickNav(page, 'Home');
    await expect(page.getByRole('heading', { name: /Good morning/i })).toBeVisible();
  });
});

async function clickNav(page: Page, name: string): Promise<void> {
  await page.getByRole('button', { name: new RegExp(name, 'i') }).click();
}

function isIgnoredConsoleError(text: string): boolean {
  return /Failed to load resource: net::ERR_NAME_NOT_RESOLVED/.test(text);
}

function isIgnoredRequestFailure(url: string): boolean {
  return /browser\.pipe\.aria\.microsoft\.com|browser\.events\.data\.microsoft\.com/.test(url);
}
