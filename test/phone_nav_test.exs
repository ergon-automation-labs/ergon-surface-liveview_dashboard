defmodule BotArmyDashboardLiveview.PhoneNavTest do
  @moduledoc """
  The bar is the list of screens that still exist, and this module is where that is pinned.

  Yearning, Body, Devotion, Habits and Anchors were navigation entries, and they were the
  right thing to be one: they were hers to say rather than corners of the house's read, so
  each was its own page instead of a card under the timer, where a tap on a point was one
  touch away from starting a countdown. What was wrong with them was not the shape of the
  entry — it was the write behind it. The bot files a body reading, a yearning, a hygiene
  event and the three cage writes under `:slave` **without being told**, so the identity is
  not on the wire at all and the page that sent it was the only thing on this open surface
  that knew whose hand was on the screen. Her panel makes all five reports behind her own
  link now (§44), and each path is retired into her **How I am** group.

  So this module pins the lists: what the bar carries, what the long-press menu carries, and
  what neither offers any more. A menu that still listed a retired screen would offer a
  screen that is not there — the same fog the retirement was for, drawn a second time.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.PhoneNavModal

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  # The five paths that used to be screens here, and are her panel's now.
  @retired_reports [
    "/yearning-phone",
    "/body-phone",
    "/devotion-phone",
    "/habits-phone",
    "/habit-anchors"
  ]

  # The GTD screen and its handheld left for the smaller half of that reason: the write did
  # carry an identity — the screen sent `slave` through the bridge — but the list was still
  # drawn on an open surface, and a task list is an answer to *what should I do next*. Both
  # paths answer with a move into her panel's Tasks group.
  @retired_gtd ["/gtd-phone", "/gtd-handheld"]

  # The reflect pair left for the reports' reason without the smaller half: both screens
  # wrote her own words into her journal and put **no identity in the write at all** — a
  # reflection is text, a prompt and a `dedupe_key`, and the store has no notion of a
  # person — so the page that sent it answered *whose words are these* by itself. Both paths
  # answer with a move into her panel's Reflect group (§47).
  @retired_reflect ["/reflection", "/reflect-phone"]

  # The energy pair left for a reason none of the others had: their check-in was a
  # `Gnat.pub/3` to `events.context.updated` — a publish with no reply — so "Context
  # saved" was drawn over a byte that only had to reach the socket, and with no subscriber
  # it reached nobody. The reading is about her rather than a decision about her, so there
  # is nothing to gate; her panel's Energy group asks `wife_care.energy.record` and reads
  # the reading back (§49). Both paths answer with a move into that group.
  @retired_energy ["/energy-mood-phone", "/energy-mood-handheld"]

  # The timer and the quest are the pair this map's shape argued against, and the last two to
  # leave. They are not the reports' defect: the timer's write carried `slave` and the quest's
  # was a read, so no journal was written from an open surface. The timer screen had the
  # *energy* defect instead — the session was filed with a publish nobody had to read and the
  # running session's id lived in the page, so a reload took both — and the quest screen had
  # the *GTD* defect, drawing a progress bar and a streak over the box her tasks live in. Her
  # panel's Timers group holds the session in the bridge (§51) and its Quest group counts the
  # rows it drew (§50). All four paths answer with a move into those two groups.
  @retired_timer ["/timer-phone", "/timer-handheld"]
  @retired_quest ["/quest-phone", "/quest-status"]
  @retired_hers @retired_reports ++
                  @retired_gtd ++
                  @retired_reflect ++ @retired_energy ++ @retired_timer ++ @retired_quest

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())
    Application.put_env(@app, :broker_stub_reply, Jason.encode!(%{"ok" => true, "data" => %{}}))

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  test "the bar carries the screens that are here, and no report screen" do
    handhelds = PhoneNav.all_handhelds()

    # The house is first on purpose — it is the screen she lives on — and the window is
    # the one screen here she is *in* rather than reading about herself from.
    assert {"/household-hud", "🏠", "House"} in handhelds
    assert {"/party-phone", "🎭", "Window"} in handhelds

    # The five report screens are gone, and gone from the lookup too, so nothing can
    # render a bar entry for one by naming it. So is GTD — it was an entry until the box
    # it drew moved to her panel behind her own link — and so is Reflect, which was an
    # entry until the journal it wrote moved to the panel, where the hand that wrote it is
    # known (§45, §47). And so is Energy, which was an entry until the reading came from the
    # bot's reply rather than from a publish nobody had to answer (§49).
    for route <- @retired_hers do
      refute Enum.any?(handhelds, fn {r, _emoji, _label} -> r == route end)
      assert PhoneNav.get_emoji(route) == nil
    end

    # The wardrobe and the shelf were never entries for reasons of their own: a wear is a
    # write whose meaning is whose voice it was, and a phrase in the air is a moment rather
    # than a place a bar on every page should offer.
    refute {"/wardrobe-phone", "👗", "Wardrobe"} in handhelds
    assert PhoneNav.get_emoji("/wardrobe-phone") == nil
    refute {"/hypnosis-phone", "🌀", "Hypnosis"} in handhelds
    assert PhoneNav.get_emoji("/hypnosis-phone") == nil

    # One option each, not one page with modes.
    assert length(handhelds) == 4
    routes = Enum.map(handhelds, &elem(&1, 0))
    assert Enum.uniq(routes) == routes
  end

  test "the long-press menu lists no screen that is retired" do
    handhelds = PhoneNavModal.all_handhelds()

    # The shelf's page was reachable from this menu and nowhere else. It is a redirect to
    # the window now, so a menu that still listed it would offer a screen that is not
    # there — and the shelf would have two homes again, which is the thing retiring it
    # settled. The five report screens, the GTD pair and the reflect pair are the same
    # case: their paths answer with a move into her panel, so listing one here would offer a
    # screen this surface does not have.
    for retired <-
          @retired_hers ++ ["/hypnosis-phone", "/wardrobe-phone"] do
      refute Enum.any?(handhelds, fn {route, _emoji, _label, _hint} -> route == retired end)
    end

    # And the menu is where the shelf is announced instead: it is drawn inside the window,
    # so the window's own line has to say so or the shelf is nowhere she would look.
    assert {_route, "🎭", "Window", hint} =
             Enum.find(handhelds, fn {route, _emoji, _label, _hint} ->
               route == "/party-phone"
             end)

    assert hint =~ "shelf"

    routes = Enum.map(handhelds, &elem(&1, 0))
    assert Enum.uniq(routes) == routes
  end

  # The placement rule that outlived the screens: a ladder used to sit under the timer, one
  # tap from starting a countdown, and it is on her panel now. The timer screen itself is
  # retired (§51), so the half of the rule that still has a subject is the screens that are
  # left: none of them may carry a ladder or one of the five report writes, whatever is
  # drawn on it.
  test "no screen that is left carries a ladder or a report write" do
    html = render(page("/fitness-phone", "Fitness"))

    refute html =~ "record_yearning"
    refute html =~ "record_body_reading"
    refute html =~ "record_goddess_proximity"
    refute html =~ "record_hygiene_event"
    refute html =~ "tap a point to log it"
  end

  # A settled page: the read has landed by the time `text` is on screen.
  defp page(route, text) do
    {:ok, view, _html} = live(build_conn(), route)
    await(view, text)
    view
  end

  # The read is a hand-rolled task, not `start_async`, so wait for the text
  # rather than for a frame — the same bounded poll the read-path tests use.
  defp await(view, text), do: await(view, text, 50)

  defp await(_view, text, 0), do: flunk("the screen never showed #{inspect(text)}")

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end
end
