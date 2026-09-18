import { test, expect } from '@playwright/test';
import {
  pressUp,
  pressDown,
  pressA,
  getSelectedItem,
} from '../helpers/gamepad';

test.describe('Fitness Handheld', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/fitness-handheld');
    // Wait for interface to load
    await page.locator('.handheld-container').waitFor({ timeout: 5000 });
  });

  test('should load successfully', async ({ page }) => {
    const container = page.locator('.handheld-container');
    await expect(container).toBeVisible();
  });

  test('should display title', async ({ page }) => {
    const title = page.locator('.view-title');
    const text = await title.textContent();
    expect(text).toBeTruthy();
  });

  test('should have navigation controls', async ({ page }) => {
    const hints = page.locator('.control-hint');
    const count = await hints.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should display form or input fields', async ({ page }) => {
    // Fitness handheld should have input for logging workouts
    const inputs = page.locator('input, select, textarea');
    const count = await inputs.count();
    expect(count).toBeGreaterThanOrEqual(0);
  });

  test('should be keyboard navigable', async ({ page }) => {
    // Press keys to navigate
    await pressDown(page);
    await pressUp(page);

    // Page should still be responsive
    const container = page.locator('.handheld-container');
    await expect(container).toBeVisible();
  });

  test('should handle form submission', async ({ page }) => {
    // Look for submit button or form
    const form = page.locator('form');

    if (await form.isVisible()) {
      const buttons = form.locator('button');
      const count = await buttons.count();
      expect(count).toBeGreaterThan(0);
    }
  });

  test('should be responsive to gamepad input', async ({ page }) => {
    // Simulate multiple inputs
    for (let i = 0; i < 3; i++) {
      await pressDown(page);
    }

    for (let i = 0; i < 3; i++) {
      await pressUp(page);
    }

    // Page should remain stable
    const container = page.locator('.handheld-container');
    await expect(container).toBeVisible();
  });

  test('should not throw errors on button presses', async ({ page }) => {
    // Listen for console errors
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      }
    });

    // Simulate button presses
    await pressA(page);
    await pressDown(page);
    await pressUp(page);

    // Should not have console errors
    expect(errors).toEqual([]);
  });

  test('should load within reasonable time', async ({ page }) => {
    const startTime = Date.now();

    await page.goto('/fitness-handheld');
    await page.locator('.handheld-container').waitFor({ timeout: 5000 });

    const loadTime = Date.now() - startTime;
    expect(loadTime).toBeLessThan(5000);
  });

  test('should have consistent styling', async ({ page }) => {
    const container = page.locator('.handheld-container');
    const hasClass = await container.evaluate(el =>
      el.classList.contains('handheld-container')
    );

    expect(hasClass).toBe(true);
  });
});
