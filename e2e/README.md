# Nova Handheld E2E Tests

Playwright-based end-to-end tests for the Nova handheld interfaces (GTD, fitness, system health, energy/mood).

## What's Tested

- **Energy/Mood Handheld** (`/energy-mood-handheld`)
  - D-pad navigation through energy levels and moods
  - View transitions
  - Button actions (A/B)
  - Message feedback
  - State display and descriptions

- **GTD Handheld** (`/gtd-handheld`)
  - Project listing and navigation
  - Project-to-tasks transition
  - Task navigation and selection
  - Control hints display
  - Empty state handling

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
- `tests/energy-mood.spec.ts` - Energy/mood checkpoint tests
- `tests/gtd-handheld.spec.ts` - GTD interface tests
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
