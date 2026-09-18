import { test, expect } from '@playwright/test';
import {
  pressUp,
  pressDown,
  pressA,
  pressB,
  getSelectedItem,
  getViewMode,
  waitForMessage,
  getVisibleItems,
} from '../helpers/gamepad';

test.describe('Energy/Mood Handheld', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/energy-mood-handheld');
  });

  test('should load with energy view', async ({ page }) => {
    const title = await page.locator('.view-title').textContent();
    expect(title).toContain('Energy');
  });

  test('should navigate energy levels with D-pad', async ({ page }) => {
    // Start at Medium (index 1)
    let selected = await getSelectedItem(page);
    expect(selected).toContain('Medium');

    // Press down
    await pressDown(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('High');

    // Press down again (should stay at High - boundary)
    await pressDown(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('High');

    // Press up
    await pressUp(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('Medium');

    // Press up again
    await pressUp(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('Low');
  });

  test('should show description for selected energy level', async ({ page }) => {
    const description = page.locator('.description p');

    // Medium (default)
    let text = await description.textContent();
    expect(text).toContain('Steady state');

    // Down to High
    await pressDown(page);
    text = await description.textContent();
    expect(text).toContain('Energized');

    // Up to Low
    await pressUp(page);
    await pressUp(page);
    text = await description.textContent();
    expect(text).toContain('Resting');
  });

  test('should transition to mood view on A button', async ({ page }) => {
    let view = await getViewMode(page);
    expect(view).toContain('Energy');

    await pressA(page);
    view = await getViewMode(page);
    expect(view).toContain('Mood');
  });

  test('should navigate moods in mood view', async ({ page }) => {
    // Go to mood view
    await pressA(page);

    // Should start at Focused (first mood)
    let selected = await getSelectedItem(page);
    expect(selected).toContain('Focused');

    // Navigate down through moods
    await pressDown(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('Creative');

    await pressDown(page);
    selected = await getSelectedItem(page);
    expect(selected).toContain('Energized');
  });

  test('should go back to energy view on B button', async ({ page }) => {
    await pressA(page); // energy -> mood
    let view = await getViewMode(page);
    expect(view).toContain('Mood');

    await pressB(page); // mood -> energy
    view = await getViewMode(page);
    expect(view).toContain('Energy');
  });

  test('should show description for selected mood', async ({ page }) => {
    await pressA(page); // energy -> mood

    const description = page.locator('.description p');

    // Focused (default)
    let text = await description.textContent();
    expect(text).toContain('Deep work');

    // Navigate to Creative
    await pressDown(page);
    text = await description.textContent();
    expect(text).toContain('Brainstorm');

    // Navigate to Recovering
    await pressDown(page);
    await pressDown(page);
    await pressDown(page);
    await pressDown(page);
    text = await description.textContent();
    expect(text).toContain('Rest');
  });

  test('should save energy and mood selection on A in mood view', async ({ page }) => {
    // Select Low energy
    await pressDown(page);
    await pressDown(page);
    await pressUp(page); // Low

    // Go to mood view
    await pressA(page);

    // Select Creative mood
    await pressDown(page);

    // Save with A button
    await pressA(page);

    // Should show "Saving..." message
    await waitForMessage(page, 'Saving');

    // In a real scenario with NATS, this would publish to events.context.updated
    // For now we're just testing the UI flow
  });

  test('should show all energy levels', async ({ page }) => {
    const items = await getVisibleItems(page);
    expect(items.length).toBeGreaterThanOrEqual(3);
    expect(items.some(item => item.includes('Low'))).toBe(true);
    expect(items.some(item => item.includes('Medium'))).toBe(true);
    expect(items.some(item => item.includes('High'))).toBe(true);
  });

  test('should show all mood options', async ({ page }) => {
    await pressA(page); // energy -> mood

    const items = await getVisibleItems(page);
    const moods = ['Focused', 'Creative', 'Energized', 'Calm', 'Recovering', 'Scattered'];

    for (const mood of moods) {
      expect(items.some(item => item.includes(mood))).toBe(true);
    }
  });

  test('should display emoji indicators', async ({ page }) => {
    // Energy view should show emoji
    let emoji = page.locator('.emoji').first();
    let emojiText = await emoji.textContent();
    expect(emojiText).toBeTruthy(); // Should have some emoji

    // Go to mood view
    await pressA(page);

    // Mood view should also show emoji
    emoji = page.locator('.emoji').first();
    emojiText = await emoji.textContent();
    expect(emojiText).toBeTruthy();
  });

  test('should display control hints', async ({ page }) => {
    const hints = page.locator('.control-hint');
    const hints_text = await hints.allTextContents();
    const hintsStr = hints_text.join(' ');

    expect(hintsStr).toContain('↑ ↓');
    expect(hintsStr).toContain('Navigate');
  });
});
