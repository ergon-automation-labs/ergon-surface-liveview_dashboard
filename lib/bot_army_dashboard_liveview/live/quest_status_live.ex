defmodule BotArmyDashboardLiveview.QuestStatusLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        quest: nil,
        next_quest_preview: nil,
        message: nil,
        loading: true
      )
      |> fetch_quest()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_quest(socket) do
    Task.start_link(fn ->
      try do
        case Gnat.request(:nats_connection, "bridge.quest.current", Jason.encode!(%{}),
               timeout: 5000
             ) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, quest} when is_map(quest) ->
                send(self(), {:quest_loaded, quest})

              {:error, _} ->
                send(self(), {:quest_loaded, nil})
            end

          {:error, _} ->
            send(self(), {:quest_loaded, nil})
        end
      rescue
        _ -> send(self(), {:quest_loaded, nil})
      end
    end)

    socket
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info({:quest_loaded, quest}, socket) do
    {:noreply, assign(socket, quest: quest, loading: false)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    if socket.assigns.quest do
      publish_quest_completed(socket, socket.assigns.quest)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  defp publish_quest_completed(socket, quest) do
    Task.start_link(fn ->
      try do
        payload = %{
          "quest_id" => quest["id"],
          "title" => quest["title"],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.quest.completed", Jason.encode!(payload)) do
          :ok ->
            send(self(), {:quest_completed, quest["title"]})

          _ ->
            send(self(), {:quest_publish_failed})
        end
      rescue
        _ -> send(self(), {:quest_publish_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Marking quest complete...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:quest_completed, title}, socket) do
    messages = [
      "✓ #{title} is complete. You did it.",
      "✓ Quest finished: #{title}. What's next?",
      "✓ #{title}. One more thing done.",
      "✓ You finished #{title}. The story moves forward."
    ]

    celebration = Enum.random(messages)

    {:noreply,
     socket
     |> assign(quest: nil, message: celebration)
     |> schedule_message_clear(5000)
     |> then(fn s -> fetch_quest(s) end)}
  end

  @impl true
  def handle_info({:quest_publish_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Could not mark quest complete")
     |> schedule_message_clear(2000)}
  end

  defp schedule_message_clear(socket, delay_ms) do
    Process.send_after(self(), :clear_message, delay_ms)
    socket
  end

  @impl true
  def handle_info(:clear_message, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  defp calculate_progress(quest) when is_map(quest) do
    tasks = quest["tasks"] || []
    completed = Enum.count(tasks, &(&1["completed"] == true))
    total = length(tasks)
    {completed, total}
  end

  defp get_next_task(quest) when is_map(quest) do
    tasks = quest["tasks"] || []
    Enum.find(tasks, fn task -> task["completed"] != true end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="handheld-container quest-status">
      <%= if @loading do %>
        <div class="loading-state">
          <div class="spinner"></div>
          <p>Loading quest...</p>
        </div>
      <% else %>
        <%= if @quest do %>
          <% {completed, total} = calculate_progress(@quest) %>
          <% next_task = get_next_task(@quest) %>
          <% progress_percent = if total > 0, do: div(completed * 100, total), else: 0 %>
          <div class="quest-card">
            <div class="view-title">⚔️ Your Quest</div>

            <div class="quest-header">
              <h1 class="quest-title"><%= @quest["title"] %></h1>
              <p class="quest-description"><%= @quest["description"] || "" %></p>
            </div>

            <div class="progress-section">
              <div class="progress-bar-container">
                <div class="progress-bar-fill" style={"width: #{progress_percent}%"}></div>
              </div>
              <div class="progress-text">
                <%= completed %> of <%= total %> tasks complete
              </div>
            </div>

            <%= if next_task do %>
              <div class="next-task">
                <div class="next-task-label">Next</div>
                <div class="next-task-title"><%= next_task["title"] %></div>
              </div>
            <% end %>

            <div class="controls">
              <%= if completed == total and total > 0 do %>
                <div class="control-hint quest-complete">
                  <span class="key">Y</span>
                  <span class="action">Mark Quest Complete</span>
                </div>
              <% else %>
                <div class="control-hint">
                  <span class="key">Y</span>
                  <span class="action">Work on quest</span>
                </div>
              <% end %>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Back</span>
              </div>
            </div>
          </div>
        <% else %>
          <div class="empty-state">
            <div class="empty-icon">🏁</div>
            <p>No active quest</p>
            <p class="empty-hint">Complete a task to unlock the next chapter</p>
          </div>
        <% end %>
      <% end %>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <style>
      .handheld-container {
        width: 100%;
        height: 100vh;
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        color: #ecf0f1;
        font-family: "Courier New", monospace;
        padding: 20px;
        box-sizing: border-box;
      }

      .quest-card {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #ffd700;
        border-radius: 8px;
        padding: 30px;
        width: 100%;
        max-width: 450px;
        box-shadow: 0 8px 32px rgba(255, 215, 0, 0.1);
      }

      .view-title {
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 20px;
        color: #ffd700;
        text-align: center;
      }

      .quest-header {
        margin-bottom: 30px;
      }

      .quest-title {
        font-size: 28px;
        font-weight: bold;
        margin: 0 0 10px 0;
        color: #ecf0f1;
      }

      .quest-description {
        font-size: 14px;
        color: #b0b0b0;
        margin: 0;
        line-height: 1.4;
      }

      .progress-section {
        margin: 30px 0;
      }

      .progress-bar-container {
        background: rgba(255, 255, 255, 0.1);
        border-radius: 4px;
        height: 20px;
        overflow: hidden;
        margin-bottom: 10px;
      }

      .progress-bar-fill {
        background: linear-gradient(90deg, #ffd700, #ffed4e);
        height: 100%;
        transition: width 0.3s ease;
      }

      .progress-text {
        font-size: 13px;
        color: #b0b0b0;
        text-align: center;
      }

      .next-task {
        background: rgba(255, 215, 0, 0.1);
        border-left: 3px solid #ffd700;
        padding: 15px;
        margin: 20px 0;
        border-radius: 4px;
      }

      .next-task-label {
        font-size: 11px;
        color: #ffd700;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 5px;
      }

      .next-task-title {
        font-size: 16px;
        color: #ecf0f1;
        font-weight: bold;
      }

      .controls {
        margin: 30px 0;
        border-top: 1px solid #333;
        border-bottom: 1px solid #333;
        padding: 20px 0;
      }

      .control-hint {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin: 12px 0;
        font-size: 14px;
      }

      .control-hint.quest-complete {
        color: #ffd700;
      }

      .control-hint .key {
        background: #ffd700;
        color: #1a1a2e;
        padding: 4px 8px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 40px;
        text-align: center;
      }

      .control-hint.quest-complete .key {
        background: #ffed4e;
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .message {
        position: absolute;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(255, 215, 0, 0.2);
        border: 1px solid #ffd700;
        padding: 12px 20px;
        border-radius: 4px;
        font-size: 14px;
        color: #ecf0f1;
        animation: slideUp 0.3s ease;
        max-width: 90%;
        text-align: center;
      }

      @keyframes slideUp {
        from {
          opacity: 0;
          transform: translateX(-50%) translateY(20px);
        }
        to {
          opacity: 1;
          transform: translateX(-50%) translateY(0);
        }
      }

      .empty-state {
        text-align: center;
        color: #a0a0a0;
      }

      .empty-icon {
        font-size: 48px;
        margin-bottom: 20px;
      }

      .empty-state p {
        margin: 10px 0;
        font-size: 16px;
      }

      .empty-hint {
        font-size: 13px;
        color: #707070;
      }

      .loading-state {
        text-align: center;
      }

      .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid #ffd700;
        border-top-color: transparent;
        border-radius: 50%;
        animation: spin 1s linear infinite;
        margin: 0 auto 20px;
      }

      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }
    </style>
    """
  end
end
