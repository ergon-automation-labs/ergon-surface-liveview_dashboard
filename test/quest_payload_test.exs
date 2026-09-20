defmodule BotArmyDashboardLiveview.QuestPayloadTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyDashboardLiveview.QuestPayload

  @quest %{"id" => "p1", "title" => "Fix email pipeline", "tasks" => []}

  describe "parse/1" do
    test "unwraps the bridge envelope" do
      body = Jason.encode!(%{"ok" => true, "quest" => @quest})

      assert QuestPayload.parse(body) == @quest
    end

    test "accepts an already-decoded envelope" do
      assert QuestPayload.parse(%{"ok" => true, "quest" => @quest}) == @quest
    end

    test "a null quest is nil, so the view renders its empty state" do
      assert QuestPayload.parse(Jason.encode!(%{"ok" => true, "quest" => nil})) == nil
      assert QuestPayload.parse(%{"ok" => true, "quest" => nil}) == nil
    end

    test "a failure is nil rather than a truthy wrapper" do
      # The regression this module exists for: treating the envelope itself as
      # the quest rendered a card with a nil title and "0 of 0 tasks complete"
      # instead of the empty state.
      body = Jason.encode!(%{"ok" => false, "quest" => nil, "error" => "upstream_error"})

      refute is_map(QuestPayload.parse(body))
      assert QuestPayload.parse(body) == nil
    end

    test "tolerates malformed bodies without raising" do
      assert QuestPayload.parse("not json") == nil
      assert QuestPayload.parse("") == nil
      assert QuestPayload.parse(nil) == nil
      assert QuestPayload.parse(%{"unexpected" => "shape"}) == nil
      assert QuestPayload.parse(%{"ok" => true, "quest" => "not a map"}) == nil
    end
  end
end
