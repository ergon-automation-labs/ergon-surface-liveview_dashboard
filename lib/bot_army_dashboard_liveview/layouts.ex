defmodule BotArmyDashboardLiveview.Layouts do
  use Phoenix.Component

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
          let liveSocket = new LiveSocket("/live", Phoenix.Socket, {
            params: {_csrf_token: document.querySelector("meta[name='csrf-token']")?.content}
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
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
