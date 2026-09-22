defmodule BotArmyDashboardLiveview.HermeticityTest do
  use ExUnit.Case, async: true

  alias BotArmyDashboardLiveview.NATSBridge

  # These guard the bug that made `mix test` on this surface unsafe: the test run
  # booted the endpoint on the LIVE port (30011) and joined the LIVE broker (4222).
  # On a machine running the deployed surface that was `eaddrinuse`; on one that was
  # not, the tests took the production port and read the live system. See
  # config/test.exs.

  @live_port 30011
  @test_port 42_991

  test "tests do not use the live dashboard port" do
    refute Application.get_env(:bot_army_dashboard_liveview, :port) == @live_port
    assert Application.get_env(:bot_army_dashboard_liveview, :port) == @test_port
  end

  test "tests do not open a listener at all" do
    endpoint =
      Application.get_env(:bot_army_dashboard_liveview, BotArmyDashboardLiveview.Endpoint)

    assert endpoint[:server] == false
    assert endpoint[:http][:port] == @test_port
    refute endpoint[:http][:port] == @live_port
  end

  test "tests do not join the broker" do
    assert Application.get_env(:bot_army_dashboard_liveview, :start_nats_bridge) == false
    # `NATSBridge` starts `Gnat` under this name; if it is missing, no test can
    # accidentally request a live subject and get a live answer.
    refute Process.whereis(:nats_connection)
  end

  test "the broker a test would join is not the production port" do
    # The environment wins in production, but the test pin must beat an ambient
    # `NATS_PORT=4222` — otherwise a stray shell export would put a test run on the
    # live broker the moment the bridge was started.
    assert NATSBridge.configured_port() == "42991"
    refute String.to_integer(NATSBridge.configured_port()) == 4222
  end
end
