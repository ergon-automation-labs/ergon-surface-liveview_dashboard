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
      # Both assigns, not just the message: a screen that names the read that failed
      # reads the tag as well, and a view whose assigns are missing one of them takes
      # the screen down on its first render rather than reporting anything.
      |> assign(:read_error, nil)
      |> assign(:read_failed_tag, nil)
      |> attach_hook(:bot_read, :handle_info, fn
        {:read_started, tag}, socket -> {:halt, BotRead.started(socket, tag)}
        {:read_failed, tag, reason}, socket -> {:halt, report(socket, tag, reason)}
        _message, socket -> {:cont, socket}
      end)

    {:cont, socket}
  end

  # A screen may claim a failed read that is its own errand's: a read this screen asks for as
  # part of a write can say on the act what went unanswered, which is a truer sentence than
  # the page saying the broker is down while the rest of the screen is fine. A screen that
  # claims nothing gets the page-wide report exactly as before, so no view can forget one and
  # none is required to mention `:read_failed`. Hooks attached in `mount/3` cannot do this: the
  # lifecycle runs `handle_info` hooks in the order they were attached, and this one is
  # attached first, in `on_mount`.
  defp report(socket, tag, reason) do
    view = socket.view

    if function_exported?(view, :claim_read_failure, 3) do
      case view.claim_read_failure(tag, reason, socket) do
        {:claimed, %Phoenix.LiveView.Socket{} = claimed} -> claimed
        :default -> BotRead.failed(socket, tag, reason)
      end
    else
      BotRead.failed(socket, tag, reason)
    end
  end
end
