defmodule BotArmyDashboardLiveview.QuestPhoneLive do
  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.SyncStatus
  alias BotArmyDashboardLiveview.QuestPayload

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        sync_status: SyncStatus.initial(),
        is_online: true,
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
    # The task runs in its own process, so `self()` inside it is the task, not
    # this LiveView — addressing the result back here has to be explicit, or
    # the view sits on its spinner forever.
    parent = self()

    Task.start_link(fn ->
      result =
        try do
          case Broker.request("bridge.quest.current", Jason.encode!(%{}), timeout: 5000) do
            {:ok, %{body: body}} -> QuestPayload.parse(body)
            {:error, _} -> nil
          end
        rescue
          _ -> nil
        end

      send(parent, {:quest_loaded, result})
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

  # Touch handlers
  @impl true
  def handle_event("tap", _params, socket) do
    handle_event("gamepad-a", %{}, socket)
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("swipe-left", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("swipe-right", _params, socket) do
    {:noreply, socket}
  end

  defp publish_quest_completed(socket, quest) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{
          "quest_id" => quest["id"],
          "title" => quest["title"],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.quest.completed", Jason.encode!(payload)) do
          :ok ->
            send(parent, {:quest_completed, quest["title"]})

          _ ->
            send(parent, {:quest_publish_failed})
        end
      rescue
        _ -> send(parent, {:quest_publish_failed})
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
  def handle_event("sync-queue-online", _params, socket) do
    {:noreply, assign(socket, is_online: true)}
  end

  @impl true
  def handle_event("sync-queue-offline", _params, socket) do
    {:noreply, assign(socket, is_online: false)}
  end

  @impl true
  def handle_event("sync-status-update", %{"status" => status}, socket) do
    {:noreply, assign(socket, sync_status: status)}
  end

  @impl true
  def handle_event("sync-queue-retry", _params, socket) do
    BotArmyDashboardLiveview.OfflineQueue.flush_queue(
      socket.assigns.socket_id,
      fn subject, payload ->
        Gnat.pub(:nats_connection, subject, payload)
      end
    )

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="quest-phone-container" class="handheld-container quest-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
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
          <div class="phone-card quest-card-phone">
            <div class="view-title">⚔️ Your Quest</div>

            <div class="quest-header-phone">
              <h1 class="quest-title-phone"><%= @quest["title"] %></h1>
              <%= if @quest["description"] && String.trim(@quest["description"]) != "" do %>
                <p class="quest-description-phone"><%= @quest["description"] %></p>
              <% end %>
            </div>

            <div class="progress-section-phone">
              <div class="progress-label">Progress</div>
              <div class="progress-bar-container-phone">
                <div class="progress-bar-fill-phone" style={"width: #{progress_percent}%"}></div>
              </div>
              <div class="progress-text-phone">
                <%= completed %> of <%= total %> tasks
              </div>
            </div>

            <%= if next_task do %>
              <div class="next-task-card">
                <div class="next-task-label">What's Next</div>
                <div class="next-task-title-phone"><%= next_task["title"] %></div>
              </div>
            <% end %>

            <div class="controls">
              <%= if completed == total and total > 0 do %>
                <div class="control-hint quest-ready">
                  <span class="key">Y</span>
                  <span class="action">Quest Complete!</span>
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

    <PhoneNav.nav current_route="/quest-phone" />

    <style>
      .quest-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .quest-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #ffd700;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #ffd700;
        text-align: center;
      }

      .quest-header-phone {
        margin-bottom: 25px;
      }

      .quest-title-phone {
        font-size: 28px;
        font-weight: bold;
        margin: 0 0 10px 0;
        color: #ecf0f1;
        word-wrap: break-word;
      }

      .quest-description-phone {
        font-size: 13px;
        color: #b0b0b0;
        margin: 0;
        line-height: 1.5;
      }

      .progress-section-phone {
        margin: 25px 0;
      }

      .progress-label {
        font-size: 12px;
        color: #ffd700;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 8px;
      }

      .progress-bar-container-phone {
        background: rgba(255, 255, 255, 0.1);
        border-radius: 6px;
        height: 24px;
        overflow: hidden;
        margin-bottom: 10px;
        border: 1px solid rgba(255, 215, 0, 0.3);
      }

      .progress-bar-fill-phone {
        background: linear-gradient(90deg, #ffd700, #ffed4e);
        height: 100%;
        transition: width 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
        box-shadow: 0 0 10px rgba(255, 215, 0, 0.5);
      }

      .progress-text-phone {
        font-size: 12px;
        color: #b0b0b0;
        text-align: center;
      }

      .next-task-card {
        background: rgba(255, 215, 0, 0.1);
        border-left: 4px solid #ffd700;
        padding: 15px;
        margin: 20px 0;
        border-radius: 6px;
      }

      .next-task-label {
        font-size: 11px;
        color: #ffd700;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 8px;
      }

      .next-task-title-phone {
        font-size: 16px;
        color: #ecf0f1;
        font-weight: bold;
      }

      .controls {
        display: flex;
        flex-direction: column;
        gap: 8px;
        border-top: 1px solid #333;
        border-bottom: 1px solid #333;
        padding: 15px 0;
        margin: 20px 0;
      }

      .control-hint {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px;
        font-size: 13px;
        min-height: 44px;
      }

      .control-hint.quest-ready {
        color: #ffd700;
      }

      .control-hint .key {
        background: #ffd700;
        color: #1a1a2e;
        padding: 6px 10px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 45px;
        text-align: center;
      }

      .control-hint.quest-ready .key {
        background: #ffed4e;
        box-shadow: 0 0 10px rgba(255, 215, 0, 0.5);
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .message {
        position: fixed;
        bottom: 20px;
        left: 10px;
        right: 10px;
        background: rgba(255, 215, 0, 0.2);
        border: 1px solid #ffd700;
        padding: 12px;
        border-radius: 4px;
        color: #ecf0f1;
        text-align: center;
        font-size: 13px;
        animation: slideUp 0.3s ease;
      }

      @keyframes slideUp {
        from {
          opacity: 0;
          transform: translateY(20px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
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
        font-size: 12px;
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

      @media (max-width: 768px) {
        .quest-card-phone {
          padding: 15px;
        }

        .quest-title-phone {
          font-size: 24px;
        }

        .progress-bar-container-phone {
          height: 20px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
