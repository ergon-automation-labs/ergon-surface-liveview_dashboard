// Touch gesture detection for carousel/phone interfaces
// Emits events to LiveView: swipe-left, swipe-right, swipe-up, swipe-down, tap, long-press

export const initTouchGestures = (element, liveViewHook) => {
  let touchStartX = 0;
  let touchStartY = 0;
  let touchStartTime = 0;
  let longPressTimer = null;

  const SWIPE_THRESHOLD = 50; // pixels
  const VERTICAL_THRESHOLD = 50; // pixels
  const LONG_PRESS_DURATION = 500; // ms
  const MIN_TAP_DURATION = 50; // ms

  const handleTouchStart = (e) => {
    if (e.touches.length === 0) return;

    touchStartX = e.touches[0].clientX;
    touchStartY = e.touches[0].clientY;
    touchStartTime = Date.now();

    // Start long-press timer
    longPressTimer = setTimeout(() => {
      liveViewHook.pushEvent("long-press", {});
      longPressTimer = null;
    }, LONG_PRESS_DURATION);
  };

  const handleTouchEnd = (e) => {
    if (e.changedTouches.length === 0) return;

    // Clear long-press timer if touch ended
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }

    const touchEndX = e.changedTouches[0].clientX;
    const touchEndY = e.changedTouches[0].clientY;
    const touchDuration = Date.now() - touchStartTime;

    const deltaX = touchEndX - touchStartX;
    const deltaY = touchEndY - touchStartY;
    const absDeltaX = Math.abs(deltaX);
    const absDeltaY = Math.abs(deltaY);

    // Swipe horizontal
    if (
      absDeltaX > SWIPE_THRESHOLD &&
      absDeltaY < VERTICAL_THRESHOLD &&
      touchDuration < LONG_PRESS_DURATION
    ) {
      if (deltaX > 0) {
        liveViewHook.pushEvent("swipe-right", {});
      } else {
        liveViewHook.pushEvent("swipe-left", {});
      }
      return;
    }

    // Swipe vertical
    if (
      absDeltaY > SWIPE_THRESHOLD &&
      absDeltaX < VERTICAL_THRESHOLD &&
      touchDuration < LONG_PRESS_DURATION
    ) {
      if (deltaY > 0) {
        liveViewHook.pushEvent("swipe-down", {});
      } else {
        liveViewHook.pushEvent("swipe-up", {});
      }
      return;
    }

    // Tap (minimal movement)
    if (
      absDeltaX < 10 &&
      absDeltaY < 10 &&
      touchDuration >= MIN_TAP_DURATION &&
      touchDuration < LONG_PRESS_DURATION
    ) {
      liveViewHook.pushEvent("tap", {});
      return;
    }
  };

  const handleTouchCancel = () => {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
  };

  element.addEventListener("touchstart", handleTouchStart, false);
  element.addEventListener("touchend", handleTouchEnd, false);
  element.addEventListener("touchcancel", handleTouchCancel, false);

  // Cleanup function
  return () => {
    element.removeEventListener("touchstart", handleTouchStart);
    element.removeEventListener("touchend", handleTouchEnd);
    element.removeEventListener("touchcancel", handleTouchCancel);
    if (longPressTimer) clearTimeout(longPressTimer);
  };
};

// Hook for use in Phoenix LiveView templates
export const TouchCarouselHook = {
  mounted() {
    const container = this.el;
    this.cleanup = initTouchGestures(container, this);
  },

  destroyed() {
    if (this.cleanup) this.cleanup();
  }
};
