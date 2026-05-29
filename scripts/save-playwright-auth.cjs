const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');

const url = process.env.ITSM_FRONTEND_URL || 'https://contoso.sharepoint.com/sites/ITSM/SitePages/Home.aspx';
const authPath = process.env.PLAYWRIGHT_STORAGE_STATE || '.auth/sharepoint.json';
const authDir = path.dirname(authPath);

async function main() {
  fs.mkdirSync(authDir, { recursive: true });

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  console.log(`Opening ${url}`);
  console.log('Complete Microsoft sign-in in the browser window. The script will save auth state after the ITSM app loads.');

  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120_000 });
  await page.getByText('ITSM Service Portal').waitFor({ timeout: 300_000 });
  await context.storageState({ path: authPath });

  console.log(`Saved Playwright auth state to ${authPath}`);
  await browser.close();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
