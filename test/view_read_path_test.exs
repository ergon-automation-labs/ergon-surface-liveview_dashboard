defmodule BotArmyDashboardLiveview.ViewReadPathTest do
  @moduledoc """
  A screen that reads must show what the broker answered.

  Every phone/handheld view reads asynchronously in a `Task.start_link/1`. If the
  task addresses its result with `self()`, it is addressing *itself*, not the
  LiveView: the answer is dropped in a mailbox that is already dead and the screen
  sits on its spinner forever. That is what these tests pin — with a stub broker
  answering, the reading has to reach the screen.

  `async: false` because the stub is installed through application env.
  """
  use ExUnit.Case, async: false

  @moduletag :core

  @endpoint BotArmyDashboardLiveview.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @app :bot_army_dashboard_liveview

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

  defp install_reply(body), do: Application.put_env(@app, :broker_stub_reply, body)

  # `render_async/1` only tracks `start_async` PIDs, and these views read in a
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

  test "the projects screen shows the projects the broker answered with" do
    install_reply(
      ~s({"projects":[{"id":"p1","name":"Water the plants","description":"they are thirsty"}]})
    )

    {:ok, view, _html} = live(build_conn(), "/gtd-phone")

    await(view, "Water the plants")
    assert render(view) =~ "they are thirsty"
    refute render(view) =~ "Loading projects..."
  end

  test "the health screen stops saying it is checking" do
    install_reply(~s({"bots":[{"id":"wife_care","name":"Wife Care","status":"ok"}]}))

    {:ok, view, _html} = live(build_conn(), "/system-health-phone")

    await(view, "Wife Care")
    refute render(view) =~ "Checking system..."
  end

  # The lie this file exists for. A read that failed used to arrive as `[]`, and
  # `[]` renders as "No projects found" — a claim about the world made by a screen
  # that had not heard anything at all.
  test "a read that failed says so instead of showing an empty list" do
    install_reply({:exit, {:noproc, {:gen_server, :call, []}}})

    {:ok, view, _html} = live(build_conn(), "/gtd-phone")

    await(view, "Can\u2019t reach the bot")
    assert render(view) =~ "the bot is not reachable right now"
    refute render(view) =~ "Loading projects..."
  end

  test "the health screen reports a failed read as a failed read" do
    install_reply({:error, :timeout})

    {:ok, view, _html} = live(build_conn(), "/system-health-phone")

    await(view, "the bot did not answer in time")
    refute render(view) =~ "Checking system..."
  end

  # The phone health screen read `system.health.bots` and `system.health.nats`,
  # subjects nothing on the fleet answers, so it could only ever say "No bots
  # found" and "NATS Offline". It reads the registry now, like the handheld.
  test "the phone health screen shows the bots the registry answers with" do
    install_reply(
      ~s({"data":{"bots":[{"name":"wife_care","last_heartbeat":") <>
        DateTime.to_iso8601(DateTime.utc_now()) <>
        ~s(","subjects":[]}],"count":1,"responder":"registry"},) <>
        ~s("ok":true,"schema_version":"1.0","timestamp":"2026-09-24T02:06:37Z"})
    )

    {:ok, view, _html} = live(build_conn(), "/system-health-phone")

    await(view, "wife_care")
    assert render(view) =~ "Connected"
    refute render(view) =~ "No bots found"
  end

  # The registry answers with its own wrapper, and this screen was empty for so
  # long that its bot list had never actually rendered — its heartbeat line had
  # `#{format_heartbeat(...)}` in a text node, where HEEx keeps it literal.
  test "the handheld health screen renders the registry's bots, not its template source" do
    install_reply(
      ~s({"data":{"bots":[{"name":"wife_care","last_heartbeat":"2026-09-24T02:06:24.535Z","subjects":[]}],"count":1,"responder":"registry"},) <>
        ~s("ok":true,"schema_version":"1.0","timestamp":"2026-09-24T02:06:37Z"})
    )

    {:ok, view, _html} = live(build_conn(), "/system-health-handheld")

    await(view, "wife_care")
    refute render(view) =~ ~S(#{)
    refute render(view) =~ "No bots found"
  end

  # The view's own empty state is still in the DOM — the refusal card hides it.
  # Assert the hiding is there, because a hidden "No projects found" and a shown
  # one are the same text in a render/1.
  test "a failed read hides the empty state it would otherwise claim" do
    install_reply({:error, :timeout})

    {:ok, view, _html} = live(build_conn(), "/system-health-phone")

    await(view, "the bot did not answer in time")
    assert render(view) =~ ".empty-state { display: none; }"
  end
end
