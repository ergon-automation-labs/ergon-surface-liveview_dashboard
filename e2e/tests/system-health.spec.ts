import { test, expect } from '@playwright/test';
import {
  pressUp,
  pressDown,
  pressA,
  pressB,
  getSelectedItem,
  getViewMode,
} from '../helpers/gamepad';

test.describe('System Health Handheld', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/system-health-handheld');
    // Wait for bots to load
    await page.locator('.bots-view').waitFor({ timeout: 5000 });
  });

  test('should load with bots view', async ({ page }) => {
    const title = await page.locator('.view-title').textContent();
    expect(title).toContain('Bot Health');
  });

  test('should show NATS status indicator', async ({ page }) => {
    const natsStatus = page.locator('.nats-status');
    const statusText = await natsStatus.textContent();
    expect(statusText).toMatch(/NATS|Connected|Offline/);
  });

  test('should navigate bots with D-pad', async ({ page }) => {
    const items = page.locator('.current-item');
    const count = await items.count();

    if (count > 1) {
      let selected = await getSelectedItem(page);
      const initialSelected = selected;

      await pressDown(page);
      selected = await getSelectedItem(page);
      expect(selected).not.toEqual(initialSelected);

      await pressUp(page);
      selected = await getSelectedItem(page);
      expect(selected).toEqual(initialSelected);
    }
  });

  test('should show bot counter', async ({ page }) => {
    const counter = page.locator('.counter');
    const text = await counter.textContent();
    expect(text).toMatch(/\d+ \/ \d+/);
  });

  test('should display bot status indicators', async ({ page }) => {
    const statusIndicators = page.locator('.status-indicator');
    const count = await statusIndicators.count();

    if (count > 0) {
      const firstIndicator = statusIndicators.first();
      const emoji = await firstIndicator.textContent();
      expect(emoji).toMatch(/✓|✗|⏸|⚠/);
    }
  });

  test('should transition to bot detail view on A button', async ({ page }) => {
    let view = await getViewMode(page);
    expect(view).toContain('Bot Health');

    await pressA(page);

    // Should show detail view with bot name
    const detail = page.locator('.detail-view');
    await detail.waitFor({ timeout: 2000 });

    view = await getViewMode(page);
    expect(view).toBeTruthy(); // Should still have a title
  });

  test('should display bot details', async ({ page }) => {
    await pressA(page);
    await page.locator('.detail-view').waitFor({ timeout: 2000 });

    // Should show status, heartbeat, subjects
    const sections = page.locator('.detail-section');
    const count = await sections.count();
    expect(count).toBeGreaterThan(0);

    // Check for common section labels
    const text = await page.locator('.detail-content').textContent();
    expect(text).toContain('Status');
  });

  test('should go back to bots list on B button', async ({ page }) => {
    await pressA(page);
    await page.locator('.detail-view').waitFor({ timeout: 2000 });

    await pressB(page);

    // Should be back at bots view
    const botsView = page.locator('.bots-view');
    await botsView.waitFor({ timeout: 2000 });

    const view = await getViewMode(page);
    expect(view).toContain('Bot Health');
  });

  test('should display control hints for bots view', async ({ page }) => {
    const hints = page.locator('.control-hint');
    const hintsText = await hints.allTextContents();
    const hintsStr = hintsText.join(' ');

    expect(hintsStr).toContain('Navigate');
    expect(hintsStr).toContain('Details');
  });

  test('should display control hints for detail view', async ({ page }) => {
    await pressA(page);
    await page.locator('.detail-view').waitFor({ timeout: 2000 });

    const hints = page.locator('.control-hint');
    const hintsText = await hints.allTextContents();
    const hintsStr = hintsText.join(' ');

    expect(hintsStr).toContain('Back');
  });

  test('should show bot heartbeat information', async ({ page }) => {
    await pressA(page);
    await page.locator('.detail-view').waitFor({ timeout: 2000 });

    const heartbeat = page.locator('.section-value').nth(1); // Second section is heartbeat
    const text = await heartbeat.textContent();
    expect(text).toBeTruthy();
  });

  test('should display subjects list in detail view', async ({ page }) => {
    await pressA(page);
    await page.locator('.detail-view').waitFor({ timeout: 2000 });

    const subjects = page.locator('.subject-item');
    const count = await subjects.count();

    // May have subjects or show "—" if none
    if (count > 0) {
      const firstSubject = subjects.first();
      const text = await firstSubject.textContent();
      expect(text).toBeTruthy();
    }
  });

  test('should handle empty state', async ({ page }) => {
    const emptyState = page.locator('.empty-state');
    const isVisible = await emptyState.isVisible().catch(() => false);

    if (isVisible) {
      const text = await emptyState.textContent();
      expect(text).toBeTruthy();
    } else {
      // If not empty, there should be bots
      const bots = page.locator('.current-item');
      const count = await bots.count();
      expect(count).toBeGreaterThan(0);
    }
  });

  test('should allow navigation up/down at boundaries', async ({ page }) => {
    const items = page.locator('.current-item');
    const count = await items.count();

    if (count > 1) {
      // Navigate to end
      for (let i = 0; i < count; i++) {
        await pressDown(page);
      }

      // Try to go further (should stay at end)
      let selected = await getSelectedItem(page);
      const atEnd = selected;
      await pressDown(page);
      selected = await getSelectedItem(page);
      expect(selected).toEqual(atEnd);
    }
  });
});
