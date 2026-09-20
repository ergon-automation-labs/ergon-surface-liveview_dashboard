# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: __tmp_live_fitness_data.spec.ts >> live fitness fetch resolves and leaves the loading state
- Location: tests/__tmp_live_fitness_data.spec.ts:5:5

# Error details

```
Error: expect(locator).toBeHidden() failed

Locator:  getByText(/Loading workouts/i)
Expected: hidden
Received: visible
Timeout:  20000ms

Call log:
  - Expect "toBeHidden" getByText(/Loading workouts/i) with timeout 20000ms
  - waiting for getByText(/Loading workouts/i)
    44 × locator resolved to <p>Loading workouts...</p>
       - unexpected value "visible"

```

```yaml
- paragraph: Loading workouts...
```

# Test source

```ts
  1  | import { test, expect } from '@playwright/test';
  2  | 
  3  | // Temporary live-surface probe: proves the LiveView's NATS fetch to the real
  4  | // fitness bot resolves (placeholder clears) and that no console error fires.
  5  | test('live fitness fetch resolves and leaves the loading state', async ({ page }) => {
  6  |   const errors: string[] = [];
  7  |   page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  8  | 
  9  |   await page.goto('/fitness-handheld');
  10 |   await expect(page.locator('.handheld-container')).toBeVisible();
  11 | 
  12 |   // "Loading workouts..." must be replaced once the NATS reply arrives.
> 13 |   await expect(page.getByText(/Loading workouts/i)).toBeHidden({ timeout: 20000 });
     |                                                     ^ Error: expect(locator).toBeHidden() failed
  14 |   expect(errors).toEqual([]);
  15 | });
  16 | 
```