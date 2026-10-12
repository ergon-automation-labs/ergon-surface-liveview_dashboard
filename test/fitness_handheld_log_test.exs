defmodule BotArmyDashboardLiveview.FitnessHandheldLogTest do
  @moduledoc """
  Which verb the fitness **handheld** logs through, and what it may claim.

  This screen asked `fitness.set.log` for a body that handler cannot read.
  `SetLoggerHandler` wants `exercise_name`/`reps_achieved`/`reps_target` and
  answers `{\"error\": \"missing_required_fields\"}` — a reply with no `\"ok\"` key
  at all — for anything else. The screen matched `{:ok, _response}`, so it said
  \"✓ Logged: …\" over a write the bot had refused, every single time. There was a
  second lie inside it too: `fitness.set.log` is the *comfort-level* verb, so even
  a payload it could read would not have recorded a workout.

  `fitness.workout.log` is the verb that records one, and since 2026-10-11 it
  answers, so the confirmation can come from the reply instead of from the bare
  fact that something came back.

  The broker is stubbed, because the reply is the point: a test that sent
  `{:workout_logged, …}` straight into the LiveView would pass with the wrong
  subject still in place.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @list "fitness.workout.list"
  @log "fitness.workout.log"
  @wrong "fitness.set.log"

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

  # A stored workout as the list reply carries it — `exercise_type` is the
  # canonical value the bot stores, which is what the log body must forward.
  defp stored_workout do
    %{
      "workout_id" => "5f1b1a3c-0000-4000-8000-000000000009",
      "title" => "Morning run",
      "exercise_type" => "running",
      "duration_minutes" => 35,
      "intensity" => "moderate",
      "date" => "2026-10-10"
    }
  end

  defp list_body do
    Jason.encode!(%{"ok" => true, "data" => %{"workouts" => [stored_workout()], "count" => 1}})
  end

  defp replies(log_body) do
    %{@list => list_body(), @log => log_body}
  end

  defp ok_log_body do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{"workout_id" => "5f1b1a3c-0000-4000-8000-000000000010"}
    })
  end

  defp log_the_selected(view) do
    render_click(view, "gamepad-confirm", %{})
    Process.sleep(150)
    render(view)
  end

  test "the tap asks fitness.workout.log and forwards the stored workout" do
    Application.put_env(@app, :broker_stub_reply, replies(ok_log_body()))

    {:ok, view, _html} = live(build_conn(), "/fitness-handheld")

    log_the_selected(view)

    assert_received {:broker_stub_request, _conn, @log, payload, _opts}

    assert %{
             "workout_type" => "running",
             "duration_minutes" => 35,
             "intensity" => "moderate",
             "title" => "Morning run"
           } = Jason.decode!(payload)
  end

  test "the comfort-level verb is never asked" do
    Application.put_env(@app, :broker_stub_reply, replies(ok_log_body()))

    {:ok, view, _html} = live(build_conn(), "/fitness-handheld")

    log_the_selected(view)

    refute_received {:broker_stub_request, _conn, @wrong, _payload, _opts}
  end

  test "a successful reply is what puts the confirmation on the screen" do
    Application.put_env(@app, :broker_stub_reply, replies(ok_log_body()))

    {:ok, view, _html} = live(build_conn(), "/fitness-handheld")

    assert log_the_selected(view) =~ "Logged: Morning run"
  end

  test "a refusal is shown, not turned into a success" do
    refused =
      Jason.encode!(%{
        "ok" => false,
        "error" => "missing required field: duration_minutes",
        "code" => "missing_field"
      })

    Application.put_env(@app, :broker_stub_reply, replies(refused))

    {:ok, view, _html} = live(build_conn(), "/fitness-handheld")

    html = log_the_selected(view)

    refute html =~ "Logged:"
    assert html =~ "missing required field: duration_minutes"
  end

  # The handler's old answer, kept as a pin: a reply with no `"ok"` key is not a
  # success, and this is the exact body that used to be read as one.
  test "the old error-shaped reply is a refusal, not a confirmation" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      replies(Jason.encode!(%{"error" => "missing_required_fields"}))
    )

    {:ok, view, _html} = live(build_conn(), "/fitness-handheld")

    html = log_the_selected(view)

    refute html =~ "Logged:"
    assert html =~ "missing_required_fields"
  end
end
