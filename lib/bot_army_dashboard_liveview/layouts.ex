defmodule BotArmyDashboardLiveview.Layouts do
  use Phoenix.Component

  alias BotArmyDashboardLiveview.PhoneNav

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Bot Army Dashboard</title>
        <script defer type="text/javascript" src="https://cdn.jsdelivr.net/npm/phoenix@1.7.0/priv/static/phoenix.min.js"></script>
        <script defer type="text/javascript" src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.0/priv/static/phoenix_live_view.min.js"></script>
        <script defer type="text/javascript">
          // Touch gesture detection hook for phone interfaces
          const TouchCarouselHook = {
            mounted() {
              const SWIPE_THRESHOLD = 50;
              const VERTICAL_THRESHOLD = 50;
              const LONG_PRESS_DURATION = 500;
              const MIN_TAP_DURATION = 50;

              let touchStartX = 0, touchStartY = 0, touchStartTime = 0, longPressTimer = null;
              const el = this.el;

              const handleTouchStart = (e) => {
                if (!e.touches.length) return;
                touchStartX = e.touches[0].clientX;
                touchStartY = e.touches[0].clientY;
                touchStartTime = Date.now();
                longPressTimer = setTimeout(() => {
                  this.pushEvent("long-press", {});
                  longPressTimer = null;
                }, LONG_PRESS_DURATION);
              };

              const handleTouchEnd = (e) => {
                if (!e.changedTouches.length) return;
                if (longPressTimer) clearTimeout(longPressTimer);

                const touchEndX = e.changedTouches[0].clientX;
                const touchEndY = e.changedTouches[0].clientY;
                const touchDuration = Date.now() - touchStartTime;
                const deltaX = touchEndX - touchStartX;
                const deltaY = touchEndY - touchStartY;
                const absDeltaX = Math.abs(deltaX);
                const absDeltaY = Math.abs(deltaY);

                if (absDeltaX > SWIPE_THRESHOLD && absDeltaY < VERTICAL_THRESHOLD && touchDuration < LONG_PRESS_DURATION) {
                  this.pushEvent(deltaX > 0 ? "swipe-right" : "swipe-left", {});
                } else if (absDeltaY > SWIPE_THRESHOLD && absDeltaX < VERTICAL_THRESHOLD && touchDuration < LONG_PRESS_DURATION) {
                  this.pushEvent(deltaY > 0 ? "swipe-down" : "swipe-up", {});
                } else if (absDeltaX < 10 && absDeltaY < 10 && touchDuration >= MIN_TAP_DURATION && touchDuration < LONG_PRESS_DURATION) {
                  this.pushEvent("tap", {});
                }
              };

              const handleTouchCancel = () => {
                if (longPressTimer) clearTimeout(longPressTimer);
              };

              el.addEventListener("touchstart", handleTouchStart, false);
              el.addEventListener("touchend", handleTouchEnd, false);
              el.addEventListener("touchcancel", handleTouchCancel, false);

              this.cleanup = () => {
                el.removeEventListener("touchstart", handleTouchStart);
                el.removeEventListener("touchend", handleTouchEnd);
                el.removeEventListener("touchcancel", handleTouchCancel);
              };
            },
            destroyed() {
              if (this.cleanup) this.cleanup();
            }
          };

          let liveSocket = new LiveSocket("/live", Phoenix.Socket, {
            params: {_csrf_token: document.querySelector("meta[name='csrf-token']")?.content},
            hooks: {
              TouchCarousel: TouchCarouselHook
            }
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
        <link rel="stylesheet" href="/css/carousel.css" />
        <link rel="stylesheet" href="/css/phone_responsive.css" />
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0a0e27;
            color: #e0e0e0;
            min-height: 100vh;
            padding: 20px;
          }
          [phx-cloak] { display: none; }
        </style>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end
