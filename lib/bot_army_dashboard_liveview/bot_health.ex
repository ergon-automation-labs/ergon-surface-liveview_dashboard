defmodule BotArmyDashboardLiveview.BotHealth do
  @moduledoc """
  What the registry's answer says about a bot, in the terms the screens show.

  The registry answers with what it knows — a name, a last heartbeat, the
  subjects a bot serves — and not with a verdict. The verdict is derived here,
  once, so that the handheld and the phone cannot disagree about whether the
  same bot is up.
  """

  # A heartbeat this recent is a bot that is running now; older than that and it
  # is either between beats or gone. The windows are the registry's own pulse
  # period (30s) and a generous multiple of it.
  @healthy_window_seconds 30
  @idle_window_seconds 300

  @spec derive_status(map()) :: :healthy | :idle | :offline
  def derive_status(bot) do
    case bot["last_heartbeat"] do
      heartbeat when is_binary(heartbeat) -> status_from_heartbeat(heartbeat)
      _other -> :offline
    end
  end

  defp status_from_heartbeat(heartbeat) do
    case DateTime.from_iso8601(heartbeat) do
      {:ok, beat_at, _offset} ->
        seconds_ago = DateTime.diff(DateTime.utc_now(), beat_at, :second)

        cond do
          seconds_ago < @healthy_window_seconds -> :healthy
          seconds_ago < @idle_window_seconds -> :idle
          true -> :offline
        end

      _other ->
        :offline
    end
  end

  @doc """
  The status as the phone screens spell it.

  Their badges are CSS-classed by these words, so the derivation has to arrive
  as one of them rather than as an atom of its own.
  """
  @spec status_word(atom()) :: String.t()
  def status_word(:healthy), do: "healthy"
  def status_word(:idle), do: "degraded"
  def status_word(:offline), do: "unhealthy"
  def status_word(_other), do: "unknown"

  @spec status_emoji(atom()) :: String.t()
  def status_emoji(:healthy), do: "✓"
  def status_emoji(:idle), do: "⏸"
  def status_emoji(:offline), do: "✗"
  def status_emoji(_other), do: "?"

  @doc """
  A heartbeat as a person reads it: "now", "5m ago" — never a raw timestamp.

  A bot that has never reported one says so, rather than rendering an empty
  space that reads as a bug in the screen.
  """
  @spec format_heartbeat(nil | String.t() | term()) :: String.t()
  def format_heartbeat(nil), do: "No heartbeat"

  def format_heartbeat(heartbeat) when is_binary(heartbeat) do
    case DateTime.from_iso8601(heartbeat) do
      {:ok, beat_at, _offset} ->
        seconds_ago = DateTime.diff(DateTime.utc_now(), beat_at, :second)

        cond do
          seconds_ago < 60 -> "now"
          seconds_ago < 3600 -> "#{div(seconds_ago, 60)}m ago"
          seconds_ago < 86_400 -> "#{div(seconds_ago, 3600)}h ago"
          true -> "#{div(seconds_ago, 86_400)}d ago"
        end

      _other ->
        "unknown"
    end
  end

  def format_heartbeat(_other), do: "unknown"
end
