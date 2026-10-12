defmodule BotArmyDashboardLiveview.FitnessPhoneLogTest do
  @moduledoc """
  What the fitness phone is allowed to claim after a tap, and which verb it asks.

  This screen used to `Gnat.pub` `events.fitness.workout_logged`. **No bot has
  ever subscribed to that subject**, and a fire-and-forget publish returns `:ok`
  whether or not anybody is listening — so the phone said "💪 Workout logged!"
  every time and nothing was written anywhere. The live database held zero
  workouts for either identity, which is what that looks like from the outside.

  `fitness.workout.log` is the verb that writes, and since 2026-10-11 it answers
  with the `BotArmyLibraryRuntime.NATS.Reply` shape. So there are two pins here:
  the tap must ask that subject, and the confirmation must come from the reply —
  a refusal is shown in the bot's own words, never as a success.

  The broker is stubbed (`BrokerStub`) because the reply is the whole point: a
  test that sent `{:workout_logged}` straight into the LiveView's mailbox would
  be testing the screen's reaction to a message the test invented, and would pass
  just as happily with the dead subject still in place.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @log "fitness.workout.log"
  @dead "events.fitness.workout_logged"

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

  # The stub wraps a binary body into the `{:ok, %{body: body}}` that
  # `Gnat.request/4` returns, so these are the bodies, not the tuples.
  defp ok_reply do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{"workout_id" => "5f1b1a3c-0000-4000-8000-000000000001"}
    })
  end

  defp refused_reply(message) do
    Jason.encode!(%{"ok" => false, "error" => message, "code" => "missing_field"})
  end

  # An answer that takes a moment, so the state *between* the tap and the reply
  # can be looked at. Without this the stub answers within the same render.
  defp slow_ok_reply do
    {:answers,
     fn _subject ->
       Process.sleep(250)
       ok_reply()
     end}
  end

  # A tap, from the screen the user is actually on. The phone's own state machine
  # walks type -> intensity -> duration -> publish, and each step is one A.
  defp log_a_workout(view) do
    render_click(view, "gamepad-a", %{})
    render_click(view, "gamepad-a", %{})
    render_click(view, "gamepad-a", %{})
  end

  # The request runs in a `Task`, so the reply arrives as a message. Rendering
  # before it lands would only ever show "Logging workout...".
  defp after_the_reply(view) do
    Process.sleep(150)
    render(view)
  end

  test "a tap asks fitness.workout.log — the verb that writes — and nothing else" do
    Application.put_env(@app, :broker_stub_reply, ok_reply())

    {:ok, view, _html} = live(build_conn(), "/fitness-phone")

    log_a_workout(view)
    after_the_reply(view)

    assert_received {:broker_stub_request, _conn, @log, payload, _opts}

    assert %{
             "workout_type" => "run",
             "intensity" => "moderate",
             "duration_minutes" => 30
           } = Jason.decode!(payload)
  end

  test "the dead fire-and-forget subject is never asked" do
    Application.put_env(@app, :broker_stub_reply, ok_reply())

    {:ok, view, _html} = live(build_conn(), "/fitness-phone")

    log_a_workout(view)
    after_the_reply(view)

    refute_received {:broker_stub_request, _conn, @dead, _payload, _opts}
  end

  test "a successful reply is what puts the confirmation on the screen" do
    Application.put_env(@app, :broker_stub_reply, slow_ok_reply())

    {:ok, view, _html} = live(build_conn(), "/fitness-phone")

    log_a_workout(view)

    # The tap has gone out and nothing has answered yet: the screen may not have
    # claimed anything at this point.
    waiting = render(view)
    assert waiting =~ "Logging workout..."
    refute waiting =~ "Workout logged!"

    Process.sleep(400)
    assert render(view) =~ "Workout logged!"
  end

  test "a refusal is shown in the bot's own words, not as a success" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      refused_reply("missing required field: duration_minutes")
    )

    {:ok, view, _html} = live(build_conn(), "/fitness-phone")

    log_a_workout(view)
    html = after_the_reply(view)

    refute html =~ "Workout logged!"
    assert html =~ "missing required field: duration_minutes"
  end

  test "a broker that is not there says so, and does not claim a log" do
    Application.put_env(@app, :broker_stub_reply, {:error, :no_broker})

    {:ok, view, _html} = live(build_conn(), "/fitness-phone")

    log_a_workout(view)
    html = after_the_reply(view)

    refute html =~ "Workout logged!"
    assert html =~ "not reachable"
  end
end
