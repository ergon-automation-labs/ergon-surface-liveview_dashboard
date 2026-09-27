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
    / household-hud yearning-phone body-phone wardrobe-phone devotion-phone
    fitness-handheld gtd-handheld system-health-handheld energy-mood-handheld timer-handheld
    habit-anchors quest-status reflection
    timer-phone habits-phone quest-phone reflect-phone party-phone energy-mood-phone
    fitness-phone system-health-phone gtd-phone session-history-phone
  )

  for route <- @routes do
    test "#{route} opens" do
      assert {:ok, _view, html} = live(build_conn(), unquote(route))
      assert html =~ "<html"
    end
  end

  # The shelf's page is retired, and a retired path still has to answer. A 404 would turn
  # "the shelf is in the window now" into "you typed it wrong" — on a phone, from a home
  # screen icon that was added when the page was real.
  test "a retired screen's path sends the bookmark to where the screen went" do
    conn = get(build_conn(), "/hypnosis-phone")
    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/party-phone?moved=shelf"]

    # A trailing slash is the same path, and a bookmark may carry one.
    assert get(build_conn(), "/hypnosis-phone/").status == 302
  end

  # The plug only answers for the paths it knows. Everything else is a 404, which is not a
  # screen either — but it is not a lie about one.
  test "a path the retirement map does not know is not answered with a move" do
    assert BotArmyDashboardLiveview.Retired.moved_to("/quest-status") == nil

    conn = get(build_conn(), "/not-a-screen")
    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "location") == []
  end
end
