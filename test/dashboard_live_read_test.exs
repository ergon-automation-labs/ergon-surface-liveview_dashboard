defmodule BotArmyDashboardLiveview.DashboardLiveReadTest do
  @moduledoc """
  The landing page's reads, which were the last ones still taken in band.

  `/` awaited `bridge.task.list` and `bridge.task.search` inside `mount/3` — two
  five-second timeouts, one after the other, against subjects nothing answers —
  and both helpers returned `[]` when the read failed. So a broker that answered
  nothing produced a confident "No tasks yet", ten seconds late, on the page the
  whole dashboard opens on.

  `async: false` because the stub broker is installed through application env.
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

  defp await(view, text), do: await(view, text, 100)

  defp await(_view, text, 0), do: flunk("the screen never showed #{inspect(text)}")

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  test "a read nobody answers is a refusal, not an empty task list" do
    install_reply("{}")

    {:ok, view, html} = live(build_conn(), "/")

    # The page is up before either read is answered — this is the page that used
    # to take ten seconds — and it does not yet claim there is nothing.
    assert html =~ "Live Task Feed"
    refute html =~ "No tasks yet"

    await(view, "reach the bot")
    refute render(view) =~ "No tasks yet"
  end

  test "the feed shows what the broker answered with" do
    install_reply(~s({"tasks":[{"id":"t1","title":"Put the kettle on","status":"pending"}]}))

    {:ok, view, _html} = live(build_conn(), "/")

    await(view, "Put the kettle on")
    refute render(view) =~ "reach the bot"
  end

  test "a task list that comes back empty is the only time it says so" do
    install_reply(~s({"tasks":[]}))

    {:ok, view, _html} = live(build_conn(), "/")

    await(view, "No tasks yet")
    refute render(view) =~ "reach the bot"
  end
end
