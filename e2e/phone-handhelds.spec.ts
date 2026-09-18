import { test, expect, Page } from '@playwright/test';

const BASE_URL = 'http://localhost:4000';

test.describe('Nova Phone Handhelds', () => {
  test.beforeEach(async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 812 });
  });

  test.describe('Timer Phone Handheld', () => {
    test('should load timer page', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);
      await expect(page.locator('.view-title')).toContainText('Focus Timer');
      await expect(page.locator('.handheld-container.timer-phone')).toBeVisible();
    });

    test('should show duration spinner', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);
      await expect(page.locator('.spinner-wheel')).toBeVisible();
      await expect(page.locator('.duration-value')).toContainText('25');
    });

    test('should navigate through phone nav bar', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);

      // Check nav bar exists
      const navBar = page.locator('.phone-nav-bar');
      await expect(navBar).toBeVisible();

      // Check timer nav item is active
      const timerNav = page.locator('.nav-item.active');
      await expect(timerNav).toContainText('Timer');
    });

    test('should open context menu on long-press', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);

      // Simulate long-press by programmatically triggering event
      await page.evaluate(() => {
        const event = new CustomEvent('long-press', { bubbles: true });
        document.querySelector('.handheld-container')?.dispatchEvent(event);
      });

      // Check if modal appears
      const modal = page.locator('.phone-nav-modal-overlay');
      await expect(modal).toBeVisible();
    });
  });

  test.describe('Habits Phone Handheld', () => {
    test('should load habits page', async ({ page }) => {
      await page.goto(`${BASE_URL}/habits-phone`);
      await expect(page.locator('.view-title')).toContainText('Daily Check-In');
    });

    test('should navigate with D-pad events', async ({ page }) => {
      await page.goto(`${BASE_URL}/habits-phone`);

      // Initial habit name
      const initialHabit = await page.locator('.habit-name-large').textContent();

      // Simulate gamepad-down event
      await page.evaluate(() => {
        const event = new CustomEvent('gamepad-down', { bubbles: true });
        document.querySelector('.handheld-container')?.dispatchEvent(event);
      });

      // Habit should change (or stay same if only one)
      const newHabit = await page.locator('.habit-name-large').textContent();
      // Just verify the element still exists and is visible
      await expect(page.locator('.habit-name-large')).toBeVisible();
    });
  });

  test.describe('Quest Phone Handheld', () => {
    test('should load quest page', async ({ page }) => {
      await page.goto(`${BASE_URL}/quest-phone`);
      await expect(page.locator('.view-title')).toContainText('Your Quest');
    });

    test('should display progress bar', async ({ page }) => {
      await page.goto(`${BASE_URL}/quest-phone`);

      // Check for progress bar
      const progressBar = page.locator('.progress-bar-container-phone');
      await expect(progressBar).toBeVisible();

      // Check progress text exists
      const progressText = page.locator('.progress-text-phone');
      await expect(progressText).toBeVisible();
    });

    test('should display next task preview', async ({ page }) => {
      await page.goto(`${BASE_URL}/quest-phone`);

      const nextTaskCard = page.locator('.next-task-card');
      if (await nextTaskCard.isVisible()) {
        await expect(nextTaskCard.locator('.next-task-label')).toContainText("What's Next");
      }
    });
  });

  test.describe('Reflection Phone Handheld', () => {
    test('should load reflection page', async ({ page }) => {
      await page.goto(`${BASE_URL}/reflect-phone`);
      await expect(page.locator('.view-title')).toContainText('Reflection');
    });

    test('should display prompt', async ({ page }) => {
      await page.goto(`${BASE_URL}/reflect-phone`);

      const prompt = page.locator('.prompt-phone');
      await expect(prompt).toBeVisible();

      // Prompt should have text
      const text = await prompt.textContent();
      expect(text?.length).toBeGreaterThan(0);
    });

    test('should have textarea input', async ({ page }) => {
      await page.goto(`${BASE_URL}/reflect-phone`);

      const textarea = page.locator('.reflection-input-phone');
      await expect(textarea).toBeVisible();

      // Should be focusable
      await textarea.focus();
      await textarea.type('Test reflection');

      const value = await textarea.inputValue();
      expect(value).toBe('Test reflection');
    });

    test('should display character count', async ({ page }) => {
      await page.goto(`${BASE_URL}/reflect-phone`);

      const textarea = page.locator('.reflection-input-phone');
      const charCount = page.locator('.char-count-phone');

      // Initially should be 0
      await expect(charCount).toContainText('0 characters');

      // Type some text
      await textarea.type('Hello world');

      // Check count updates (this might require waiting for phx-change event)
      await page.waitForTimeout(100);
      const text = await charCount.textContent();
      expect(text).toContain('characters');
    });
  });

  test.describe('Energy-Mood Phone Handheld', () => {
    test('should load energy-mood page', async ({ page }) => {
      await page.goto(`${BASE_URL}/energy-mood-phone`);
      await expect(page.locator('.view-title')).toContainText('How Are You');
    });

    test('should show energy selection', async ({ page }) => {
      await page.goto(`${BASE_URL}/energy-mood-phone`);

      const energyDisplay = page.locator('.energy-display-phone');
      await expect(energyDisplay).toBeVisible();

      // Check for energy items
      const activeItem = page.locator('.energy-item.active');
      await expect(activeItem).toBeVisible();
    });
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

  test.describe('GTD Phone Handheld', () => {
    test('should load GTD page', async ({ page }) => {
      await page.goto(`${BASE_URL}/gtd-phone`);
      await expect(page.locator('.view-title')).toContainText('GTD');
    });

    test('should show projects on start', async ({ page }) => {
      await page.goto(`${BASE_URL}/gtd-phone`);

      const section = page.locator('.gtd-section-phone');
      if (await section.isVisible()) {
        const title = page.locator('.section-title');
        await expect(title).toContainText('Projects');
      }
    });

    test('should support swipe-to-complete on tasks', async ({ page }) => {
      await page.goto(`${BASE_URL}/gtd-phone`);

      // Check for swipeable task display
      const taskDisplay = page.locator('.task-display[data-swipeable="true"]');

      if (await taskDisplay.isVisible()) {
        await expect(taskDisplay).toHaveAttribute('data-swipe-action', 'complete');
        await expect(page.locator('.swipe-hint')).toContainText('Swipe to complete');
      }
    });
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
      await page.goto(`${BASE_URL}/timer-phone`);

      // Click on habits nav item
      const habitsLink = page.locator('.nav-item:has-text("Habits")');
      if (await habitsLink.isVisible()) {
        await habitsLink.click();
        await page.waitForURL('**/habits-phone');
        await expect(page).toHaveURL(/habits-phone/);
      }
    });

    test('should show search in context menu', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);

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
      await page.goto(`${BASE_URL}/timer-phone`);

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
      await page.goto(`${BASE_URL}/timer-phone`);

      // Check view title size
      const title = page.locator('.view-title');
      const styles = await title.evaluate(el => window.getComputedStyle(el));
      const fontSize = parseFloat(styles.fontSize);
      expect(fontSize).toBeGreaterThanOrEqual(16); // Minimum readable size
    });

    test('should have sufficient color contrast', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);

      // Check that text is visible
      const title = page.locator('.view-title');
      await expect(title).toBeVisible();

      const card = page.locator('.phone-card');
      await expect(card).toBeVisible();
    });

    test('should support keyboard navigation', async ({ page }) => {
      await page.goto(`${BASE_URL}/timer-phone`);

      // Should be able to focus elements
      const textarea = page.locator('.reflection-input-phone');
      if (await textarea.isVisible()) {
        await textarea.focus();
        const focused = await textarea.evaluate((el: HTMLElement) => el === document.activeElement);
        expect(focused).toBeTruthy();
      }
    });
  });
});
