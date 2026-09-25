defmodule BotArmyDashboardLiveview.HouseholdHUDBodyTest do
  # Same harness as the yearning card: the write path swaps the broker transport
  # for a stub and sets process-wide application env, so this module is not async.
  #
  # One stub reply answers every subject, which is what makes the write and the
  # re-read that follows it the same answer — the tests that need those two to
  # disagree say so explicitly.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview
  @subject "wife_care.control_panel.record_body_reading"
  @channels ~w(arousal breathing hands pulse cage)
  # Written out rather than as `~w`: the `~w` sigil splits on whitespace and its
  # `\ ` escape does not glue words back together, so `~w(a\ little)` is two words.
  @words ["none", "a little", "some", "a lot", "a great deal", "as much as it gets"]

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

  defp bot_scale do
    @words
    |> Enum.with_index()
    |> Enum.map(fn {word, level} -> %{"level" => level, "label" => word} end)
  end

  defp bot_kinds do
    Enum.map(@channels, fn key -> %{"key" => key, "label" => String.capitalize(key)} end)
  end

  # One row exactly as `BodyReadings.view/1` sends it.
  defp reading(level, kind \\ "hands", opts \\ []) do
    word = Enum.at(@words, level)

    %{
      "id" => "00000000-0000-4000-8000-000000000000",
      "kind" => kind,
      "label" => String.capitalize(kind),
      "level" => level,
      "level_label" => word,
      "value" => level,
      "unit" => nil,
      "display" => "#{word} (#{level} of 5)",
      "source" => "reported",
      "source_label" => Keyword.get(opts, :source_label, "what she said"),
      "cadence" => "tap",
      "device" => nil,
      "confidence" => nil,
      "window_s" => nil,
      "session_id" => nil,
      "note" => nil,
      "reported_by" => "subject",
      "occurred_at" => "2026-09-25T20:00:00Z",
      "minutes_ago" => Keyword.get(opts, :minutes_ago, 4),
      "today?" => Keyword.get(opts, :today?, true)
    }
  end

  defp latest(reported) do
    Map.new(@channels, fn key -> {key, Map.get(reported, key)} end)
  end

  # The bot's `control_panel.state` reply, cut to the body block.
  defp state_reply(reported, opts \\ []) do
    body = %{
      "kinds" => Keyword.get(opts, :kinds, bot_kinds()),
      "scale" => Keyword.get(opts, :scale, bot_scale()),
      "max_level" => 5,
      "latest" => latest(reported),
      "recent" => [],
      "any_reported?" => Enum.any?(reported, fn {_kind, row} -> is_map(row) end)
    }

    Jason.encode!(%{"ok" => true, "data" => %{"body" => body}})
  end

  defp stub_reply(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  # A screen whose reads have already answered, so a test starts from a settled
  # card rather than from the "asking the house" state.
  defp hud(reported, opts \\ []) do
    stub_reply(state_reply(reported, opts))
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    await(view, "The body")
    view
  end

  # `render_async/1` only tracks `start_async` PIDs and the screen re-reads in a
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

  defp tap(view, kind, level) do
    render_click(view, "record_body_reading", %{"kind" => kind, "level" => level})
  end

  defp occurrences(html, text), do: length(String.split(html, text)) - 1

  # ── the card ────────────────────────────────────────────────────────────────

  test "the card draws every channel the bot keeps, each with the six points" do
    html = render(hud(%{"hands" => reading(3)}))

    for kind <- @channels do
      assert html =~ ~s(phx-value-kind="#{kind}")
    end

    for level <- 0..5 do
      assert html =~ ~s(phx-value-level="#{level}")
    end

    refute html =~ ~s(phx-value-level="6")
    # The words are on the card, not only in a hover title a handheld cannot show.
    assert html =~ "0 none"
    assert html =~ "5 as much as it gets"
    # And the card says what a tap is.
    assert html =~ "never what was measured"
  end

  # The channel list is the bot's, not this screen's idea of it. A channel the bot
  # has added must appear without a surface release; one it has dropped must go.
  test "the channels drawn are the bot's list, not a list this screen keeps" do
    kinds = [%{"key" => "throat", "label" => "Throat", "detail" => "how tight it has gone"}]
    html = render(hud(%{}, kinds: kinds))

    assert html =~ ~s(phx-value-kind="throat")
    refute html =~ ~s(phx-value-kind="hands")
  end

  # Same rule for the scale: a bot that renames its points must not leave the card
  # offering words the house no longer uses.
  test "the scale drawn is the bot's scale, not this screen's" do
    scale = [%{"level" => 0, "label" => "nothing"}, %{"level" => 5, "label" => "everything"}]
    html = render(hud(%{}, scale: scale))

    # Scoped to the body card's own legend: the Yearning card draws the house
    # scale on the same screen, so a bare `phx-value-level` search would pass on
    # somebody else's buttons.
    assert html =~ "The points: 0 nothing · 5 everything"
    refute html =~ "The points: 0 none"
  end

  # A channel nobody has read is not a channel at zero. The card says so in words,
  # and it does not highlight a point on that row.
  test "a channel with nothing on record reads not reported, never zero" do
    view = hud(%{})

    assert render(view) =~ "not reported"
    refute has_element?(view, "button.tap.on")
  end

  test "the highlighted point is today's reading for that channel" do
    view = hud(%{"hands" => reading(3), "pulse" => reading(1, "pulse")})

    assert has_element?(view, "button[phx-value-kind=hands][phx-value-level=3].tap.on")
    assert has_element?(view, "button[phx-value-kind=pulse][phx-value-level=1].tap.on")
    refute has_element?(view, "button[phx-value-kind=hands][phx-value-level=2].tap.on")
    refute has_element?(view, "button[phx-value-kind=cage].tap.on")
  end

  # A reading from another day is still a reading — it is shown with its number —
  # but it is not today's, so nothing on that row is painted as the current state.
  test "a reading from an earlier day is shown but not highlighted" do
    view = hud(%{"hands" => reading(3, "hands", today?: false)})

    assert render(view) =~ "a lot (3 of 5)"
    refute has_element?(view, "button[phx-value-kind=hands].tap.on")
  end

  # Where a number came from is part of the number: a measurement must never be
  # dressed in the words of a finger press.
  test "the card carries the bot's own words for where the reading came from" do
    view = hud(%{"pulse" => reading(2, "pulse", source_label: "measured")})

    assert render(view) =~ "measured"
    refute render(view) =~ "what she said"
  end

  # ── the tap ─────────────────────────────────────────────────────────────────

  test "a tap logs the channel and the point, in the body the bot actually reads" do
    view = hud(%{"hands" => reading(2)})
    stub_reply(state_reply(%{"hands" => reading(4)}))

    tap(view, "hands", "4")

    assert_received {:broker_stub_request, :nats_connection, @subject, sent_body, _opts}

    assert Jason.decode!(sent_body) == %{
             "kind" => "hands",
             "level" => 4,
             "source" => "reported"
           }
  end

  # The one thing this screen must never do: show the number it sent as if the
  # house had agreed. After a tap the card reads the house again, and what it
  # paints is the answer.
  test "what is shown after a tap is the bot's reading, not the tap" do
    view = hud(%{"hands" => reading(2)})
    stub_reply(state_reply(%{"hands" => reading(4)}))

    tap(view, "hands", "4")
    await(view, "the reading that came back is Hands at 4 of 5 (a great deal)")

    assert has_element?(view, "button[phx-value-kind=hands][phx-value-level=4].tap.on")
  end

  # "Saved" and "the bot says 4" are two different claims. When the write is taken
  # but the reading that comes back is not the one sent, the card says exactly
  # that instead of rounding up to success.
  test "a tap the bot took but did not read back as is reported as such" do
    view = hud(%{"hands" => reading(2)})
    # One body answers both calls: the write sees `ok: true` and is taken, and the
    # re-read that follows reports 3.
    stub_reply(state_reply(%{"hands" => reading(3)}))

    tap(view, "hands", "4")
    await(view, "but its reading shows a lot (3 of 5)")

    assert render(view) =~ "the bot took Hands at 4 of 5 (a great deal)"
    refute has_element?(view, "button[phx-value-kind=hands][phx-value-level=4].tap.on")
  end

  # A tap on the body card must not report itself under the Yearning card. Two
  # cards are on screen at once, and a line under the wrong one is a lie about
  # where the reading went.
  test "a body tap speaks once, on its own card" do
    view = hud(%{"hands" => reading(2)})
    stub_reply(state_reply(%{"hands" => reading(4)}))

    tap(view, "hands", "4")
    await(view, "the reading that came back is Hands at 4 of 5")

    assert occurrences(render(view), "the reading that came back is") == 1
    refute render(view) =~ "the reading that came back is 4 of 5"
  end

  # A refusal is the bot's sentence, not this screen's paraphrase. The bot names
  # the channels it keeps; a paraphrase loses the part the operator needs.
  test "a refusal is shown in the bot's own words and claims nothing" do
    view = hud(%{})

    stub_reply(
      Jason.encode!(%{
        "ok" => false,
        "error" => "unknown channel: toes",
        "code" => "validation_error"
      })
    )

    tap(view, "hands", "5")
    await(view, "unknown channel: toes")

    refute render(view) =~ "logged —"
    refute has_element?(view, "button.tap.on")
  end

  # A dead broker is not a refusal. "Nothing was recorded" is the one thing this
  # sentence has to make unambiguous, and it has to leave a trace for the
  # operator: a button that quietly does nothing is not a diagnosis.
  test "an answer that never comes says nothing was recorded, and logs it" do
    view = hud(%{})
    stub_reply({:error, :no_broker})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        tap(view, "hands", "3")
        await(view, "nothing was recorded")
      end)

    assert log =~ "[HouseholdHUD]"
    assert log =~ ":no_broker"
  end

  # The screen owns this check because a bad point is a bad *request*, not a
  # reading the house should have to refuse. Nothing is sent.
  test "a point outside the six is refused before anything is sent" do
    view = hud(%{})

    tap(view, "hands", "9")

    assert render(view) =~ "not one of the six points this house keeps"
    refute_received {:broker_stub_request, :nats_connection, @subject, _body, _opts}
  end

  # A channel this screen never drew is a stale page, not a reading. Sending it
  # would put a word in the house's mouth.
  test "a channel that is not on the card is refused before anything is sent" do
    view = hud(%{})

    tap(view, "toes", "3")

    assert render(view) =~ "not a channel on this card"
    refute_received {:broker_stub_request, :nats_connection, @subject, _body, _opts}
  end

  # ── the payload, without a socket ───────────────────────────────────────────

  describe "the body section" do
    test "a channel the bot sent with no key is dropped rather than drawn" do
      section = HUD.body_section(%{"body" => %{"kinds" => [%{"label" => "Nameless"}]}})

      refute Enum.any?(section.channels, &(&1.key in [nil, ""]))
      assert length(section.channels) == length(@channels)
    end

    test "a report with no body block leaves a card that can still be tapped" do
      section = HUD.body_section(%{"intent" => %{}})

      assert section.source == :unreported
      assert Enum.map(section.channels, & &1.key) == @channels
      assert Enum.all?(section.channels, &(&1.level == nil and &1.source == :unreported))
      assert section.scale == HUD.house_scale()
    end

    test "a failed read falls back to the channels the house keeps" do
      section = HUD.body_section(nil)

      assert Enum.map(section.channels, & &1.key) == @channels
      assert section.any_reported? == false
    end
  end
end
