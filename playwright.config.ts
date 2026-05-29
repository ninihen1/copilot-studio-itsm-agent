import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.ITSM_FRONTEND_URL || 'https://contoso.sharepoint.com/sites/ITSM/SitePages/Home.aspx';
const storageState = process.env.PLAYWRIGHT_STORAGE_STATE || '.auth/sharepoint.json';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 60_000,
  expect: {
    timeout: 10_000
  },
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL,
    storageState,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ],
  outputDir: 'test-results'
});
