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
  """

  @doc """
  `request(subject, payload, opts)`, with an unreachable connection returned as
  `{:error, :no_broker}` instead of an exit.

  The exit reason is deliberately not passed on: it embeds the call arguments,
  and those arguments are sometimes her typed words.
  """
  @spec request(String.t(), iodata(), keyword()) :: {:ok, term()} | {:error, term()}
  def request(subject, payload, opts \\ []) do
    Broker.request(subject, payload, opts)
  rescue
    _ -> {:error, :no_broker}
  catch
    :exit, _reason -> {:error, :no_broker}
    kind, reason -> {:error, {kind, reason}}
  end
end
