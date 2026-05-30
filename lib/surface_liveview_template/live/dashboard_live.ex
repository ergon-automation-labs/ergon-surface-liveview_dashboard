defmodule SurfaceLiveviewTemplate.DashboardLive do
  @moduledoc """
  Sample LiveView. Copy and adapt for your surface; mount it in the router
  with a proper LiveView socket (see Phoenix LiveView installation).
  """
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:items, [])

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <h1><%= @page_title %></h1>
      <%= if length(@items) == 0 do %>
        <p class="empty-state">No items yet — connect NATS or add data from your bot.</p>
      <% else %>
        <ul>
          <%= for item <- @items do %>
            <li><%= item %></li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end
end
