defmodule BotArmyDashboardLiveview.SessionHistoryPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    {:ok, _} = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        state: :overview,
        selected_session_index: 0,
        sessions: [],
        stats: %{},
        message: nil,
        loading: false
      )
      |> load_session_data()
      |> schedule_tick()

    {:ok, socket}
  end

  defp load_session_data(socket) do
    # In a real app, this would query from a backend/database
    # For now, we show the structure for how it would work
    socket
    |> assign(
      sessions: [],
      stats: %{
        "work" => %{count: 0, total_time: 0},
        "habit" => %{count: 0},
        "mood" => %{count: 0},
        "reflection" => %{count: 0}
      }
    )
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.state do
      :overview ->
        {:noreply, socket}

      :sessions ->
        if Enum.empty?(socket.assigns.sessions) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_session_index
          new_idx = max(idx - 1, 0)
          {:noreply, assign(socket, selected_session_index: new_idx)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.state do
      :overview ->
        {:noreply, socket}

      :sessions ->
        if Enum.empty?(socket.assigns.sessions) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_session_index
          new_idx = min(idx + 1, length(socket.assigns.sessions) - 1)
          {:noreply, assign(socket, selected_session_index: new_idx)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.state do
      :overview ->
        {:noreply, assign(socket, state: :sessions, selected_session_index: 0)}

      :sessions ->
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.state do
      :overview ->
        {:noreply, socket}

      :sessions ->
        {:noreply, assign(socket, state: :overview)}

      _ ->
        {:noreply, socket}
    end
  end

  # Touch handlers
  @impl true
  def handle_event("swipe-up", _params, socket) do
    handle_event("gamepad-up", %{}, socket)
  end

  @impl true
  def handle_event("swipe-down", _params, socket) do
    handle_event("gamepad-down", %{}, socket)
  end

  @impl true
  def handle_event("swipe-left", _params, socket) do
    handle_event("gamepad-a", %{}, socket)
  end

  @impl true
  def handle_event("swipe-right", _params, socket) do
    handle_event("gamepad-b", %{}, socket)
  end

  @impl true
  def handle_event("tap", _params, socket) do
    handle_event("gamepad-a", %{}, socket)
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    {:noreply, socket}
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
    <div id="session-history-phone-container" class="handheld-container session-history-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <div class="phone-card session-history-card-phone">
        <div class="view-title">📊 Session History</div>

        <%= case @state do %>
          <% :overview -> %>
            <div class="stats-grid">
              <div class="stat-card work-stat">
                <div class="stat-emoji">⏱️</div>
                <div class="stat-label">Work Sessions</div>
                <div class="stat-value"><%= @stats["work"][:count] || 0 %></div>
              </div>

              <div class="stat-card habit-stat">
                <div class="stat-emoji">✓</div>
                <div class="stat-label">Habits Logged</div>
                <div class="stat-value"><%= @stats["habit"][:count] || 0 %></div>
              </div>

              <div class="stat-card mood-stat">
                <div class="stat-emoji">🌡️</div>
                <div class="stat-label">Moods Checked</div>
                <div class="stat-value"><%= @stats["mood"][:count] || 0 %></div>
              </div>

              <div class="stat-card reflection-stat">
                <div class="stat-emoji">📝</div>
                <div class="stat-label">Reflections</div>
                <div class="stat-value"><%= @stats["reflection"][:count] || 0 %></div>
              </div>
            </div>

            <div class="total-stats">
              <div class="total-item">
                <span class="label">Total Work Time</span>
                <span class="value"><%= format_hours(@stats["work"][:total_time] || 0) %></span>
              </div>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">View Sessions</span>
              </div>
            </div>

          <% :sessions -> %>
            <%= if Enum.empty?(@sessions) do %>
              <div class="empty-state">
                <p>No sessions recorded yet</p>
                <p class="empty-hint">Start a work session, check habits, or log a mood to see history</p>
              </div>
            <% else %>
              <div class="empty-state">
                <p>Session details coming soon</p>
                <p class="empty-hint">Detailed session review will display here</p>
              </div>
            <% end %>

            <div class="controls">
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Back</span>
              </div>
            </div>
        <% end %>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <style>
      .session-history-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .session-history-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #f39c12;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #f39c12;
        text-align: center;
      }

      .stats-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 12px;
        margin: 20px 0;
      }

      .stat-card {
        background: rgba(243, 156, 18, 0.1);
        border: 1px solid rgba(243, 156, 18, 0.3);
        border-radius: 10px;
        padding: 15px;
        text-align: center;
      }

      .stat-card.work-stat {
        border-color: rgba(52, 152, 219, 0.3);
        background: rgba(52, 152, 219, 0.1);
      }

      .stat-card.habit-stat {
        border-color: rgba(39, 174, 96, 0.3);
        background: rgba(39, 174, 96, 0.1);
      }

      .stat-card.mood-stat {
        border-color: rgba(155, 89, 182, 0.3);
        background: rgba(155, 89, 182, 0.1);
      }

      .stat-card.reflection-stat {
        border-color: rgba(107, 127, 215, 0.3);
        background: rgba(107, 127, 215, 0.1);
      }

      .stat-emoji {
        font-size: 28px;
        margin-bottom: 8px;
      }

      .stat-label {
        font-size: 11px;
        color: #b0b0b0;
        margin-bottom: 8px;
      }

      .stat-value {
        font-size: 28px;
        font-weight: bold;
        color: #ecf0f1;
      }

      .total-stats {
        background: rgba(243, 156, 18, 0.15);
        border: 1px solid rgba(243, 156, 18, 0.3);
        border-radius: 8px;
        padding: 15px;
        margin: 15px 0;
      }

      .total-item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 0;
        border-bottom: 1px solid rgba(243, 156, 18, 0.2);
      }

      .total-item:last-child {
        border-bottom: none;
      }

      .total-item .label {
        color: #b0b0b0;
        font-size: 13px;
      }

      .total-item .value {
        color: #f39c12;
        font-weight: bold;
        font-size: 16px;
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

      .control-hint .key {
        background: #f39c12;
        color: #1a1a2e;
        padding: 6px 10px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 45px;
        text-align: center;
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .empty-state {
        text-align: center;
        color: #a0a0a0;
        padding: 30px 0;
      }

      .empty-state p {
        margin: 10px 0;
        font-size: 14px;
      }

      .empty-hint {
        font-size: 12px;
        color: #707070;
      }

      @media (max-width: 768px) {
        .session-history-card-phone {
          padding: 15px;
        }

        .stat-value {
          font-size: 24px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end

  defp format_hours(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp format_hours(_), do: "0h 0m"
end
