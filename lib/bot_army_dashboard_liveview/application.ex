defmodule BotArmyDashboardLiveview.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("[Application] Starting Bot Army Dashboard...")
    port = Application.fetch_env!(:bot_army_dashboard_liveview, :port)
    Logger.info("[Application] Listening on port #{port}...")

    children = [
      {Phoenix.PubSub, name: BotArmyDashboardLiveview.PubSub},
      {BotArmyDashboardLiveview.NATSBridge, []},
      {Plug.Cowboy, scheme: :http, plug: BotArmyDashboardLiveview.Router, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: BotArmyDashboardLiveview.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("[Application] Supervisor started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("[Application] Supervisor failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# --- Multi-App Pattern (for bundling multiple surfaces in one container) ---
#
# If you're combining multiple LiveView surfaces into one OTP release (breaking Docker rules
# for consistency with bot packs), each surface would have its own Phoenix app + router.
#
# Example: Combining fitness_liveview + chore_liveview + notifications_liveview:
#
#   1. Create three separate app configs in mix.exs (one per surface, as separate libraries)
#   2. In docker-compose.yml, build ONE release with all three as deps
#   3. In this Application module, supervise multiple routers on different ports:
#
#       children = [
#         {Phoenix.PubSub, name: BotArmyDashboardLiveview.PubSub},
#         {Plug.Cowboy, [scheme: :http, plug: FitnessLiveview.Router, options: [port: 4001]]},
#         {Plug.Cowboy, [scheme: :http, plug: ChoreLiveview.Router, options: [port: 4002]]},
#         {Plug.Cowboy, [scheme: :http, plug: NotificationsLiveview.Router, options: [port: 4003]]},
#       ]
#
#   4. In docker-compose.yml, expose all three ports (4001, 4002, 4003)
#   5. Each surface has its own routes, LiveView modules, and assets
#   6. All share the same NATS connection (gnat), PubSub, and runtime environment
#
# This keeps deployment simple (one Docker image, one OTP release) while maintaining
# separation between surfaces (different routes, modules, ports). A reverse proxy can
# route /chore -> 4002, /fitness -> 4001, etc. if desired.
