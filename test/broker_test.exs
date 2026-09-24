defmodule BotArmyDashboardLiveview.BrokerTest do
  use ExUnit.Case, async: false
  @moduletag :core

  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.BrokerStub

  setup do
    Application.put_env(:bot_army_dashboard_liveview, :broker_transport, BrokerStub)

    on_exit(fn ->
      Application.delete_env(:bot_army_dashboard_liveview, :broker_transport)
      Application.delete_env(:bot_army_dashboard_liveview, :broker_stub_reply)
    end)
  end

  defp reply(value),
    do: Application.put_env(:bot_army_dashboard_liveview, :broker_stub_reply, value)

  test "asks the connection the app registers, and passes the question through unchanged" do
    assert {:ok, %{body: "{}"}} =
             Broker.request("wife_care.control_panel.hygiene", ~s({"a":1}), timeout: 500)

    assert_received {:broker_stub_request, :nats_connection, "wife_care.control_panel.hygiene",
                     ~s({"a":1}), [timeout: 500]}
  end

  test "a dead connection comes back as an error, not as an exit out of the caller" do
    reply({:exit, {:noproc, {:gen_server, :call, []}}})
    assert Broker.request("s", "{}") == {:error, :no_broker}
  end

  test "a call that times out is reported as a timeout" do
    reply({:exit, {:timeout, {:gen_server, :call, []}}})
    assert Broker.request("s", "{}") == {:error, :timeout}
  end

  test "an exit it cannot name is not blamed on the bot" do
    reply({:exit, :killed})
    assert Broker.request("s", "{}") == {:error, :broker_exit}
  end

  test "its own bugs are raised, never reported as an unreachable bot" do
    reply({:raise, "the payload could not be encoded"})

    assert_raise RuntimeError, "the payload could not be encoded", fn ->
      Broker.request("s", "{}")
    end
  end

  # The regression that shipped in 0.2.19: this wrapper called `Broker.request/3`
  # on the top-level alias `Broker` — a module that does not exist — and the
  # blanket rescue it shipped with reported the resulting UndefinedFunctionError
  # as :no_broker. Every read in the dashboard then said "the bot is not reachable
  # right now" while the broker was up and the bot was answering.
  #
  # No test could tell that apart from a genuinely dead broker, because the tests
  # asserted the *message* the screen showed. So this one asserts the compiled
  # call: it is not allowed to call a module that is not there, or itself.
  test "with the real transport, the wrapper asks the connection and nothing else" do
    Application.delete_env(:bot_army_dashboard_liveview, :broker_transport)
    assert Broker.transport() == Gnat

    {:function, _, :request, 3, clauses} =
      Broker |> abstract_forms() |> Enum.find(&match?({:function, _, :request, 3, _}, &1))

    calls = remote_calls(clauses)

    refute {Broker, :request} in calls, "Broker.request/3 must not ask itself"

    for {module, _fun} <- calls do
      assert Code.ensure_loaded?(module),
             "Broker.request/3 calls #{inspect(module)}, which does not exist"
    end

    # It reaches the connection either directly or through the seam that names it.
    assert {Gnat, :request} in calls or local_call?(clauses, :transport)
  end

  defp abstract_forms(module) do
    case :beam_lib.chunks(:code.which(module), [:abstract_code]) do
      {:ok, {_, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        forms

      other ->
        flunk("no debug info in the compiled module: #{inspect(other)}")
    end
  end

  defp remote_calls(term, acc \\ []) do
    acc =
      case term do
        {:remote, _line, {:atom, _, module}, {:atom, _, fun}} -> [{module, fun} | acc]
        _ -> acc
      end

    case term do
      tuple when is_tuple(tuple) -> tuple |> Tuple.to_list() |> Enum.reduce(acc, &remote_calls/2)
      list when is_list(list) -> Enum.reduce(list, acc, &remote_calls/2)
      _ -> acc
    end
  end

  defp local_call?(term, fun) do
    case term do
      {:call, _line, {:atom, _, ^fun}, _args} -> true
      tuple when is_tuple(tuple) -> tuple |> Tuple.to_list() |> Enum.any?(&local_call?(&1, fun))
      list when is_list(list) -> Enum.any?(list, &local_call?(&1, fun))
      _ -> false
    end
  end
end
