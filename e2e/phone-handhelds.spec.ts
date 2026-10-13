// SUPERSEDED — and not run. This file sits outside Playwright's `testDir` (the config in
// this directory points at `./tests`), and its `BASE_URL` still says port 4000 while the
// dashboard has served 30011 for a long time. So nothing here executes in CI or in
// `npx playwright test`. The live suite is `e2e/tests/*.spec.ts`. What this file is kept
// for is the prose: the retired-path checks below are the record of what each move was,
// and they are updated when a screen is retired even though Playwright will not run them.
// The executed retirement pin is `test/routes_mount_test.exs` on the Elixir side.

import { test, expect, Page } from '@playwright/test';

const BASE_URL = 'http://localhost:4000';

test.describe('Nova Phone Handhelds', () => {
  test.beforeEach(async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 812 });
  });

  test.describe('Retired report screens', () => {
    // These five used to be screens here, and they wrote her own reports from an open
    // surface: the bot files a body reading, a yearning, a hygiene event and the three
    // cage writes under `:slave` without being told, so the page that sent the write was
    // the only thing that knew whose hand was on the screen. They make them on her own
    // panel behind her own link now (§44), and each path hands the bookmark there.
    for (const path of [
      '/yearning-phone',
      '/body-phone',
      '/devotion-phone',
      '/habits-phone',
      '/habit-anchors',
    ]) {
      test(`should send ${path} to her panel`, async ({ page }) => {
        const response = await page.goto(`${BASE_URL}${path}`);

        // A 302 with a destination, not a 404: the path was a real screen, and a phone
        // may hold it as a home-screen icon. `/habits-phone` is the one this spec used to
        // drive, so the assertion is worth keeping for that path in particular.
        expect([301, 302, 307, 308]).toContain(response?.status());

        await expect(page).toHaveURL(/\?tab=how_i_am$/);
      });
    }
  });

  // Reflect is her panel's now (§47), and it is the report screens' defect exactly: both
  // screens wrote her own words into her journal from a surface anyone on the network can
  // reach, and the write carried no identity at all — a reflection is text, a prompt and a
  // `dedupe_key`, and the store has no notion of a person. What replaced it is drawn on
  // 30014 behind her own link, so both of its paths answer with the move instead of a
  // screen. A 404 would turn "your journal moved" into "you typed it wrong", on a phone,
  // from a home screen icon that was added when the screen was real.
  test.describe('Reflection Phone Handheld — retired into her panel', () => {
    for (const path of ['/reflection', '/reflect-phone']) {
      test(`${path} answers with a move, not a 404`, async ({ page }) => {
        const response = await page.request.get(`${BASE_URL}${path}`, { maxRedirects: 0 });

        expect(response.status()).toBe(302);
        expect(response.headers()['location']).toContain(':30014/?tab=reflect');
      });
    }
  });

  // Energy is her panel's now (§49), and it is the quietest retire of the set: the
  // check-in went out as a `Gnat.pub/3` to `events.context.updated`, a publish with no
  // reply, so "Context saved" was drawn over a byte that only had to reach the socket —
  // with no subscriber it reached nobody. The reading is about her rather than a decision
  // about her, so there is nothing to gate; her panel asks `wife_care.energy.record` and
  // reads the reading back, on 30014 behind her own link. Both paths answer with the move
  // instead of a screen, for the same reason as the others: a 404 would turn "how you are
  // moved" into "you typed it wrong", on a phone, from a home screen icon.
  test.describe('Energy-Mood Phone Handheld — retired into her panel', () => {
    for (const path of ['/energy-mood-phone', '/energy-mood-handheld']) {
      test(`${path} answers with a move, not a 404`, async ({ page }) => {
        const response = await page.request.get(`${BASE_URL}${path}`, { maxRedirects: 0 });

        expect(response.status()).toBe(302);
        expect(response.headers()['location']).toContain(':30014/?tab=energy');
      });
    }
  });

  // The timer and the quest are the last two to leave, and they are worth pinning apart
  // because they are not the reports' defect. The timer screen had the *energy* defect a
  // second time — the session was filed with a publish nobody had to read, and its id was
  // kept in the page, where a reload took it — and her panel's Timers group holds the
  // session in the bridge (§51). The quest screen had the *GTD* defect: a progress bar and a
  // streak drawn over the box her tasks live in, where her panel counts the open steps
  // (§50). A 404 would turn "your session moved" into "you typed it wrong", on a phone.
  test.describe('Timer and Quest Phone Handhelds — retired into her panel', () => {
    for (const [path, tab] of [
      ['/timer-phone', 'timer'],
      ['/timer-handheld', 'timer'],
      ['/quest-phone', 'quest'],
      ['/quest-status', 'quest'],
    ] as const) {
      test(`${path} answers with a move, not a 404`, async ({ page }) => {
        const response = await page.request.get(`${BASE_URL}${path}`, { maxRedirects: 0 });

        expect(response.status()).toBe(302);
        expect(response.headers()['location']).toContain(`:30014/?tab=${tab}`);
      });
    }
  });

  test.describe('Fitness Phone Handheld', () => {
    test('should load fitness page', async ({ page }) => {
      await page.goto(`${BASE_URL}/fitness-phone`);
      await expect(page.locator('.view-title')).toContainText('Log Workout');
    });

    test('should display step counter', async ({ page }) => {
      await page.goto(`${BASE_URL}/fitness-phone`);

      const stepNumber = page.locator('.step-number');
      await expect(stepNumber).toContainText('1 of 3');
    });

    test('should show workout type display', async ({ page }) => {
      await page.goto(`${BASE_URL}/fitness-phone`);

      const typeDisplay = page.locator('.workout-type-display');
      await expect(typeDisplay).toBeVisible();
    });
  });

  // The GTD screen is her panel's now (§45). The box it drew — a list, a defer and a done
  // over `bridge.task.*` — is drawn on 30014 behind her own link, so both of its paths
  // answer with the move instead of a screen. A 404 would turn "the tasks moved" into "you
  // typed it wrong", on a phone, from a home screen icon that was added when it was real.
  test.describe('GTD Phone Handheld — retired into her panel', () => {
    for (const path of ['/gtd-phone', '/gtd-handheld']) {
      test(`${path} answers with a move, not a 404`, async ({ page }) => {
        const response = await page.request.get(`${BASE_URL}${path}`, { maxRedirects: 0 });

        expect(response.status()).toBe(302);
        expect(response.headers()['location']).toContain(':30014/?tab=tasks');
      });
    }
  });

  test.describe('System Health Phone Handheld', () => {
    test('should load health page', async ({ page }) => {
      await page.goto(`${BASE_URL}/system-health-phone`);
      await expect(page.locator('.view-title')).toContainText('System Health');
    });

    test('should display NATS status', async ({ page }) => {
      await page.goto(`${BASE_URL}/system-health-phone`);

      const natsStatus = page.locator('.nats-status');
      await expect(natsStatus).toBeVisible();
    });
  });

  test.describe('Session History Phone Handheld', () => {
    test('should load history page', async ({ page }) => {
      await page.goto(`${BASE_URL}/session-history-phone`);
      await expect(page.locator('.view-title')).toContainText('Session History');
    });

    test('should display stats grid', async ({ page }) => {
      await page.goto(`${BASE_URL}/session-history-phone`);

      const statsGrid = page.locator('.stats-grid');
      await expect(statsGrid).toBeVisible();

      // Check for stat cards
      const statCards = page.locator('.stat-card');
      const count = await statCards.count();
      expect(count).toBeGreaterThan(0);
    });
  });

  test.describe('Navigation', () => {
    test('should navigate between pages via nav bar', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // The bar carries the screens that are here. Habits used to be one and is not any
      // more — nor is the timer, which left with the quest (§50/§51) — so this walks the
      // house instead, which is the screen she lives on.
      const houseLink = page.locator('.nav-item:has-text("House")');
      await expect(houseLink).toBeVisible();
      await houseLink.click();
      await page.waitForURL('**/household-hud');
      await expect(page).toHaveURL(/household-hud/);
    });

    test('should not offer a retired report screen in the bar', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      for (const label of ['Yearning', 'Body', 'Devotion', 'Habits', 'Anchors', 'Timer', 'Quest']) {
        await expect(page.locator(`.nav-item:has-text("${label}")`)).toHaveCount(0);
      }
    });

    test('should show search in context menu', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // Open context menu
      await page.evaluate(() => {
        const event = new CustomEvent('long-press', { bubbles: true });
        document.querySelector('.handheld-container')?.dispatchEvent(event);
      });

      // Check for search input
      const searchInput = page.locator('.search-input');
      if (await searchInput.isVisible()) {
        await expect(searchInput).toHaveAttribute('placeholder', /search/i);
      }
    });
  });

  test.describe('Accessibility', () => {
    test('should have minimum touch target sizes', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // Check control hints have min-height
      const controlHints = page.locator('.control-hint');
      const count = await controlHints.count();

      if (count > 0) {
        const firstHint = controlHints.first();
        const box = await firstHint.boundingBox();
        expect(box?.height).toBeGreaterThanOrEqual(44); // Minimum 44px
      }
    });

    test('should have readable text sizes', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // Check view title size
      const title = page.locator('.view-title');
      const styles = await title.evaluate(el => window.getComputedStyle(el));
      const fontSize = parseFloat(styles.fontSize);
      expect(fontSize).toBeGreaterThanOrEqual(16); // Minimum readable size
    });

    test('should have sufficient color contrast', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // Check that text is visible
      const title = page.locator('.view-title');
      await expect(title).toBeVisible();

      const card = page.locator('.phone-card');
      await expect(card).toBeVisible();
    });

    test('should support keyboard navigation', async ({ page }) => {
      await page.goto(`${BASE_URL}/household-hud`);

      // This used to focus the reflect screen's textarea — a screen that is her panel's
      // now (§47), so the check had begun passing by finding nothing. Keep the lesson on a
      // control that is actually here: a bar link has to be reachable and focusable.
      const navLink = page.locator('.phone-nav-bar a').first();
      await navLink.focus();
      const focused = await navLink.evaluate((el: HTMLElement) => el === document.activeElement);
      expect(focused).toBeTruthy();
    });
  });
});
