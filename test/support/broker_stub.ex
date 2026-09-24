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

    * a binary — the reply body
    * `{:error, reason}`
    * `{:exit, reason}` — to exercise the exit paths
    * `{:raise, message}` — to prove a bug is not mistaken for a dead bot
  """

  @config :bot_army_dashboard_liveview

  def request(conn, subject, payload, opts) do
    listener = Application.get_env(@config, :broker_stub_listener, self())
    send(listener, {:broker_stub_request, conn, subject, payload, opts})
    reply()
  end

  defp reply do
    case Application.get_env(@config, :broker_stub_reply, "{}") do
      {:exit, reason} -> exit(reason)
      {:raise, message} -> raise message
      {:error, reason} -> {:error, reason}
      body when is_binary(body) -> {:ok, %{body: body}}
    end
  end
end
