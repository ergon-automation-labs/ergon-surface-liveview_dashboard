import { Page } from '@playwright/test';

/**
 * Simulate gamepad input via Phoenix LiveView phx-click events
 * The handheld interfaces listen for "gamepad-*" events
 */

export async function simulateGamepadEvent(
  page: Page,
  eventName: 'up' | 'down' | 'left' | 'right' | 'a' | 'b' | 'x' | 'y'
) {
  const event = `gamepad-${eventName}`;

  // Dispatch the event that the handheld listeners expect
  await page.evaluate((evt) => {
    // Find any element with phx event listeners and dispatch
    const form = document.querySelector('form[phx-change], [phx-click]');
    if (form) {
      const pushEvent = (form as any).__phx_data?.push || window.__phx_data?.push;
      if (pushEvent) {
        pushEvent(evt, {});
      }
    }

    // Also try direct event dispatch as fallback
    window.dispatchEvent(
      new CustomEvent(evt, {
        detail: { params: {} },
        bubbles: true,
      })
    );
  }, event);

  // Give Phoenix time to process the event
  await page.waitForTimeout(100);
}

export async function pressUp(page: Page) {
  await simulateGamepadEvent(page, 'up');
}

export async function pressDown(page: Page) {
  await simulateGamepadEvent(page, 'down');
}

export async function pressA(page: Page) {
  await simulateGamepadEvent(page, 'a');
}

export async function pressB(page: Page) {
  await simulateGamepadEvent(page, 'b');
}

export async function pressX(page: Page) {
  await simulateGamepadEvent(page, 'x');
}

export async function pressY(page: Page) {
  await simulateGamepadEvent(page, 'y');
}

/**
 * Wait for a message to appear on screen (status/feedback)
 */
export async function waitForMessage(page: Page, text?: string) {
  if (text) {
    await page.locator('.message').filter({ hasText: text }).waitFor({ timeout: 2000 });
  } else {
    await page.locator('.message').waitFor({ timeout: 2000 });
  }
}

/**
 * Wait for a message to disappear
 */
export async function waitForMessageCleared(page: Page) {
  const message = page.locator('.message');
  await message.waitFor({ state: 'hidden', timeout: 3000 });
}

/**
 * Get the currently selected item text
 */
export async function getSelectedItem(page: Page): Promise<string> {
  const selected = await page.locator('.current-item.selected').first();
  const text = await selected.textContent();
  return text?.trim() || '';
}

/**
 * Get all visible items in the list
 */
export async function getVisibleItems(page: Page): Promise<string[]> {
  const items = await page.locator('.current-item').allTextContents();
  return items.map(t => t.trim());
}

/**
 * Get current view mode (energy, mood, projects, tasks, etc)
 */
export async function getViewMode(page: Page): Promise<string> {
  const title = await page.locator('.view-title').first().textContent();
  return title?.trim() || '';
}
