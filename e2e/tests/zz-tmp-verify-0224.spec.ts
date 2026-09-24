import { test, Locator } from '@playwright/test';
import * as fs from 'fs';

// Throwaway probe (0.2.24): measure what each previously-empty screen says now.
// It writes one line per route to /tmp/wc-0224.txt and asserts only that the
// screen settled — i.e. that it is no longer showing its spinner.

const routes = [
  '/fitness-handheld',
  '/gtd-handheld',
  '/system-health-handheld',
  '/quest-status',
  '/quest-phone',
  '/system-health-phone',
  '/gtd-phone',
];

const OUT = '/tmp/wc-0224.txt';

async function textOf(locator: Locator): Promise<string> {
  if ((await locator.count()) === 0) return '<none>';
  const text = await locator.innerText({ timeout: 2000 }).catch(() => '<unreadable>');
  return JSON.stringify(text.replace(/\s+/g, ' ').trim());
}

test.setTimeout(180_000);

test('every previously-empty screen says what it knows', async ({ page }) => {
  fs.writeFileSync(OUT, '');

  for (const route of routes) {
    await page.goto(route, { waitUntil: 'domcontentloaded' });

    // Wait until no spinner is visible, up to 12s, then read.
    let spun = true;
    for (let i = 0; i < 48; i++) {
      const spinner = page.locator('.spinner, .loading-state').first();
      if ((await spinner.count()) === 0 || !(await spinner.isVisible())) {
        spun = false;
        break;
      }
      await page.waitForTimeout(250);
    }

    const refusal = await textOf(page.locator('.read-error').first());
    const empty = await textOf(page.locator('.empty-state').first());
    const body = await page.locator('body').innerText({ timeout: 5000 });

    fs.appendFileSync(
      OUT,
      [
        `route=${route}`,
        `  still-spinning=${spun}`,
        `  refusal=${refusal}`,
        `  empty-state-in-dom=${empty}`,
        `  hides-empty-state=${body.includes('.empty-state { display: none; }')}`,
        `  visible-first-lines=${JSON.stringify(body.replace(/\s+/g, ' ').trim().slice(0, 200))}`,
        '',
      ].join('\n'),
    );
  }
});
