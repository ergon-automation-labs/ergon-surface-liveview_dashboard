defmodule BotArmyDashboardLiveview.Router do
  use Plug.Router
  require Logger

  plug(:log_request)
  plug(:match)
  plug(:dispatch)

  get "/" do
    Logger.info("[Router] GET /")

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>Bot Army Dashboard</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          background: #0a0e27;
          color: #e0e0e0;
          min-height: 100vh;
          padding: 20px;
        }
        .header {
          max-width: 1400px;
          margin: 0 auto 30px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          border-bottom: 1px solid #1e2749;
          padding-bottom: 20px;
        }
        .title {
          font-size: 28px;
          font-weight: bold;
          color: #00ff88;
        }
        .status {
          padding: 8px 16px;
          border-radius: 6px;
          background: #3a1a1a;
          color: #ff4444;
        }
        .container {
          max-width: 1400px;
          margin: 0 auto;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 20px;
          margin-bottom: 30px;
        }
        .stat-card {
          background: #0f1535;
          border: 1px solid #1e2749;
          padding: 20px;
          border-radius: 8px;
          text-align: center;
        }
        .stat-label {
          font-size: 12px;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 10px;
        }
        .stat-value {
          font-size: 32px;
          font-weight: bold;
          color: #00ff88;
        }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="title">⚙️ Bot Army Dashboard</div>
        <div class="status">🔴 NATS Initializing...</div>
      </div>

      <div class="container">
        <div class="grid">
          <div class="stat-card">
            <div class="stat-label">Tasks Today</div>
            <div class="stat-value">—</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">Completed</div>
            <div class="stat-value">—</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">In Progress</div>
            <div class="stat-value">—</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">Blocked</div>
            <div class="stat-value">—</div>
          </div>
        </div>
        <p style="text-align: center; margin: 20px 0;">Dashboard initializing. Open browser console for NATS bridge status.</p>
      </div>
    </body>
    </html>
    """

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, html)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp log_request(conn, _opts) do
    Logger.info("[Router] #{conn.method} #{conn.request_path}")
    conn
  end
end
