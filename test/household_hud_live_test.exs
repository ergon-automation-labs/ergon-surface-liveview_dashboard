defmodule BotArmyDashboardLiveview.HouseholdHUDLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  # The NATS bridge is off in test (config/test.exs), so every read here takes the
  # "nothing answered" path. That is the state the HUD must never lie in.
  @endpoint BotArmyDashboardLiveview.Endpoint

  # The screen before the bot has answered: it must say it is asking, and offer
  # nothing that implies a reading.
  test "is honest while it is still asking" do
    {:ok, _view, html} = live(build_conn(), "/household-hud")

    assert html =~ "Household HUD"
    assert html =~ "asking the house…"
  end

  test "says nothing answered, and offers a way to try again" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "No answer from the wife care bot yet."
    assert html =~ "ask again"
    refute html =~ "asking the house…"
  end

  test "shows what the keys do, on every screen" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "refresh"
    assert html =~ "control panel"
  end

  test "never fabricates the doc's example numbers" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    refute html =~ "65%"
    refute html =~ "MAID LEVEL 65"
  end

  test "the exit is on the screen even when nothing else is" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Exit — always available"
    assert html =~ "Stop everything"
  end

  test "carries the active state, its reason, and its energy" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Active state"
    assert html =~ "Neutral (normal operations)"
    assert html =~ "Energy: not set"
    assert html =~ "Nothing is shifting it today."
  end

  test "names the states it cannot derive yet instead of omitting them" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Not derived yet"
    assert html =~ "Reward Pulse State"
    assert html =~ "Restoration State"
    assert html =~ "diaper"
  end

  test "the background class follows the state and the pet layer" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "state-neutral"
    # Nothing answered, so the pet layer is not known to be on: the safe default
    # is the crisp, bloom-free rendering rather than an assumed warmth.
    assert html =~ ~s(class="hud state-neutral crisp")
    refute html =~ "state-neutral crisp bloom"
  end

  test "refreshing asks again and does not take the screen down" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    render_async(view)

    html = render_click(view, "refresh")

    assert html =~ "Household HUD"
    assert render_async(view) =~ "No answer from the wife care bot yet."
  end
end
