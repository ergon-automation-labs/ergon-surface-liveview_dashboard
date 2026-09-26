defmodule BotArmyDashboardLiveview.BrokerStub do
  @moduledoc """
  A stand-in connection for tests: it records the question it was asked and
  answers from application config.

  A screen's read path can then be exercised without a broker, which is the only
  way to test what the screen does with an *answer*. The suite used to `send/2`
  the answer straight into the LiveView instead, so it never went through
  `Broker` at all — and a `Broker` that asked nobody was indistinguishable from a
  broker that was down.

  Configure with `:broker_stub_reply`:

    * a binary — the reply body, for every subject
    * a map — the reply body per subject, so a screen that asks two questions
      can be answered differently on each (a subject the map does not name is
      answered with `"{}"`)
    * `{:answers, fun}` — a function of the subject, for a read that has to
      answer *differently over time*, which is the only honest way to test a
      screen that re-reads after a write. What it returns is resolved like any
      other value here, so it can return a body, a map, or an error.
    * `{:error, reason}`
    * `{:exit, reason}` — to exercise the exit paths
    * `{:raise, message}` — to prove a bug is not mistaken for a dead bot
  """

  @config :bot_army_dashboard_liveview

  def request(conn, subject, payload, opts) do
    listener = Application.get_env(@config, :broker_stub_listener, self())
    send(listener, {:broker_stub_request, conn, subject, payload, opts})
    reply(subject)
  end

  defp reply(subject) do
    @config
    |> Application.get_env(:broker_stub_reply, "{}")
    |> resolve(subject)
  end

  defp resolve(replies, subject) when is_map(replies) do
    answer(Map.get(replies, subject, "{}"), subject)
  end

  defp resolve(reply, subject), do: answer(reply, subject)

  defp answer({:exit, reason}, _subject), do: exit(reason)
  defp answer({:raise, message}, _subject), do: raise(message)
  defp answer({:error, reason}, _subject), do: {:error, reason}

  # A screen that re-reads after a write has to see the wardrobe change, and the
  # change is what the re-read is for. The function gets the subject and returns
  # whatever the stored reply would have been.
  defp answer({:answers, fun}, subject) when is_function(fun, 1),
    do: answer(fun.(subject), subject)

  defp answer(body, _subject) when is_binary(body), do: {:ok, %{body: body}}
end
