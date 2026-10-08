defmodule BotArmyDashboardLiveview.CageEscapesTest do
  # The escape card is on the same screen as the body card and is deliberately not
  # one of its channels, so these tests are about two things at once: that the
  # counts shown are the bot's, and that nothing here ever turns an event into a
  # point on the house scale.
  #
  # Same harness as `body_phone_test`: the transport is a stub and the app env is
  # process-wide, so this module is not async. A map reply answers each subject
  # separately, which is what lets the write and the re-read that follows it say
  # different things.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview
  @escape_subject "wife_care.control_panel.record_cage_escape"
  @undo_subject "wife_care.control_panel.undo_cage_escape"
  @flip_subject "wife_care.control_panel.set_cage_escape_period"

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  # ── the wire, cut to what this card reads ───────────────────────────────────

  defp escape_event(id, at, period, note \\ nil) do
    %{"id" => id, "at" => at, "period" => period, "source" => "reported", "note" => note}
  end

  defp at(seconds_ago) do
    DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.to_iso8601()
  end

  # A block as the bot sends it. `total`, `night` and `day` are passed in rather
  # than counted from `events`, because the bot counts over its whole log while
  # `events` is only the few newest — a surface that "helpfully" recounted would
  # disagree with the bot the moment the log outgrows the window.
  defp block(events, opts \\ []) do
    %{
      "total" => Keyword.get(opts, :total, length(events)),
      "night" => Keyword.get(opts, :night, Enum.count(events, &(&1["period"] == "night"))),
      "day" => Keyword.get(opts, :day, Enum.count(events, &(&1["period"] == "day"))),
      "last_at" => List.last(events)["at"],
      "events" => Enum.reverse(events),
      "night_window" => Keyword.get(opts, :window, %{"from" => 22, "until" => 8})
    }
  end

  defp panel_reply(escapes, opts \\ []) do
    data =
      %{"body" => %{"kinds" => [], "scale" => [], "latest" => %{}, "any_reported?" => false}}
      |> Map.merge(Keyword.get(opts, :extra, %{}))
      |> then(fn data ->
        if escapes == :absent, do: data, else: Map.put(data, "cage_escapes", escapes)
      end)

    Jason.encode!(%{"ok" => true, "data" => data})
  end

  defp ok_reply(escapes) do
    Jason.encode!(%{"ok" => true, "data" => %{"cage_escapes" => escapes}})
  end

  defp stub_reply(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  defp page(escapes, opts \\ []) do
    stub_reply(panel_reply(escapes, opts))
    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")
    view
  end

  # `render_async/1` only tracks `start_async` PIDs and this screen re-reads in a
  # hand-rolled task, so wait for the text instead of for a frame.
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

  defp last_escape_reply do
    [
      escape_event(1, at(90_000), "night"),
      escape_event(2, at(7_200), "day"),
      escape_event(3, at(3_600), "night")
    ]
  end

  # ── the card ────────────────────────────────────────────────────────────────

  test "the card is on the body screen, and is not one of its channels" do
    html = render(page(block(last_escape_reply())))

    assert html =~ "The cage — escapes"
    # A channel is a level with the six points under it. An escape has no point to
    # be, so the card that counts them must not offer one.
    refute html =~ ~s(phx-value-kind="cage_escapes")
    assert html =~ "A count is not a reading"
  end

  test "the card shows the total and both sides of the night" do
    escapes = block(last_escape_reply())
    html = render(page(escapes))

    assert html =~ ~s(style="font-size:30px; line-height:1;">3</span>)
    assert html =~ "2 at night · 1 during the day"
    refute html =~ "days since"
  end

  test "the counts are the bot's, not a recount of the events it sent" do
    # The bot counts over its whole log; `events` is only the newest few. Here they
    # deliberately disagree, and the card must show the bot's number — a screen
    # that counted the rows it was sent would silently report a different total.
    escapes = block(last_escape_reply(), total: 41, night: 30, day: 11)
    html = render(page(escapes))

    assert html =~ "30 at night · 11 during the day"
    refute html =~ "2 at night · 1 during the day"
  end

  test "a panel that has not answered says so rather than drawing a confident zero" do
    html = render(page(:absent))

    assert html =~ "the panel has not reported the escape log yet"
    # "nothing recorded" and "nothing happened" are different claims.
    refute html =~ "at night ·"
  end

  test "the card says what night meant, in the bot's own window" do
    html = render(page(block([], window: %{"from" => 21, "until" => 9})))

    assert html =~ "night means 21:00–09:00"
  end

  test "the most recent escape is shown relatively, never as a clock hour" do
    escapes = block([escape_event(1, at(3 * 3_600), "night")])
    html = render(page(escapes))

    # This surface has no timezone database either, so a UTC hour drawn as local
    # would be hours out and look entirely plausible.
    assert html =~ "most recent — 3h ago"
    assert html =~ "it was day"
  end

  test "an escape the bot sent without an id is dropped, not drawn with a dead button" do
    no_id = %{"at" => at(60), "period" => "night", "source" => "reported"}

    escapes =
      block([], total: 1, night: 1, day: 0)
      |> Map.put("events", [no_id])

    html = render(page(escapes))

    # The count is the bot's and is right. The row is not drawn, because correcting
    # an event names it and this one has no name to send.
    assert html =~ "1 at night · 0 during the day"
    refute html =~ "most recent"
    refute html =~ ~s(phx-click="flip_cage_escape")
  end

  # ── the presses ─────────────────────────────────────────────────────────────

  test "the + counts one escape and lets the clock decide which side of the night" do
    escapes = block(last_escape_reply())
    stub_reply(panel_reply(escapes))
    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    render_click(view, "record_cage_escape", %{})

    assert_received {:broker_stub_request, _conn, @escape_subject, payload, _opts}
    # No "period" at all: absent means the bot's clock decides, and sending a
    # period here would silently turn every ordinary tap into a correction.
    assert Jason.decode!(payload) == %{}
  end

  test "the correction names the one event it moves and the side it moves it to" do
    escapes = block(last_escape_reply())
    stub_reply(panel_reply(escapes))
    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    # The newest is night, so the button offers the other side and says so in words
    # rather than being a switch whose state has to be inferred from its position.
    assert render(view) =~ "it was day"

    view
    |> element(~s(button[phx-click="flip_cage_escape"]))
    |> render_click()

    assert_received {:broker_stub_request, _conn, @flip_subject, payload, _opts}
    # `phx-value-*` reaches the server as a string whatever the number looked like
    # on the page, so the id goes over as "3" and the bot reads either spelling.
    assert Jason.decode!(payload) == %{"id" => "3", "period" => "day"}
  end

  test "undo takes back the newest escape, with no body" do
    escapes = block(last_escape_reply())
    stub_reply(panel_reply(escapes))
    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    view
    |> element(~s(button[phx-click="undo_cage_escape"]))
    |> render_click()

    assert_received {:broker_stub_request, _conn, @undo_subject, payload, _opts}
    assert Jason.decode!(payload) == %{}
  end

  test "the sentence under the card reports the read that came back, never the write" do
    # The write and the re-read are answered separately, which is the only honest
    # way to tell "the bot took it" from "the log now says 3".
    after_write = block(last_escape_reply(), total: 3, night: 2, day: 1)

    stub_reply(%{
      @escape_subject => ok_reply(%{"total" => 1, "night" => 1, "day" => 0, "events" => []}),
      "wife_care.control_panel.state" => panel_reply(after_write)
    })

    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    render_click(view, "record_cage_escape", %{})
    await(view, "counted — 3 in all, 2 at night, 1 during the day.")

    assert render(view) =~ "counted — 3 in all, 2 at night, 1 during the day."
    # The write's own numbers are not the screen's to report.
    refute render(view) =~ "counted — 1 in all"
  end

  test "a refusal keeps the bot's own sentence instead of being rounded up to success" do
    sentence = "there is no escape recorded to take back"

    stub_reply(%{
      @undo_subject => Jason.encode!(%{"ok" => false, "error" => sentence}),
      "wife_care.control_panel.state" => panel_reply(block(last_escape_reply()))
    })

    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    view
    |> element(~s(button[phx-click="undo_cage_escape"]))
    |> render_click()

    assert render(view) =~ sentence
  end

  test "a dead broker is not a refusal, and says nothing was recorded" do
    stub_reply(%{
      @escape_subject => {:error, :timeout},
      "wife_care.control_panel.state" => panel_reply(block([]))
    })

    {:ok, view, _html} = live(build_conn(), "/body-phone")
    await(view, "The cage")

    render_click(view, "record_cage_escape", %{})

    assert render(view) =~ "nothing was recorded"
  end

  # ── the payload seam, without a browser ──────────────────────────────────────

  describe "HouseholdHUDPayload.cage_escapes_section/1" do
    test "reads the bot's block and keeps its counts" do
      section = HUD.cage_escapes_section(%{"cage_escapes" => block(last_escape_reply())})

      assert section.total == 3
      assert section.night == 2
      assert section.day == 1
      assert section.source == :reported
      assert section.window == %{from: 22, until: 8}
      assert section.last.id == 3
      assert section.last.period == :night
    end

    test "an absent block is unreported with nil counts, never zeroes" do
      for panel <- [%{}, nil, %{"cage_escapes" => nil}] do
        section = HUD.cage_escapes_section(panel)

        assert section.source == :unreported
        assert section.total == nil
        assert section.night == nil
        assert section.day == nil
        assert section.last == nil
      end
    end

    test "an event carrying a period this screen does not know is still drawn" do
      # The bot owns the periods. A new one must not crash the card or vanish; it
      # simply has no side of the night here yet.
      section =
        HUD.cage_escapes_section(%{
          "cage_escapes" => block([escape_event(1, at(60), "dusk")], total: 1, night: 0, day: 0)
        })

      assert section.total == 1
      assert section.last.id == 1
      assert section.last.period == nil
    end

    test "the key rides in the built panel payload beside the body section" do
      report =
        HUD.build(
          Jason.encode!(%{"state" => %{"cage_escapes" => block(last_escape_reply())}}),
          nil
        )

      assert report.cage_escapes.total == 3
      # Beside, not inside: it is a sibling of the body section, not a channel of it.
      refute Map.has_key?(report.body, :cage_escapes)
      assert Enum.all?(report.body.channels, &(&1.key != "cage_escapes"))
    end
  end
end
