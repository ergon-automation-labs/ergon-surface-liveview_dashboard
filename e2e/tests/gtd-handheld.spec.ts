import { test, expect } from '@playwright/test';
import {
  pressUp,
  pressDown,
  pressA,
  pressB,
  getSelectedItem,
  getViewMode,
} from '../helpers/gamepad';

test.describe('GTD Handheld', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/gtd-handheld');
    // Wait for projects to load
    await page.locator('.projects-view').waitFor({ timeout: 5000 });
  });

  test('should load with projects view', async ({ page }) => {
    const title = await page.locator('.view-title').textContent();
    expect(title).toContain('Projects');
  });

  test('should navigate projects with D-pad', async ({ page }) => {
    // Get initial selection
    let selected = await getSelectedItem(page);
    expect(selected).toBeTruthy();

    const initialSelected = selected;

    // Press down to change selection
    await pressDown(page);
    selected = await getSelectedItem(page);

    // If there are multiple projects, selection should change
    const items = page.locator('.current-item');
    const count = await items.count();
    if (count > 1) {
      expect(selected).not.toEqual(initialSelected);
    }

    // Press up to go back
    await pressUp(page);
    selected = await getSelectedItem(page);
    expect(selected).toEqual(initialSelected);
  });

  test('should show project counter', async ({ page }) => {
    const counter = page.locator('.counter');
    const text = await counter.textContent();
    expect(text).toMatch(/\d+ \/ \d+/); // Should show "X / Y" format
  });

  test('should transition to tasks view on A button', async ({ page }) => {
    // Select first project
    let view = await getViewMode(page);
    expect(view).toContain('Projects');

    // Press A to view tasks
    await pressA(page);

    // Wait for tasks view to load
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    view = await getViewMode(page);
    expect(view).toContain('Tasks');
  });

  test('should go back to projects on B button', async ({ page }) => {
    // Go to tasks view
    await pressA(page);
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    // Press B to go back
    await pressB(page);

    // Should be back at projects
    const view = await getViewMode(page);
    expect(view).toContain('Projects');
  });

  test('should display control hints for projects view', async ({ page }) => {
    const hints = page.locator('.control-hint');
    const hintsText = await hints.allTextContents();
    const hintsStr = hintsText.join(' ');

    expect(hintsStr).toContain('Navigate');
    expect(hintsStr).toContain('View Tasks');
  });

  test('should display control hints for tasks view', async ({ page }) => {
    await pressA(page);
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    const hints = page.locator('.control-hint');
    const hintsText = await hints.allTextContents();
    const hintsStr = hintsText.join(' ');

    expect(hintsStr).toContain('Navigate');
    expect(hintsStr).toContain('Complete');
    expect(hintsStr).toContain('Defer');
    expect(hintsStr).toContain('Add Note');
  });

  test('should navigate tasks when in tasks view', async ({ page }) => {
    await pressA(page);
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    const taskItems = page.locator('.current-item');
    const count = await taskItems.count();

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

  test('should show task counter in tasks view', async ({ page }) => {
    await pressA(page);
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    const counter = page.locator('.counter');
    const text = await counter.textContent();
    expect(text).toMatch(/\d+ \/ \d+/);
  });

  test('should show task status and due date when available', async ({ page }) => {
    await pressA(page);
    await page.locator('.tasks-view').waitFor({ timeout: 5000 });

    // Select first task (highlighted)
    const selectedTask = page.locator('.current-item.selected').first();
    const text = await selectedTask.textContent();

    // Should show status or other metadata
    expect(text).toBeTruthy();
  });

  test('should handle empty states gracefully', async ({ page }) => {
    const emptyState = page.locator('.empty-state');
    const isVisible = await emptyState.isVisible().catch(() => false);

    if (isVisible) {
      const text = await emptyState.textContent();
      expect(text).toBeTruthy();
    } else {
      // If not empty, there should be items to navigate
      const items = page.locator('.current-item');
      const count = await items.count();
      expect(count).toBeGreaterThan(0);
    }
  });
});
