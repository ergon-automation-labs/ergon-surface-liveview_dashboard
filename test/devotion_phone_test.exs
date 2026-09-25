defmodule BotArmyDashboardLiveview.DevotionPhoneTest do
  # The reads swap the broker transport for a stub and set process-wide
  # application env, so this module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.Devotion

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @notes "wife_care.control_panel.subject_replies"
  @panel "wife_care.control_panel.state"
  @write "wife_care.control_panel.subject_reply"

  @sent "tonight I wanted to be told what to wear"
  @seed_text "devotions this week: 3 of 10"

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

  # The bot's own `control_panel.state` reply, cut to the four blocks the seeds
  # read. These are the live shapes: `engagement.this_week` and `quotas.weekly`
  # are both counted by the bot, and `maid_level.notice` is the house's own
  # present-tense sentence.
  defp state_reply(opts \\ []) do
    opts = Map.new(opts)

    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "engagement" => %{"this_week" => Map.get(opts, :week, 3), "today" => 1, "total" => 41},
        "quotas" => %{
          "weekly" => %{
            "status" => Map.get(opts, :status, "non_compliant"),
            "current" => Map.get(opts, :week, 3),
            "required" => Map.get(opts, :required, 10)
          }
        },
        "streak" => %{
          "current_streak" => Map.get(opts, :run, 2),
          "longest_streak" => Map.get(opts, :longest, 21)
        },
        "maid_level" => %{
          "level" => 1,
          "notice" => Map.get(opts, :notice, "this week reads 3 of 10")
        }
      }
    })
  end

  defp notes_reply(replies) do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{"replies" => replies, "window" => %{"reply_count" => length(replies)}}
    })
  end

  defp note(text, kind \\ "note", at \\ "2026-09-25T21:04:00Z") do
    %{"id" => "r-#{text}", "kind" => kind, "text" => text, "at" => at}
  end

  defp write_ok do
    Jason.encode!(%{"ok" => true, "data" => %{"reply" => %{"kind" => "note"}}})
  end

  defp stub_replies(overrides) do
    defaults = %{@notes => notes_reply([]), @panel => state_reply(), @write => write_ok()}

    Application.put_env(@app, :broker_stub_reply, Map.merge(defaults, overrides))
  end

  # A screen whose two reads have both answered, so a test starts from a settled
  # page rather than from the "reading what you have written…" state.
  # The text a test waits for is the text its own stub makes the screen show:
  # waiting for the standard seed line on a screen whose week is blank would wait
  # for a sentence that is right not to be there.
  defp page(overrides \\ %{}, settled \\ @seed_text) do
    stub_replies(overrides)
    {:ok, view, _html} = live(build_conn(), "/devotion-phone")
    await(view, settled)
    view
  end

  defp submit(view, text) do
    view |> form("form.devotion-form", %{text: text}) |> render_submit()
  end

  # `render_async/1` only tracks `start_async` PIDs and the screen re-reads in a
  # hand-rolled task, so wait for the text instead of for a frame.
  defp await(view, text), do: await(view, text, 50)

  defp await(view, text, 0) do
    flunk(
      "the screen never showed #{inspect(text)}; it showed: #{render(view) |> String.split("</head>") |> List.last() |> String.slice(0, 900)}"
    )
  end

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  # ── the seeds are the invitation ───────────────────────────────────────────

  test "the screen opens with the week as material, never as a score" do
    html = render(page())

    assert html =~ @seed_text
    assert html =~ "the run is 2, and it has been 21"
    assert html =~ "this week reads 3 of 10"
    # The openers are questions in the house's voice, and there are two of them.
    assert html =~ "what is worth telling her about today?"
    assert html =~ "what would you want her to know that the record cannot show?"
    refute html =~ "%"
  end

  test "a met week is said to be met, and still carries no grade" do
    html =
      render(
        page(
          %{
            @panel =>
              state_reply(
                week: 10,
                status: "compliant",
                notice: "the week's ask is met — 10 of 10"
              )
          },
          "the week is met: 10 of 10"
        )
      )

    assert html =~ "the week is met: 10 of 10"
    refute html =~ "Good submission"
  end

  test "an empty record says the week is blank rather than bad" do
    reply = Jason.encode!(%{"ok" => true, "data" => %{"window" => %{}}})

    html = render(page(%{@panel => reply}, "the bot has nothing on the week yet"))

    assert html =~ "the bot has nothing on the week yet — that is not the same as a bad week."
    refute html =~ "devotions this week"
  end

  test "a week that has not started still offers the openers" do
    html =
      render(
        page(
          %{@panel => state_reply(week: 0, run: 0, notice: "")},
          "devotions this week: 0 of 10"
        )
      )

    assert html =~ "devotions this week: 0 of 10"
    assert html =~ "what is worth telling her about today?"
  end

  # ── the write ──────────────────────────────────────────────────────────────

  test "a note is sent as a note of the window, trimmed" do
    view = page()
    submit(view, "   #{@sent}   ")

    assert_received {:broker_stub_request, :nats_connection, @write, body, _opts}
    assert Jason.decode!(body) == %{"kind" => "note", "text" => @sent}
  end

  # The one thing this screen must never do: report the call as a record. What
  # makes a note "logged" is the bot's own re-read holding its text.
  test "a note the record now holds is reported as logged" do
    view = page(%{@notes => notes_reply([note(@sent)])})
    submit(view, @sent)

    await(view, "the record now holds it")
    assert render(view) =~ @sent
  end

  test "a note the record does not hold is not reported as logged" do
    view = page(%{@notes => notes_reply([])})
    submit(view, @sent)

    await(view, "sent — reading it back…")
    refute render(view) =~ "logged"
  end

  test "a note is read back with the day it was written" do
    view = page(%{@notes => notes_reply([note("the first one", "note", "2026-09-20T08:00:00Z")])})

    assert render(view) =~ "2026-09-20"
    assert render(view) =~ "the first one"
  end

  # A note with nothing in it is not a note, and a blank row in the record of
  # what she said to the goddess is a row that claims she said something.
  test "an empty note is refused here and never reaches the bot" do
    view = page()
    submit(view, "   \n  ")

    assert render(view) =~ "a note with nothing in it is not a note"
    refute_received {:broker_stub_request, :nats_connection, @write, _body, _opts}
  end

  test "a refusal from the bot keeps its own sentence and keeps her words" do
    view =
      page(%{
        @write =>
          Jason.encode!(%{
            "ok" => false,
            "error" => "the house is paused — nothing is being recorded"
          })
      })

    submit(view, @sent)

    await(view, "the house is paused — nothing is being recorded")
    refute render(view) =~ "logged"
    assert render(view) =~ @sent
  end

  test "a dead broker says nothing was recorded, and logs it" do
    view = page(%{@write => {:error, :no_broker}})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        submit(view, @sent)
        await(view, "nothing was recorded")
      end)

    assert log =~ "[Devotion]"
    assert log =~ ":no_broker"
  end

  # ── the window holds more than notes ───────────────────────────────────────

  # A stop is consent information and is read where it is read. A devotion list
  # that mixed it in would quietly teach her that a stop is just another note.
  test "her other answers are not devotions" do
    replies =
      notes_reply([
        note("stop for now", "stop"),
        %{
          "id" => "r-2",
          "kind" => "too_much",
          "text" => "too much this week",
          "at" => "2026-09-24T09:00:00Z"
        }
      ])

    view = page(%{@notes => replies})

    html = render(view)

    refute html =~ "stop for now"
    refute html =~ "too much this week"
    assert html =~ "nothing written yet — the first one can be short."
  end

  # "The bot answered something else" is a different sentence from "there is
  # nothing", and this screen used to be able to say the second one for both.
  test "an answer shaped like neither a list nor a keyed list is a refusal" do
    stub_replies(%{@notes => Jason.encode!(%{"ok" => true, "data" => %{"replies" => "nope"}})})
    {:ok, view, _html} = live(build_conn(), "/devotion-phone")

    await(view, "the bot answered, but not with what this screen asked for")
    refute render(view) =~ "nothing written yet"
  end

  # ── the module's own rules ─────────────────────────────────────────────────

  test "only notes survive, newest first, and only ten of them" do
    notes = [note("kept", "note") | for(n <- 1..14, do: note("n#{n}"))]

    kept = Devotion.notes_only(notes)

    assert length(kept) == 10
    assert Devotion.field(hd(kept), "text") == "kept"
  end

  test "a note read back off the store, with atoms, still reads" do
    kept =
      Devotion.notes_only([%{id: "r", kind: :note, text: "the maid version", at: "2026-09-25"}])

    assert length(kept) == 1
    assert Devotion.field(hd(kept), "text") == "the maid version"
    assert Devotion.when_label(hd(kept)) == "2026-09-25"
  end

  test "a note with no readable date is dated earlier rather than dated now" do
    assert Devotion.when_label(%{"at" => nil}) == "earlier"
    assert Devotion.when_label(%{}) == "earlier"
  end
end
