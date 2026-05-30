defmodule SurfaceLiveviewTemplate.Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  # LiveView dashboard (replace with your routes)
  get "/dashboard" do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, layout_html("/dashboard", "Dashboard", dashboard_content()))
  end

  # Home
  get "/" do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, home_html())
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp layout_html(path, title, body) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>#{title}</title>
      <script defer phx-track-static src="/assets/app.js"></script>
      <link phx-track-static rel="stylesheet" href="/assets/app.css"/>
    </head>
    <body>
      <header style="padding:1rem;border-bottom:1px solid #eee;">
        <a href="/">Home</a> | <a href="/dashboard">Dashboard</a>
      </header>
      <main style="padding:1rem;">#{body}</main>
    </body>
    </html>
    """
  end

  defp home_html do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>Surface Template</title>
      <style>
        body { font-family: system-ui,sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
        h1 { margin-bottom: 0.5rem; }
        nav { margin-top: 1rem; }
        a { color: #2563eb; }
      </style>
    </head>
    <body>
      <h1>LiveView Surface Template</h1>
      <p>Copy this project, rename the app, then add your LiveViews and optional NATS bridge.</p>
      <nav>
        <a href="/dashboard">Dashboard (sample)</a>
      </nav>
    </body>
    </html>
    """
  end

  defp dashboard_content do
    """
    <div class="dashboard">
      <h1>Dashboard</h1>
      <p>Replace this with a LiveView that mounts here. Add <code>/assets/app.js</code> (LiveView client) and mount your LiveView in the router with a proper socket.</p>
      <p>See README for: renaming the app, adding LiveViews, and optional NATS bridge.</p>
    </div>
    """
  end
end
