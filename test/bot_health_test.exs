defmodule BotArmyDashboardLiveview.BotHealthTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyDashboardLiveview.BotHealth

  defp heartbeat_ago(seconds) do
    DateTime.utc_now()
    |> DateTime.add(-seconds, :second)
    |> DateTime.to_iso8601()
  end

  describe "derive_status/1" do
    test "a bot that beat a moment ago is healthy" do
      assert BotHealth.derive_status(%{"last_heartbeat" => heartbeat_ago(5)}) == :healthy
    end

    test "a bot between beats is idle" do
      assert BotHealth.derive_status(%{"last_heartbeat" => heartbeat_ago(120)}) == :idle
    end

    test "a bot that has not beaten in a long time is offline" do
      assert BotHealth.derive_status(%{"last_heartbeat" => heartbeat_ago(900)}) == :offline
    end

    test "a bot that has never reported a heartbeat is offline" do
      assert BotHealth.derive_status(%{}) == :offline
      assert BotHealth.derive_status(%{"last_heartbeat" => nil}) == :offline
    end

    test "a heartbeat that is not a timestamp is offline" do
      assert BotHealth.derive_status(%{"last_heartbeat" => "yesterday"}) == :offline
      assert BotHealth.derive_status(%{"last_heartbeat" => 999.0}) == :offline
    end
  end

  describe "status_word/1 and status_emoji/1" do
    test "the words are the ones the phone's badge classes accept" do
      assert BotHealth.status_word(:healthy) == "healthy"
      assert BotHealth.status_word(:idle) == "degraded"
      assert BotHealth.status_word(:offline) == "unhealthy"
      assert BotHealth.status_word(:something_else) == "unknown"
    end

    test "the two screens show the same glyph for the same fact" do
      assert BotHealth.status_emoji(:healthy) == "✓"
      assert BotHealth.status_emoji(:idle) == "⏸"
      assert BotHealth.status_emoji(:offline) == "✗"
      assert BotHealth.status_emoji(:something_else) == "?"
    end
  end

  describe "format_heartbeat/1" do
    test "reads as time passing, not as a timestamp" do
      assert BotHealth.format_heartbeat(heartbeat_ago(5)) == "now"
      assert BotHealth.format_heartbeat(heartbeat_ago(300)) == "5m ago"
      assert BotHealth.format_heartbeat(heartbeat_ago(7200)) == "2h ago"
      assert BotHealth.format_heartbeat(heartbeat_ago(172_800)) == "2d ago"
    end

    test "says when there is nothing to read" do
      assert BotHealth.format_heartbeat(nil) == "No heartbeat"
      assert BotHealth.format_heartbeat("yesterday") == "unknown"
      assert BotHealth.format_heartbeat(999.0) == "unknown"
    end
  end
end
