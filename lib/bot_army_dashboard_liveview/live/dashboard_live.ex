defmodule BotArmyDashboardLiveview.DashboardLive do
  use Phoenix.LiveView
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    try do
      Logger.info("[DashboardLive] Mounting...")

      # Subscribe to NATS bridge status and events
      Logger.debug("[DashboardLive] Subscribing to dashboard channels")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:status")
      Logger.debug("[DashboardLive] Subscribed to dashboard:status")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:tasks")
      Logger.debug("[DashboardLive] Subscribed to dashboard:tasks")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:decompositions")
      Logger.debug("[DashboardLive] Subscribed to dashboard:decompositions")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:health")
      Logger.debug("[DashboardLive] Subscribed to dashboard:health")
      Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:presence")
      Logger.debug("[DashboardLive] Subscribed to dashboard:presence")

      # Query current NATS connection status
      Logger.debug("[DashboardLive] Querying NATS status")
      nats_status = BotArmyDashboardLiveview.NATSBridge.get_status()

      # Query current tasks from bridge
      Logger.debug("[DashboardLive] Querying tasks from bridge")
      tasks = BotArmyDashboardLiveview.NATSBridge.get_tasks()

      # Schedule periodic task refresh (every 5 seconds)
      Process.send_after(self(), :refresh_tasks, 5000)

      # Query completed tasks for learning capture
      completed_tasks = BotArmyDashboardLiveview.NATSBridge.get_completed_tasks()

      # Initial state
      {:ok,
       assign(socket,
         nats_connected: nats_status,
         task_feed: Enum.filter(tasks, fn t -> t["status"] != "completed" end),
         completed_tasks: completed_tasks,
         decompositions: [],
         bot_health: %{},
         learning_focused_task: nil,
         learning_form: %{
           "what_learned" => "",
           "key_insights" => "",
           "mistakes_made" => "",
           "difficulty_level" => "medium",
           "tags" => ""
         },
         stats: %{
           tasks_today: Enum.count(tasks),
           completed_today: Enum.count(completed_tasks),
           in_progress: Enum.count(Enum.filter(tasks, fn t -> t["status"] != "completed" end)),
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
          <%= for task <- @task_feed do %>
            <div class="feed-item">
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <span><strong><%= task["title"] || "Unnamed task" %></strong></span>
                <span style="font-size: 12px; color: #888;">
                  <%= if task["priority"] == "high", do: "🔴", else: (if task["priority"] == "low", do: "🟢", else: "🟡") %>
                </span>
              </div>
              <% if task["description"] do %>
                <div style="font-size: 13px; color: #aaa; margin-top: 4px;"><%= String.slice(task["description"], 0..80) %></div>
              <% end %>
              <div class="feed-item-time"><%= format_time(task["created_at"]) %> ago</div>
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
        <div class="section-title">📚 Learning Capture</div>
        <%= if Enum.empty?(@completed_tasks) do %>
          <div class="empty-state">
            <div class="emoji">🎓</div>
            <p>No completed tasks to review. Complete a task to capture learnings!</p>
          </div>
        <% else %>
          <%= for task <- Enum.take(@completed_tasks, 10) do %>
            <div class="feed-item" style="cursor: pointer; border-left: 3px solid #4CAF50;" phx-click="open_learning_form" phx-value-task_id={task["id"]}>
              <div style="display: flex; justify-content: space-between; align-items: start;">
                <div style="flex: 1;">
                  <span><strong><%= task["title"] %></strong></span>
                  <div style="font-size: 12px; color: #888; margin-top: 4px;">
                    Completed <%= format_time(task["completed_at"]) %> ago
                  </div>
                </div>
                <span style="font-size: 12px; background: #2d5a2d; padding: 4px 8px; border-radius: 3px; margin-left: 10px;">
                  Capture learning
                </span>
              </div>
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
      <%= if @learning_focused_task do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 1000;">
          <div style="background: #0f1535; border: 1px solid #1e2749; border-radius: 8px; padding: 30px; width: 90%; max-width: 600px;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
              <h2 style="color: #00ff88; margin: 0; font-size: 20px;">📚 Learning from: <%= @learning_focused_task["title"] %></h2>
              <button phx-click="close_learning_form" style="background: none; border: none; color: #888; font-size: 24px; cursor: pointer;">×</button>
            </div>

            <div style="margin-bottom: 15px;">
              <label style="display: block; color: #aaa; font-size: 12px; margin-bottom: 5px; text-transform: uppercase;">What did you learn?</label>
              <textarea phx-change="update_learning_field" phx-value-field="what_learned" value={@learning_form["what_learned"]} style="width: 100%; height: 80px; background: #1a3a1a; color: #00ff88; border: 1px solid #1e2749; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 13px; resize: vertical;" placeholder="Key takeaways, skills gained, understanding deepened..."></textarea>
            </div>

            <div style="margin-bottom: 15px;">
              <label style="display: block; color: #aaa; font-size: 12px; margin-bottom: 5px; text-transform: uppercase;">Key insights</label>
              <textarea phx-change="update_learning_field" phx-value-field="key_insights" value={@learning_form["key_insights"]} style="width: 100%; height: 60px; background: #1a3a1a; color: #00ff88; border: 1px solid #1e2749; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 13px; resize: vertical;" placeholder="Patterns, principles, surprising discoveries..."></textarea>
            </div>

            <div style="margin-bottom: 15px;">
              <label style="display: block; color: #aaa; font-size: 12px; margin-bottom: 5px; text-transform: uppercase;">Mistakes / what to avoid</label>
              <textarea phx-change="update_learning_field" phx-value-field="mistakes_made" value={@learning_form["mistakes_made"]} style="width: 100%; height: 60px; background: #1a3a1a; color: #00ff88; border: 1px solid #1e2749; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 13px; resize: vertical;" placeholder="What went wrong, gotchas, edge cases..."></textarea>
            </div>

            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 15px;">
              <div>
                <label style="display: block; color: #aaa; font-size: 12px; margin-bottom: 5px; text-transform: uppercase;">Difficulty</label>
                <select phx-change="update_learning_field" phx-value-field="difficulty_level" value={@learning_form["difficulty_level"]} style="width: 100%; background: #1a3a1a; color: #00ff88; border: 1px solid #1e2749; padding: 8px; border-radius: 4px; font-size: 13px;">
                  <option value="easy">Easy</option>
                  <option value="medium">Medium</option>
                  <option value="hard">Hard</option>
                </select>
              </div>
              <div>
                <label style="display: block; color: #aaa; font-size: 12px; margin-bottom: 5px; text-transform: uppercase;">Tags (comma-separated)</label>
                <input type="text" phx-change="update_learning_field" phx-value-field="tags" value={@learning_form["tags"]} style="width: 100%; background: #1a3a1a; color: #00ff88; border: 1px solid #1e2749; padding: 8px; border-radius: 4px; font-size: 13px;" placeholder="elixir, debugging, architecture...">
              </div>
            </div>

            <div style="display: flex; gap: 10px; justify-content: flex-end;">
              <button phx-click="close_learning_form" style="background: #2a2a2a; color: #aaa; border: 1px solid #1e2749; padding: 10px 20px; border-radius: 4px; cursor: pointer; font-size: 13px;">Cancel</button>
              <button phx-click="submit_learning" style="background: #00ff88; color: #000; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; font-size: 13px; font-weight: bold;">Save Learning</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_info({:status_update, status}, socket) do
    Logger.debug("[DashboardLive] Status update: #{status}")
    {:noreply, assign(socket, nats_connected: status)}
  end

  def handle_info({:task_event, subject, event}, socket) do
    Logger.debug("[DashboardLive] Task event from #{subject}: #{inspect(event, limit: 50)}")
    new_feed = [event | socket.assigns.task_feed] |> Enum.take(20)
    {:noreply, assign(socket, task_feed: new_feed)}
  end

  def handle_info({:decomposition_event, subject, event}, socket) do
    Logger.debug("[DashboardLive] Decomposition event from #{subject}")
    new_decomps = [event | socket.assigns.decompositions] |> Enum.take(10)
    {:noreply, assign(socket, decompositions: new_decomps)}
  end

  def handle_info({:health_event, subject, event}, socket) do
    Logger.debug("[DashboardLive] Health event from #{subject}")
    bot_name = event["bot_name"] || "unknown"
    new_health = Map.put(socket.assigns.bot_health, bot_name, event)
    {:noreply, assign(socket, bot_health: new_health)}
  end

  def handle_info({:presence_event, _subject, _event}, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh_tasks, socket) do
    Logger.debug("[DashboardLive] Refreshing tasks from bridge")

    tasks = BotArmyDashboardLiveview.NATSBridge.get_tasks()
    completed = BotArmyDashboardLiveview.NATSBridge.get_completed_tasks()
    active = tasks

    # Schedule next refresh
    Process.send_after(self(), :refresh_tasks, 5000)

    {:noreply,
     assign(socket,
       task_feed: active,
       completed_tasks: completed,
       stats: %{
         tasks_today: Enum.count(tasks),
         completed_today: Enum.count(completed),
         in_progress: Enum.count(active),
         blocked: 0
       }
     )}
  end

  def handle_event("open_learning_form", %{"task_id" => task_id}, socket) do
    task = Enum.find(socket.assigns.completed_tasks, fn t -> t["id"] == task_id end)

    {:noreply,
     assign(socket,
       learning_focused_task: task,
       learning_form: %{
         "what_learned" => "",
         "key_insights" => "",
         "mistakes_made" => "",
         "difficulty_level" => "medium",
         "tags" => ""
       }
     )}
  end

  def handle_event("close_learning_form", _params, socket) do
    {:noreply, assign(socket, learning_focused_task: nil)}
  end

  def handle_event("update_learning_field", %{"field" => field, "value" => value}, socket) do
    form = Map.put(socket.assigns.learning_form, field, value)
    {:noreply, assign(socket, learning_form: form)}
  end

  def handle_event("submit_learning", _params, socket) do
    if socket.assigns.learning_focused_task do
      task = socket.assigns.learning_focused_task
      form = socket.assigns.learning_form

      # Send learning to NATS for storage + LLM processing
      learning_event = %{
        task_id: task["id"],
        task_title: task["title"],
        what_learned: form["what_learned"],
        key_insights: form["key_insights"],
        mistakes_made: form["mistakes_made"],
        difficulty_level: form["difficulty_level"],
        tags:
          String.split(form["tags"], ",") |> Enum.map(&String.trim/1) |> Enum.filter(&(&1 != "")),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Publish to NATS for learning bot to process
      try do
        :nats_connection
        |> GenServer.whereis()
        |> then(fn pid ->
          if pid do
            Gnat.pub(
              pid,
              "events.learning.captured",
              Jason.encode!(learning_event)
            )
          end
        end)
      rescue
        _ -> :ok
      end

      Logger.info("[DashboardLive] Learning captured: #{task["title"]}")

      {:noreply,
       assign(socket,
         learning_focused_task: nil,
         completed_tasks:
           Enum.filter(socket.assigns.completed_tasks, fn t ->
             t["id"] != task["id"]
           end)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(msg, socket) do
    Logger.debug("[DashboardLive] Received unknown message: #{inspect(msg, limit: 50)}")
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
