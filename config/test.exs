import Config

# Tests are hermetic: no listener, no broker.
#
# Before this file existed, `mix test` in this surface booted the endpoint on the
# LIVE dashboard port (30011) and connected to the LIVE broker (4222), subscribing
# to `events.gtd.decomposition.>` and `system.health.>`. On a machine where the
# deployed surface was already running that surfaced as `eaddrinuse`; where it was
# not, the test run would take the production port and read the live system.
#
# 42991 is the fleet's hermetic test port (monorepo convention).
config :bot_army_dashboard_liveview, :port, 42991

config :bot_army_dashboard_liveview, BotArmyDashboardLiveview.Endpoint,
  url: [host: "localhost", port: 42991],
  http: [ip: {127, 0, 0, 1}, port: 42991],
  server: false,
  check_origin: false,
  secret_key_base: "DASHBOARD_SECRET_KEY_BASE_MIN_64_CHARS_REQUIRED_FOR_LIVE_VIEW_ENCRYPTION_",
  pubsub_server: BotArmyDashboardLiveview.PubSub,
  live_view: [signing_salt: "abcdefghijklmnopqrst"]

# The NATS bridge is a network dependency. Tests drive the payload builders and
# the LiveView in-process, so the bridge stays down and a panel read deterministically
# exercises the "nothing answered" path rather than whatever this machine publishes.
config :bot_army_dashboard_liveview, :start_nats_bridge, false

# Belt and braces: if the bridge is ever started in a test run, it must still not
# join the live broker. 42991 is the hermetic test port used everywhere else here.
config :bot_army_dashboard_liveview, :nats_port, "42991"
