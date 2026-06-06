defmodule BotArmyDashboardLiveview.DashboardLive do
  @moduledoc """
  Real-time Bot Army dashboard showing:
  - Live task feed (completions, creations, updates)
  - Decompositions in progress
  - Bot health status
  - Quick stats (tasks today, etc)
  """

  use Phoenix.LiveView
  require Logger

  alias Phoenix.PubSub

  def mount(_params, _session, socket) do
    # Subscribe to PubSub channels
    PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:tasks")
    PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:decompositions")
    PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:health")
    PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:presence")

    {:ok,
     assign(socket,
       task_feed: [],
       decompositions: [],
       bot_health: %{},
       stats: %{
         tasks_today: 0,
         completed_today: 0,
         in_progress: 0,
         blocked: 0
       },
       nats_connected: check_nats_connection()
     )}
  end

  def handle_info({:task_event, subject, event}, socket) do
    task_feed = [
      %{
        type: extract_task_event_type(subject),
        title: event["payload"]["title"] || "Unknown task",
        timestamp: event["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601(),
        duration: event["payload"]["duration_minutes"]
      }
      | Enum.take(socket.assigns.task_feed, 19)
    ]

    {:noreply, assign(socket, :task_feed, task_feed)}
  end

  def handle_info({:decomposition_event, subject, event}, socket) do
    decomposition = %{
      type: extract_decomposition_event_type(subject),
      subtask_count: length(event["payload"]["subtasks"] || []),
      timestamp: event["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601(),
      status: event["payload"]["status"]
    }

    decompositions = [decomposition | Enum.take(socket.assigns.decompositions, 9)]

    {:noreply, assign(socket, :decompositions, decompositions)}
  end

  def handle_info({:health_event, subject, event}, socket) do
    bot_name = String.split(subject, ".") |> Enum.at(-1)

    health = %{
      status: event["payload"]["status"] || "unknown",
      timestamp: event["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601()
    }

    bot_health = Map.put(socket.assigns.bot_health, bot_name, health)

    {:noreply, assign(socket, :bot_health, bot_health)}
  end

  def handle_info({:presence_event, _subject, _event}, socket) do
    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

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
          background: #080c1a;
          border-left: 3px solid #00ff88;
          margin-bottom: 10px;
          border-radius: 4px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 13px;
        }

        .feed-title {
          flex: 1;
          color: #e0e0e0;
        }

        .feed-time {
          color: #666;
          font-size: 12px;
          margin-left: 10px;
        }

        .event-badge {
          display: inline-block;
          padding: 4px 8px;
          background: #1a3a1a;
          color: #00ff88;
          border-radius: 4px;
          font-size: 11px;
          font-weight: 500;
          margin-right: 10px;
        }

        .decomposition-item {
          padding: 12px;
          background: #080c1a;
          border-left: 3px solid #4488ff;
          margin-bottom: 10px;
          border-radius: 4px;
          font-size: 13px;
        }

        .bot-status {
          display: inline-block;
          padding: 6px 12px;
          background: #1a3a1a;
          color: #00ff88;
          border-radius: 4px;
          font-size: 12px;
          margin-right: 10px;
          margin-bottom: 8px;
        }

        .bot-status.offline {
          background: #3a1a1a;
          color: #ff4444;
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
            🔴 NATS Disconnected
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
            <p>No task events yet. Complete a task to see it here.</p>
          </div>
        <% else %>
          <%= for item <- @task_feed do %>
            <div class="feed-item">
              <span class="event-badge"><%= item.type %></span>
              <span class="feed-title"><%= item.title %></span>
              <%= if item.duration do %>
                <span class="feed-time"><%= item.duration %>m</span>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="section">
        <div class="section-title">🔄 Decompositions in Progress</div>
        <%= if Enum.empty?(@decompositions) do %>
          <div class="empty-state">
            <div class="emoji">🎲</div>
            <p>No decompositions yet. Break down a complex goal to see it here.</p>
          </div>
        <% else %>
          <%= for decomp <- @decompositions do %>
            <div class="decomposition-item">
              <strong><%= decomp.type %></strong> • <%= decomp.subtask_count %> subtasks
              <div class="feed-time" style="margin-top: 4px;"><%= format_time(decomp.timestamp) %></div>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="section">
        <div class="section-title">🤖 Bot Health</div>
        <%= if Enum.empty?(@bot_health) do %>
          <div class="empty-state">
            <div class="emoji">💤</div>
            <p>No bot health events yet. Bots will appear as they report status.</p>
          </div>
        <% else %>
          <%= for {bot_name, health} <- @bot_health do %>
            <div class={"bot-status" <> if health.status == "healthy", do: "", else: " offline"}>
              <%= bot_name %>: <%= health.status %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Private

  defp extract_task_event_type(subject) do
    case String.split(subject, ".") do
      ["events", "gtd", "task", type] -> String.capitalize(type)
      _ -> "task"
    end
  end

  defp extract_decomposition_event_type(subject) do
    case String.split(subject, ".") do
      ["events", "gtd", "decomposition", type] -> String.capitalize(type)
      _ -> "decomposition"
    end
  end

  defp format_time(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, dt, :second)

        cond do
          diff < 60 -> "#{diff}s ago"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          true -> "#{div(diff, 86400)}d ago"
        end

      :error ->
        "recently"
    end
  end

  defp check_nats_connection do
    case GenServer.whereis(:nats_connection) do
      nil -> false
      _pid -> true
    end
  end
end
