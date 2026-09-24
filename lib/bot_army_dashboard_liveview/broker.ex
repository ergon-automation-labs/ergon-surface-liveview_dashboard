defmodule BotArmyDashboardLiveview.Broker do
  @moduledoc """
  Ask the broker a question without letting an exit out of the caller.

  `Gnat.request/4` against a connection process that is not running does not
  return an error — it *exits* with `:noproc`, and an exit is not an exception,
  so a `try/rescue` wrapped around it looks like a guard and is not one.

  That is not theoretical: several screens asked their first question inside
  `mount/3`, so a dashboard whose broker was down answered 500 for the whole
  screen instead of showing the screen with a "can't reach the bot" line in it.
  A screen that cannot be reached should say so, not disappear.

  Every call site in this app sits inside a `Task` (or in mount) and already
  handles `{:error, reason}`, so turning the exit into one is the whole fix.

  What this module must not do is turn its own bugs into that message. The first
  version of it asked *itself* instead of the connection and, with a blanket
  `rescue`, reported the resulting stack error as `:no_broker`: every read in the
  dashboard said "the bot is not reachable right now" while the broker was up and
  the bot was answering. A wrapper that guesses at the cause of a local failure
  is a lie about a remote one, so there is no rescue here — only an exit is
  translated, and a raised error is left to raise.
  """

  @connection :nats_connection
  @config :bot_army_dashboard_liveview

  @doc """
  `request(subject, payload, opts)` on the registered connection, with an
  unreachable connection returned as `{:error, :no_broker}` instead of an exit.

  The exit reason is deliberately not passed on: it embeds the call arguments,
  and those arguments are sometimes her typed words.
  """
  @spec request(String.t(), iodata(), keyword()) :: {:ok, term()} | {:error, term()}
  def request(subject, payload, opts \\ []) do
    transport().request(@connection, subject, payload, opts)
  catch
    :exit, {:noproc, _} -> {:error, :no_broker}
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _reason -> {:error, :broker_exit}
  end

  @doc """
  The module that talks to the connection.

  A test swaps this to drive a screen's read path without a broker, which is the
  only way to test what a screen does with an answer — as opposed to what it does
  with a message the test put in its mailbox itself.
  """
  @spec transport() :: module()
  def transport do
    Application.get_env(@config, :broker_transport, Gnat)
  end
end
