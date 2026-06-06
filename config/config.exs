import Config

# HTTP port is set at setup (non-conflicting). Override with BOT_ARMY_DASHBOARD_LIVEVIEW_PORT env at runtime.
port =
  case System.get_env("BOT_ARMY_DASHBOARD_LIVEVIEW_PORT") do
    nil -> 30011
    p when is_binary(p) -> String.to_integer(p)
    _ -> 30011
  end

config :bot_army_dashboard_liveview, :port, port

config :bot_army_dashboard_liveview, BotArmyDashboardLiveview.Endpoint,
  url: [host: "localhost", port: port],
  http: [ip: {0, 0, 0, 0}, port: port],
  check_origin: false,
  pubsub_server: BotArmyDashboardLiveview.PubSub,
  live_view: [signing_salt: "abcdefghijklmnopqrst"]

# NATS connection (optional, for subscribing to other bots' topics)
# When running in Docker, NATS_HOST and NATS_PORT point to the external Bot Army NATS
# On the same network: NATS_HOST=nats (Docker Compose service name) or host.docker.internal:4222
