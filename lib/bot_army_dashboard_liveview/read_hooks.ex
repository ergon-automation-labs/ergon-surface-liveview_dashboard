defmodule BotArmyDashboardLiveview.ReadHooks do
  @moduledoc """
  Every screen starts with no failed read, and hears about one in one place.

  Attached by the router as an `on_mount` hook over all the live routes, so that
  no view has to carry a `handle_info/2` clause for a failure and none can forget
  one. A view that never mentions `:read_failed` still reports a failed read,
  which is the whole point: the forgetting was systemic.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias BotArmyDashboardLiveview.BotRead

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:read_error, nil)
      |> attach_hook(:bot_read, :handle_info, fn
        {:read_started, tag}, socket -> {:halt, BotRead.started(socket, tag)}
        {:read_failed, tag, reason}, socket -> {:halt, BotRead.failed(socket, tag, reason)}
        _message, socket -> {:cont, socket}
      end)

    {:cont, socket}
  end
end
