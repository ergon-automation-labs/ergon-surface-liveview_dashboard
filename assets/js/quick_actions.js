// Quick action handlers for phone handhelds
// Enables swipe-to-complete, long-press menus, gesture shortcuts

export const QuickActionsHook = {
  mounted() {
    this.setupSwipeActions();
    this.setupQuickKeys();
  },

  destroyed() {
    this.cleanup();
  },

  setupSwipeActions() {
    const container = this.el;
    if (!container) return;

    // Find all swipeable items (marked with data-swipeable)
    const swipeables = container.querySelectorAll('[data-swipeable]');

    swipeables.forEach(item => {
      let startX = 0;
      let currentX = 0;

      const onTouchStart = (e) => {
        startX = e.touches[0].clientX;
        currentX = startX;
      };

      const onTouchMove = (e) => {
        currentX = e.touches[0].clientX;
        const delta = startX - currentX;

        // Show swipe hint when user drags
        if (Math.abs(delta) > 20) {
          item.style.transform = `translateX(${-delta * 0.3}px)`;
          item.style.opacity = Math.max(0.7, 1 - delta / 300);
        }
      };

      const onTouchEnd = (e) => {
        const delta = startX - currentX;
        const threshold = 80;

        // Swipe left = complete/delete action
        if (delta > threshold) {
          const action = item.dataset.swipeAction || 'complete';
          this.pushEvent('quick-action', {
            action,
            itemId: item.dataset.itemId,
            itemType: item.dataset.itemType
          });
          item.style.transition = 'all 0.3s ease';
          item.style.transform = 'translateX(-100%)';
          item.style.opacity = '0';
        } else {
          // Reset
          item.style.transition = 'all 0.2s ease';
          item.style.transform = 'translateX(0)';
          item.style.opacity = '1';
        }

        item.removeEventListener('touchmove', onTouchMove);
        item.removeEventListener('touchend', onTouchEnd);
      };

      item.addEventListener('touchstart', onTouchStart);
      item.addEventListener('touchmove', onTouchMove);
      item.addEventListener('touchend', onTouchEnd);
    });
  },

  setupQuickKeys() {
    // Double-tap (within 300ms) = quick save
    let lastTapTime = 0;
    let lastTapElement = null;

    this.el.addEventListener('click', (e) => {
      const now = Date.now();
      const target = e.target.closest('[data-quick-action]');

      if (target && lastTapElement === target && now - lastTapTime < 300) {
        const action = target.dataset.quickAction;
        this.pushEvent('quick-action', {
          action,
          itemId: target.dataset.itemId,
          itemType: target.dataset.itemType
        });
        lastTapTime = 0;
        lastTapElement = null;
      } else {
        lastTapTime = now;
        lastTapElement = target;
      }
    });
  },

  cleanup() {
    // Cleanup listeners if needed
  }
};

// Utility: Check if device supports swipe actions
export const isSwipeCapable = () => {
  return 'ontouchstart' in window || navigator.maxTouchPoints > 0;
};

// Utility: Format action hint for display
export const getActionHint = (action) => {
  const hints = {
    complete: '✓ Swipe to complete',
    defer: '→ Swipe to defer',
    delete: '✕ Swipe to delete',
    save: '💾 Double-tap to save',
    close: '✕ Swipe to close'
  };
  return hints[action] || 'Swipe to action';
};
