defmodule BotArmyDashboardLiveview.RoutesMountTest do
  @moduledoc """
  Every route has to survive being opened.

  This is a regression pin, not a smoke test. On the deployed dashboard twelve
  of these routes answered 500 to a browser, for two reasons that both lived in
  the views:

    * each one wrote `{:ok, _} = PubSub.subscribe(...)`, and a `Phoenix.PubSub`
      subscription returns `:ok` — so `mount/3` raised a `MatchError` before it
      rendered anything;
    * a screen that asked the broker a question during `mount/3` let the
      connection's `:noproc` *exit* out of the view — an exit is not an
      exception, so the `try/rescue` around it was decorative, and the screen
      500'd instead of saying it could not reach the bot.

  The test environment has no broker, so these mounts are all the "broker is
  down" case: they must render anyway.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint BotArmyDashboardLiveview.Endpoint

  @routes ~w(
    / household-hud
    fitness-handheld gtd-handheld system-health-handheld energy-mood-handheld timer-handheld
    habit-anchors quest-status reflection
    timer-phone habits-phone quest-phone reflect-phone energy-mood-phone
    fitness-phone system-health-phone gtd-phone session-history-phone
  )

  for route <- @routes do
    test "#{route} opens" do
      assert {:ok, _view, html} = live(build_conn(), unquote(route))
      assert html =~ "<html"
    end
  end
end
