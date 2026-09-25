defmodule BotArmyDashboardLiveview.TimerPhoneYearningTest do
  # The write path swaps the broker transport for a stub and sets process-wide
  # application env, so this module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview
  @subject "wife_care.control_panel.record_goddess_proximity"

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

  # The bot's `control_panel.state` reply, cut to the one block this card reads.
  # `reported_today` is what makes a reading "today's"; the level alone does not.
  defp state_reply(level, today? \\ true) do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        # The timer phone also reads its task list; one stub body answers
        # every subject, so the panel reply carries an empty list for it.
        "tasks" => [],
        "louiza" => %{
          "yearning" => %{
            "level" => level,
            "reported_today" => today?,
            "occurred_on" => "2026-09-25"
          }
        }
      }
    })
  end

  defp stub_reply(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  # A screen whose two reads have already answered, so a test starts from a
  # settled card rather than from the "asking the house" state.
  defp hud(level) do
    stub_reply(state_reply(level))
    {:ok, view, _html} = live(build_conn(), "/timer-phone")
    await(view, "#{level} of 5")
    view
  end

  # `render_async/1` only tracks `start_async` PIDs and the screen re-reads in a
  # hand-rolled task, so wait for the text instead of for a frame. Same bounded
  # poll the other read-path tests use.
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

  defp tap_point(view, level), do: render_click(view, "record_yearning", %{"level" => level})

  test "the card offers the house's six points and nothing finer" do
    html = render(hud(2))

    for level <- 0..5 do
      assert html =~ ~s(phx-value-level="#{level}")
    end

    refute html =~ ~s(phx-value-level="6")
    # The words are on the card, not only in a hover title a handheld cannot show.
    assert html =~ "0 none right now"
    assert html =~ "5 as much as it gets"
    # And the card says whose number it is.
    assert html =~ "never measured"
  end

  test "the reading that is highlighted is today's reading" do
    view = hud(3)

    assert has_element?(view, "button[phx-value-level=3].tap.on")
    refute has_element?(view, "button[phx-value-level=2].tap.on")
  end

  # A reading from another day is not today's, and the card must not paint it as
  # if it were — the same distinction the payload draws between "0 of 5" and
  # "no reading today".
  test "a reading from an earlier day is shown but not highlighted" do
    stub_reply(state_reply(4, false))
    {:ok, view, _html} = live(build_conn(), "/timer-phone")
    await(view, "Last reading on 2026-09-25")

    refute has_element?(view, "button.tap.on")
  end

  test "a tap logs the point, in the body the bot actually reads" do
    view = hud(2)
    stub_reply(state_reply(4))

    tap_point(view, "4")

    assert_received {:broker_stub_request, :nats_connection, @subject, sent_body, _opts}
    assert Jason.decode!(sent_body) == %{"goddess_proximity_seeking" => 4}
  end

  # The one thing this screen must never do: show the number it sent as if the
  # house had agreed. After a tap the card reads the house again, and what it
  # paints is the answer.
  test "what is shown after a tap is the bot's reading, not the tap" do
    view = hud(2)
    stub_reply(state_reply(4))

    tap_point(view, "4")
    await(view, "the reading that came back is 4 of 5")

    assert has_element?(view, "button[phx-value-level=4].tap.on")
    assert render(view) =~ "a great deal"
  end

  # "Saved" and "the bot says 4" are two different claims. When the write is
  # taken but the reading that comes back is not the one sent, the card says
  # exactly that instead of rounding up to success.
  test "a tap the bot took but did not read back as is reported as such" do
    view = hud(2)
    # One body answers both calls: the write sees `ok: true` and is taken, and the
    # re-read that follows reports 3.
    stub_reply(state_reply(3))

    tap_point(view, "4")
    await(view, "but its reading shows 3 of 5")

    assert render(view) =~ "the bot took 4 of 5 (a great deal)"
    refute has_element?(view, "button[phx-value-level=4].tap.on")
  end

  # A refusal is the bot's sentence, not this screen's paraphrase. The bot names
  # the range and the reason; a paraphrase loses the part the operator needs.
  test "a refusal is shown in the bot's own words and claims nothing" do
    view = hud(2)

    stub_reply(
      Jason.encode!(%{
        "ok" => false,
        "error" => "goddess_proximity_seeking must be between 0 and 5",
        "code" => "validation_error"
      })
    )

    tap_point(view, "5")
    await(view, "must be between 0 and 5")

    refute render(view) =~ "logged —"
    refute has_element?(view, "button[phx-value-level=5].tap.on")
  end

  # A dead broker is not a refusal. "Nothing was recorded" is the one thing this
  # sentence has to make unambiguous, and it has to leave a trace for the
  # operator: a button that quietly does nothing is not a diagnosis.
  test "an answer that never comes says nothing was recorded, and logs it" do
    view = hud(2)
    stub_reply({:error, :no_broker})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        tap_point(view, "3")
        await(view, "nothing was recorded")
      end)

    assert log =~ "[SelfReport]"
    assert log =~ ":no_broker"
  end

  # The screen owns this check because a bad point is a bad *request*, not a
  # reading the house should have to refuse. Nothing is sent.
  test "a point outside the six is refused before anything is sent" do
    view = hud(2)
    stub_reply(state_reply(2))

    tap_point(view, "9")

    assert render(view) =~ "not one of the six points this house keeps"
    refute_received {:broker_stub_request, :nats_connection, @subject, _body, _opts}
  end

  test "a tap that is not a number is refused the same way" do
    view = hud(2)

    tap_point(view, "four")

    assert render(view) =~ "not one of the six points this house keeps"
    refute_received {:broker_stub_request, :nats_connection, @subject, _body, _opts}
  end
end
