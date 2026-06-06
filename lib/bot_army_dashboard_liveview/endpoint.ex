defmodule BotArmyDashboardLiveview.Endpoint do
  use Phoenix.Endpoint, otp_app: :bot_army_dashboard_liveview

  @session_options [
    store: :cookie,
    key: "_dashboard_key",
    signing_salt: "dashboard_salt_123"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :bot_army_dashboard_liveview,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)
  )

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(BotArmyDashboardLiveview.Router)
end
