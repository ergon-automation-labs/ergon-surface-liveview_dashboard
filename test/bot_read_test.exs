defmodule BotArmyDashboardLiveview.BotReadTest do
  @moduledoc """
  The read layer's contract: an answer, or a reason — never an empty list.

  `async: false` because the stub transport is installed through application env.
  """
  use ExUnit.Case, async: false

  @moduletag :core

  import Phoenix.Component, only: [assign: 2]

  alias BotArmyDashboardLiveview.BotRead
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

  defp reply(body), do: Application.put_env(@app, :broker_stub_reply, body)

  describe "list/2" do
    test "takes a list answer as it is" do
      assert BotRead.list([%{"id" => "p1"}], "projects") == {:ok, [%{"id" => "p1"}]}
      assert BotRead.list([], "projects") == {:ok, []}
    end

    test "takes the list the answer carries under its key" do
      assert BotRead.list(%{"projects" => [%{"id" => "p1"}]}, "projects") ==
               {:ok, [%{"id" => "p1"}]}

      assert BotRead.list(%{"projects" => []}, "projects") == {:ok, []}
    end

    test "refuses an answer shaped like neither" do
      assert BotRead.list(%{"error" => "no idea"}, "projects") == :error
      assert BotRead.list(%{"projects" => "not a list"}, "projects") == :error
      assert BotRead.list(%{"projects" => nil}, "projects") == :error
      assert BotRead.list(nil, "projects") == :error
      assert BotRead.list("projects", "projects") == :error
    end
  end

  describe "read/3" do
    test "answers with the decoded reply" do
      reply(~s({"projects":[{"id":"p1"}]}))

      assert BotRead.read("bridge.project.list", %{}) == {:ok, %{"projects" => [%{"id" => "p1"}]}}
    end

    test "unwraps the envelope a responder wrapped around the payload" do
      reply(~s({"correlation_id":"c-1","data":{"bots":[{"id":"wife_care"}]}}))

      assert BotRead.read("bot_army.registry.bots.list", %{}) ==
               {:ok, %{"bots" => [%{"id" => "wife_care"}]}}
    end

    test "unwraps the bot registry's answer, which wraps its bots in data" do
      # Measured off the wire, 2026-09-24. The registry's wrapper carries its own
      # `ok` and `schema_version`, and a strict envelope rule that did not know
      # them read the bots as an unreadable answer.
      reply(
        ~s({"data":{"bots":[{"id":"wife_care"}],"count":1,"responder":"registry"},) <>
          ~s("ok":true,"schema_version":"1.0","timestamp":"2026-09-24T02:06:37Z"})
      )

      assert {:ok, answer} = BotRead.read("bot_army.registry.bots.list", %{})
      assert BotRead.list(answer, "bots") == {:ok, [%{"id" => "wife_care"}]}
    end

    test "leaves a payload alone when it has a data key of its own" do
      # An envelope is `data` and nothing but envelope keys beside it. Anything
      # else is the answer itself, and taking its `data` would hand the screen the
      # inside of its own reading.
      reply(~s({"correlation_id":"c-1","data":{"x":1},"payload":"thing"}))

      assert BotRead.read("some.subject", %{}) ==
               {:ok, %{"data" => %{"x" => 1}, "payload" => "thing", "correlation_id" => "c-1"}}
    end

    test "a reply that is not JSON is a bad reply, not an empty answer" do
      reply("not json at all")
      assert BotRead.read("some.subject", %{}) == {:error, :bad_reply}

      reply("")
      assert BotRead.read("some.subject", %{}) == {:error, :bad_reply}
    end

    test "a dead connection comes back as a reason, not as an exit" do
      reply({:exit, {:noproc, {:gen_server, :call, []}}})
      assert BotRead.read("some.subject", %{}) == {:error, :no_broker}

      reply({:error, :timeout})
      assert BotRead.read("some.subject", %{}) == {:error, :timeout}
    end
  end

  describe "async/5" do
    test "answers the caller with the value, and says it started" do
      reply(~s({"projects":[]}))
      assert BotRead.async(self(), :projects_loaded, "bridge.project.list", %{}) == :ok

      assert_receive {:read_started}
      assert_receive {:projects_loaded, %{"projects" => []}}
    end

    test "answers a failure as a failure for the screen to explain" do
      reply({:exit, {:noproc, {:gen_server, :call, []}}})
      assert BotRead.async(self(), :projects_loaded, "bridge.project.list", %{}) == :ok

      assert_receive {:read_started}
      assert_receive {:read_failed, :no_broker}
      refute_received {:projects_loaded, _anything}
    end
  end

  describe "message/1" do
    test "names the failure in the operator's terms" do
      assert BotRead.message(:no_broker) == "the bot is not reachable right now"
      assert BotRead.message(:timeout) == "the bot did not answer in time"
      assert BotRead.message(:unexpected_reply) =~ "not with what this screen asked for"
    end

    test "never answers, so a screen never renders a nil" do
      for reason <- [:bad_reply, :bad_payload, :broker_exit, :something_else, nil, %{}] do
        message = BotRead.message(reason)
        assert is_binary(message) and message != ""
      end
    end
  end

  describe "failed/2" do
    test "stops every spinner on the screen, not just :loading" do
      socket =
        assign(%Phoenix.LiveView.Socket{}, %{
          loading: true,
          narrative_loading: true,
          saving: true,
          read_error: nil
        })

      failed = BotRead.failed(socket, :timeout)

      assert failed.assigns.loading == false
      assert failed.assigns.narrative_loading == false
      assert failed.assigns.saving == true
      assert failed.assigns.read_error == "the bot did not answer in time"
    end

    test "a screen with a NATS badge learns the broker did not answer" do
      socket = assign(%Phoenix.LiveView.Socket{}, %{loading: true, nats_status: :checking})

      assert BotRead.failed(socket, :timeout).assigns.nats_status == :unhealthy
    end

    test "a screen with no NATS badge gets no nats_status assign invented for it" do
      socket = assign(%Phoenix.LiveView.Socket{}, %{loading: true})

      refute Map.has_key?(BotRead.failed(socket, :timeout).assigns, :nats_status)
    end
  end
end
