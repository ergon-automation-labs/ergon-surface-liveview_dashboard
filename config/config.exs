import Config

# HTTP port is set at setup (non-conflicting). Override with SURFACE_LIVEVIEW_PORT env at runtime.
port =
  case System.get_env("SURFACE_LIVEVIEW_PORT") do
    nil -> 4000
    p when is_binary(p) -> String.to_integer(p)
    _ -> 4000
  end

config :surface_liveview_template, :port, port

# NATS connection (optional, for subscribing to other bots' topics)
# When running in Docker, NATS_HOST and NATS_PORT point to the external Bot Army NATS
# On the same network: NATS_HOST=nats (Docker Compose service name) or host.docker.internal:4222
nats_port =
  case System.get_env("NATS_PORT", "4222") do
    p when is_binary(p) -> String.to_integer(p)
    _ -> 4222
  end

config :gnat,
  nats_host: System.get_env("NATS_HOST", "localhost"),
  nats_port: nats_port,
  nats_servers: [
    %{
      host: System.get_env("NATS_HOST", "localhost"),
      port: nats_port
    }
  ]
