# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: energy-mood.spec.ts >> Energy/Mood Handheld >> should navigate energy levels with D-pad
- Location: tests/energy-mood.spec.ts:23:7

# Error details

```
Test timeout of 30000ms exceeded.
```

```
Error: locator.textContent: Test timeout of 30000ms exceeded.
Call log:
  - waiting for locator('.current-item.selected').first()

```

# Page snapshot

```yaml
- generic [ref=e5]:
  - generic [ref=e6]: Your Energy
  - generic [ref=e7]:
    - generic [ref=e8]: ⚙️
    - generic [ref=e9]:
      - generic [ref=e10] [cursor=pointer]: Low
      - generic [ref=e11] [cursor=pointer]: Medium
      - generic [ref=e12] [cursor=pointer]: High
  - paragraph [ref=e14]: Steady state, normal operations
  - generic [ref=e15]:
    - generic [ref=e16]:
      - generic [ref=e17]: ↑ ↓
      - generic [ref=e18]: Navigate
    - generic [ref=e19]:
      - generic [ref=e20]: A
      - generic [ref=e21]: "Next: Mood"
```

# Test source

```ts
  1   | import { Page } from '@playwright/test';
  2   | 
  3   | /**
  4   |  * Simulate gamepad input via Phoenix LiveView phx-click events
  5   |  * The handheld interfaces listen for "gamepad-*" events
  6   |  */
  7   | 
  8   | export async function simulateGamepadEvent(
  9   |   page: Page,
  10  |   eventName: 'up' | 'down' | 'left' | 'right' | 'a' | 'b' | 'x' | 'y'
  11  | ) {
  12  |   const event = `gamepad-${eventName}`;
  13  | 
  14  |   // Dispatch the event that the handheld listeners expect
  15  |   await page.evaluate((evt) => {
  16  |     // Find any element with phx event listeners and dispatch
  17  |     const form = document.querySelector('form[phx-change], [phx-click]');
  18  |     if (form) {
  19  |       const pushEvent = (form as any).__phx_data?.push || window.__phx_data?.push;
  20  |       if (pushEvent) {
  21  |         pushEvent(evt, {});
  22  |       }
  23  |     }
  24  | 
  25  |     // Also try direct event dispatch as fallback
  26  |     window.dispatchEvent(
  27  |       new CustomEvent(evt, {
  28  |         detail: { params: {} },
  29  |         bubbles: true,
  30  |       })
  31  |     );
  32  |   }, event);
  33  | 
  34  |   // Give Phoenix time to process the event
  35  |   await page.waitForTimeout(100);
  36  | }
  37  | 
  38  | export async function pressUp(page: Page) {
  39  |   await simulateGamepadEvent(page, 'up');
  40  | }
  41  | 
  42  | export async function pressDown(page: Page) {
  43  |   await simulateGamepadEvent(page, 'down');
  44  | }
  45  | 
  46  | export async function pressA(page: Page) {
  47  |   await simulateGamepadEvent(page, 'a');
  48  | }
  49  | 
  50  | export async function pressB(page: Page) {
  51  |   await simulateGamepadEvent(page, 'b');
  52  | }
  53  | 
  54  | export async function pressX(page: Page) {
  55  |   await simulateGamepadEvent(page, 'x');
  56  | }
  57  | 
  58  | export async function pressY(page: Page) {
  59  |   await simulateGamepadEvent(page, 'y');
  60  | }
  61  | 
  62  | /**
  63  |  * Wait for a message to appear on screen (status/feedback)
  64  |  */
  65  | export async function waitForMessage(page: Page, text?: string) {
  66  |   if (text) {
  67  |     await page.locator('.message').filter({ hasText: text }).waitFor({ timeout: 2000 });
  68  |   } else {
  69  |     await page.locator('.message').waitFor({ timeout: 2000 });
  70  |   }
  71  | }
  72  | 
  73  | /**
  74  |  * Wait for a message to disappear
  75  |  */
  76  | export async function waitForMessageCleared(page: Page) {
  77  |   const message = page.locator('.message');
  78  |   await message.waitFor({ state: 'hidden', timeout: 3000 });
  79  | }
  80  | 
  81  | /**
  82  |  * Get the currently selected item text
  83  |  */
  84  | export async function getSelectedItem(page: Page): Promise<string> {
  85  |   const selected = await page.locator('.current-item.selected').first();
> 86  |   const text = await selected.textContent();
      |                               ^ Error: locator.textContent: Test timeout of 30000ms exceeded.
  87  |   return text?.trim() || '';
  88  | }
  89  | 
  90  | /**
  91  |  * Get all visible items in the list
  92  |  */
  93  | export async function getVisibleItems(page: Page): Promise<string[]> {
  94  |   const items = await page.locator('.current-item').allTextContents();
  95  |   return items.map(t => t.trim());
  96  | }
  97  | 
  98  | /**
  99  |  * Get current view mode (energy, mood, projects, tasks, etc)
  100 |  */
  101 | export async function getViewMode(page: Page): Promise<string> {
  102 |   const title = await page.locator('.view-title').first().textContent();
  103 |   return title?.trim() || '';
  104 | }
  105 | 
```