defmodule BotArmyDashboardLiveview.DashboardLive do
  use Phoenix.LiveView
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    try do
      # Subscribe to NATS bridge status and events
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:status")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:tasks")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:decompositions")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:health")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:presence")

      # Query current NATS connection status
      nats_status = BotArmyDashboardLiveview.NATSBridge.get_status()

      # Initial state
      {:ok,
       assign(socket,
         nats_connected: nats_status,
         task_feed: [],
         decompositions: [],
         bot_health: %{},
         stats: %{
           tasks_today: 0,
           completed_today: 0,
           in_progress: 0,
           blocked: 0
         }
       )}
    rescue
      error ->
        Logger.error("[DashboardLive] Mount error: #{inspect(error)}")

        {:ok,
         assign(socket,
           nats_connected: false,
           task_feed: [],
           decompositions: [],
           bot_health: %{},
           stats: %{tasks_today: 0, completed_today: 0, in_progress: 0, blocked: 0}
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <style>
        .dashboard {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          max-width: 1400px;
          margin: 0 auto;
          padding: 20px;
          background: #0a0e27;
          color: #e0e0e0;
          min-height: 100vh;
        }

        .header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 30px;
          border-bottom: 1px solid #1e2749;
          padding-bottom: 20px;
        }

        .title {
          font-size: 28px;
          font-weight: bold;
          color: #00ff88;
        }

        .nats-status {
          padding: 8px 16px;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 500;
          background: #1a3a1a;
          color: #00ff88;
        }

        .nats-status.disconnected {
          background: #3a1a1a;
          color: #ff4444;
        }

        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 20px;
          margin-bottom: 30px;
        }

        .stat-card {
          background: #0f1535;
          border: 1px solid #1e2749;
          padding: 20px;
          border-radius: 8px;
          text-align: center;
        }

        .stat-label {
          font-size: 12px;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 10px;
        }

        .stat-value {
          font-size: 32px;
          font-weight: bold;
          color: #00ff88;
        }

        .section {
          background: #0f1535;
          border: 1px solid #1e2749;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 20px;
        }

        .section-title {
          font-size: 16px;
          font-weight: bold;
          color: #00ff88;
          margin-bottom: 15px;
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .feed-item {
          padding: 12px;
          border-bottom: 1px solid #1e2749;
          font-size: 14px;
        }

        .feed-item:last-child {
          border-bottom: none;
        }

        .feed-item-time {
          font-size: 11px;
          color: #666;
          margin-top: 4px;
        }

        .empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #666;
        }

        .emoji {
          font-size: 24px;
          margin-bottom: 10px;
        }
      </style>

      <div class="header">
        <div class="title">⚙️ Bot Army Dashboard</div>
        <div class={"nats-status" <> if @nats_connected, do: "", else: " disconnected"}>
          <%= if @nats_connected do %>
            🟢 NATS Connected
          <% else %>
            🔴 NATS Connecting...
          <% end %>
        </div>
      </div>

      <div class="grid">
        <div class="stat-card">
          <div class="stat-label">Tasks Today</div>
          <div class="stat-value"><%= @stats.tasks_today %></div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Completed</div>
          <div class="stat-value"><%= @stats.completed_today %></div>
        </div>
        <div class="stat-card">
          <div class="stat-label">In Progress</div>
          <div class="stat-value"><%= @stats.in_progress %></div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Blocked</div>
          <div class="stat-value"><%= @stats.blocked %></div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">📋 Live Task Feed</div>
        <%= if Enum.empty?(@task_feed) do %>
          <div class="empty-state">
            <div class="emoji">🎯</div>
            <p>No tasks yet. Tasks will appear here as they are created.</p>
          </div>
        <% else %>
          <%= for item <- @task_feed do %>
            <div class="feed-item">
              <span><strong><%= item["title"] || "Unnamed task" %></strong></span>
              <div class="feed-item-time"><%= format_time(item["timestamp"]) %> ago</div>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="section">
        <div class="section-title">🔄 Decompositions in Progress</div>
        <%= if Enum.empty?(@decompositions) do %>
          <div class="empty-state">
            <div class="emoji">📝</div>
            <p>No active decompositions. Complex tasks will show here when being broken down.</p>
          </div>
        <% else %>
          <%= for item <- @decompositions do %>
            <div class="feed-item">
              <span><strong><%= item["title"] || "Decomposition" %></strong></span>
              <div class="feed-item-time"><%= format_time(item["timestamp"]) %> ago</div>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="section">
        <div class="section-title">💚 Bot Health</div>
        <%= if Enum.empty?(@bot_health) do %>
          <div class="empty-state">
            <div class="emoji">💤</div>
            <p>No bot health events yet. Bots will appear as they report status.</p>
          </div>
        <% else %>
          <%= for {bot_name, health} <- @bot_health do %>
            <div class="feed-item">
              <%= bot_name %>: <strong><%= health["status"] %></strong>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:status_update, status}, socket) do
    {:noreply, assign(socket, nats_connected: status)}
  end

  def handle_info({:task_event, _subject, event}, socket) do
    new_feed = [event | socket.assigns.task_feed] |> Enum.take(20)
    {:noreply, assign(socket, task_feed: new_feed)}
  end

  def handle_info({:decomposition_event, _subject, event}, socket) do
    new_decomps = [event | socket.assigns.decompositions] |> Enum.take(10)
    {:noreply, assign(socket, decompositions: new_decomps)}
  end

  def handle_info({:health_event, _subject, event}, socket) do
    bot_name = event["bot_name"] || "unknown"
    new_health = Map.put(socket.assigns.bot_health, bot_name, event)
    {:noreply, assign(socket, bot_health: new_health)}
  end

  def handle_info({:presence_event, _subject, _event}, socket) do
    {:noreply, socket}
  end

  defp format_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        seconds_ago = DateTime.diff(DateTime.utc_now(), dt)
        format_duration(seconds_ago)

      _ ->
        "recently"
    end
  end

  defp format_time(_), do: "recently"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_duration(seconds) when seconds < 86400, do: "#{div(seconds, 3600)}h"
  defp format_duration(seconds), do: "#{div(seconds, 86400)}d"
end
