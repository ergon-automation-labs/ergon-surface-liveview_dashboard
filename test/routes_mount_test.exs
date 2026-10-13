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
    fitness-handheld system-health-handheld
    fitness-phone system-health-phone session-history-phone
    party-phone
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

  # The wardrobe's screen went to a different origin, which is the case this map cannot
  # answer with a relative path: `/` here is this dashboard, and no screen on it holds a
  # closet. The address is built from the host the bookmark arrived on, and it is a
  # different *port* — so a phone that opened `http://<phone-host>:30011/wardrobe-phone`
  # has to be sent to `<phone-host>:30014`, never to localhost, which would be the phone.
  test "a retired screen that went to her own panel is sent there, on the host that asked" do
    conn = get(build_conn(), "/wardrobe-phone")
    assert conn.status == 302

    assert Plug.Conn.get_resp_header(conn, "location") == [
             "http://www.example.com:30014/?tab=closet"
           ]

    assert get(build_conn(), "/wardrobe-phone/").status == 302

    # And there is no relative form of it to fall back to, which is precisely what the
    # map is shaped to prevent.
    assert BotArmyDashboardLiveview.Retired.moved_to("/wardrobe-phone") == :her_closet
  end

  # The five report screens are the same case as the closet, and the reason is worth
  # restating where the behaviour is pinned: the bot files each of these writes under
  # `:slave` without being told, so the page that sent the write was the only thing that
  # knew whose hand was on the screen — and this surface is open. They all land on the one
  # group that holds her reports, because the distinction worth keeping is *where her own
  # numbers live*, and one group she can recognise is a better answer to a bookmark than
  # five addresses that each have to be right.
  test "the five retired report screens all hand their bookmark to her panel" do
    for path <- ~w(/yearning-phone /body-phone /devotion-phone /habits-phone /habit-anchors) do
      conn = get(build_conn(), path)
      assert conn.status == 302, "#{path} did not answer with a move"

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "http://www.example.com:30014/?tab=how_i_am"
             ]

      # A trailing slash is the same path, as it is for every other retired path.
      assert get(build_conn(), path <> "/").status == 302

      # And it is the *kind*, not a URL: an address computed with no request behind it
      # would be an address for the wrong machine.
      assert BotArmyDashboardLiveview.Retired.moved_to(path) == :her_reports
    end

    # One destination for all five, which is the decision this test is really about.
    assert BotArmyDashboardLiveview.HerPanel.how_i_am_url_from_host("air") ==
             "http://air:30014/?tab=how_i_am"
  end

  # The GTD screen is the same case with a name on the write: the identity was on the wire
  # (`slave`, through the bridge), so nothing was filed under the wrong hand — but the list
  # was still drawn on an open surface, and a task list is an answer to *what should I do
  # next*. Both of its paths go to the one group that holds that box, and the handheld twin
  # goes with the phone because the screen it drew is gone, not because anyone linked to it.
  test "the retired GTD screen and its handheld hand their bookmarks to her panel's tasks" do
    for path <- ~w(/gtd-phone /gtd-handheld) do
      conn = get(build_conn(), path)
      assert conn.status == 302, "#{path} did not answer with a move"

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "http://www.example.com:30014/?tab=tasks"
             ]

      assert get(build_conn(), path <> "/").status == 302
      assert BotArmyDashboardLiveview.Retired.moved_to(path) == :her_tasks
    end

    assert BotArmyDashboardLiveview.HerPanel.tasks_url_from_host("air") ==
             "http://air:30014/?tab=tasks"
  end

  # The reflect pair is the report screens' defect exactly, and the worst of the set: both
  # wrote her own words into her journal from a surface anyone on the network can reach,
  # and the write carried **no identity at all** — a reflection is text, a prompt and a
  # `dedupe_key`, and the store has no notion of a person, so the page that sent the write
  # was the whole answer to *whose words are these*. Her panel holds that write under her own
  # login and draws the same question, box and journal (§47). Both paths go to that group,
  # and they go as one destination: the desk screen and the phone screen were two doors onto
  # one box.
  test "the retired reflect screens hand their bookmarks to her panel's reflect group" do
    for path <- ~w(/reflection /reflect-phone) do
      conn = get(build_conn(), path)
      assert conn.status == 302, "#{path} did not answer with a move"

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "http://www.example.com:30014/?tab=reflect"
             ]

      assert get(build_conn(), path <> "/").status == 302
      assert BotArmyDashboardLiveview.Retired.moved_to(path) == :her_reflect
    end

    assert BotArmyDashboardLiveview.HerPanel.reflect_url_from_host("air") ==
             "http://air:30014/?tab=reflect"
  end

  # The energy pair is the quietest retire of the set, and the only one whose defect was not
  # about *who* could write: a check-in was sent by `Gnat.pub/3` to `events.context.updated`,
  # a publish with no reply, so "Context saved" was drawn over a byte that only had to reach
  # the socket — and with no subscriber it reached nobody. The reading is about her rather
  # than a decision about her, so the fix is not a gate: her panel's Energy group asks
  # `wife_care.energy.record` and reads the reading back (§49). Both paths go there, the
  # handheld twin with the phone because the screen it drew is gone rather than because
  # anyone linked to it.
  test "the retired energy screens hand their bookmarks to her panel's energy group" do
    for path <- ~w(/energy-mood-phone /energy-mood-handheld) do
      conn = get(build_conn(), path)
      assert conn.status == 302, "#{path} did not answer with a move"

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "http://www.example.com:30014/?tab=energy"
             ]

      assert get(build_conn(), path <> "/").status == 302
      assert BotArmyDashboardLiveview.Retired.moved_to(path) == :her_energy
    end

    assert BotArmyDashboardLiveview.HerPanel.energy_url_from_host("air") ==
             "http://air:30014/?tab=energy"
  end

  # The timer and the quest are the last two retires, and they are worth pinning apart from
  # the rest because they are **not** the reports' defect. The timer's write carried `slave`
  # and the quest's was a read, so nothing was filed under the wrong hand. The timer screen
  # instead had the energy screen's defect — a session filed by a publish nobody had to read,
  # with its id kept in the page, where a reload lost it — and her panel's Timers group holds
  # the session in the bridge (§51). The quest screen had the GTD screen's defect and the worst
  # half of it: a progress bar and a streak drawn over the box her tasks live in, where her
  # panel draws the open steps and counts the rows it drew (§50). Both pairs hand their
  # bookmarks to the group that holds what the screen was about.
  test "the retired timer and quest screens hand their bookmarks to her panel's groups" do
    for {paths, kind, tab} <- [
          {~w(/timer-phone /timer-handheld), :her_timer, "timer"},
          {~w(/quest-phone /quest-status), :her_quest, "quest"}
        ] do
      for one <- paths do
        conn = get(build_conn(), one)
        assert conn.status == 302, "#{one} did not answer with a move"

        assert Plug.Conn.get_resp_header(conn, "location") == [
                 "http://www.example.com:30014/?tab=#{tab}"
               ]

        assert get(build_conn(), one <> "/").status == 302
        assert BotArmyDashboardLiveview.Retired.moved_to(one) == kind
      end
    end

    assert BotArmyDashboardLiveview.HerPanel.timer_url_from_host("air") ==
             "http://air:30014/?tab=timer"

    assert BotArmyDashboardLiveview.HerPanel.quest_url_from_host("air") ==
             "http://air:30014/?tab=quest"
  end

  # The plug only answers for the paths it knows. Everything else is a 404, which is not a
  # screen either — but it is not a lie about one.
  test "a path the retirement map does not know is not answered with a move" do
    assert BotArmyDashboardLiveview.Retired.moved_to("/not-a-screen") == nil

    conn = get(build_conn(), "/not-a-screen")
    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "location") == []
  end
end
