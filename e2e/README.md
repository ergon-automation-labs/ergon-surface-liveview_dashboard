# Nova Handheld E2E Tests

Playwright-based end-to-end tests for the Nova handheld interfaces (fitness, system health), plus the redirects the retired ones left behind.

## What's Tested

- **Energy/Mood Handheld** — *retired.* The screen is her panel's **Energy** group now
  (§49), and its defect was the quietest of the set: the check-in was a `Gnat.pub/3` to
  `events.context.updated`, a publish with no reply, so "Context saved" confirmed only
  that a byte had reached the socket — and with no subscriber it reached nobody. The
  reading is about her rather than a decision about her, so nothing is gated; the panel
  asks `wife_care.energy.record` and reads the reading back. `/energy-mood-phone` and
  `/energy-mood-handheld` both answer with a `302` into that group; the screen's own
  spec (`tests/energy-mood.spec.ts`) went with it, and the redirect is pinned in
  `phone-handhelds.spec.ts`.

- **GTD Handheld** — *retired.* The screen is her panel's **Tasks** group now (§45:
  the box a task list is an answer to is hers, and it is drawn behind her own link).
  `/gtd-handheld` and `/gtd-phone` both answer with a `302` into it; the two tests that
  pinned that screen's gamepad walkthrough went with it, and the redirect is pinned in
  `phone-handhelds.spec.ts`.

- **Reflect Phone** — *retired.* The screen is her panel's **Reflect** group now (§47), and
  it is the report screens' defect exactly: the write had **no identity in it at all** — a
  reflection is text, a prompt and a `dedupe_key`, and the store has no notion of a person —
  so the page that sent it answered *whose words are these* by itself, on a surface anyone
  on the network can reach. `/reflection` and `/reflect-phone` both answer with a `302` into
  that group; the five tests that pinned the screen's prompt, textarea, character count and
  title went with it, and the redirect is pinned in `phone-handhelds.spec.ts`.

- **System Health Handheld** (`/system-health-handheld`)
  - Bot listing and navigation
  - NATS status display
  - Bot detail view
  - Status indicators and heartbeat info
  - Subject listing

## Setup

```bash
cd e2e
npm install
```

## Running Tests

```bash
# Run all tests
npm test

# Run with UI (interactive)
npm run test:ui

# Run in debug mode (step through)
npm run test:debug

# Run tests in headed mode (see browser)
npm run test:headed

# View test report
npm run report
```

## Prerequisites

- Elixir/Phoenix dashboard running on `localhost:4000`
- Tests will auto-start the Phoenix server if not running

```bash
cd ..
mix phx.server
```

## Gamepad Event Simulation

Tests simulate gamepad input through Phoenix LiveView event dispatching:

- `pressUp()` - D-pad up
- `pressDown()` - D-pad down
- `pressA()` - A button
- `pressB()` - B button
- `pressX()` - X button
- `pressY()` - Y button

## Test Structure

- `helpers/gamepad.ts` - Gamepad event simulation utilities
- `tests/system-health.spec.ts` - System health interface tests

## Adding New Tests

Example test:

```typescript
import { test, expect } from '@playwright/test';
import { pressDown, getSelectedItem } from '../helpers/gamepad';

test('should do something', async ({ page }) => {
  await page.goto('/some-handheld');
  
  // Simulate input
  await pressDown(page);
  
  // Assert
  const selected = await getSelectedItem(page);
  expect(selected).toContain('Expected text');
});
```

## CI/CD Integration

Tests are configured to run in CI mode. Set `CI=true` environment variable for stricter validation:

```bash
CI=true npm test
```

In CI mode:
- Tests run serially (workers: 1)
- Failed tests retry 2x
- HTML report is generated
- Slower timeouts to account for container startup

## Debugging

### View browser interactions
```bash
npm run test:headed
```

### Step through tests
```bash
npm run test:debug
```

### Check test output
```bash
npm run report
```

## Notes

- Tests use mocked gamepad events (Phoenix LiveView custom events)
- NATS integration is tested via event dispatch, not actual NATS calls
- Tests assume the dashboard is compiled and running
- Timing: 100ms wait after each gamepad event for LiveView to process
