defmodule BotArmyDashboardLiveview.HabitAnchorsLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    {:ok, _} = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        habits: [],
        selected_habit_index: 0,
        message: nil,
        loading: true
      )
      |> fetch_habits()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_habits(socket) do
    Task.start_link(fn ->
      try do
        case Gnat.request(:nats_connection, "bridge.habit.list", Jason.encode!(%{}),
               timeout: 5000
             ) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"habits" => habits}} ->
                send(self(), {:habits_loaded, habits})

              {:ok, habits} when is_list(habits) ->
                send(self(), {:habits_loaded, habits})

              {:error, _} ->
                send(self(), {:habits_loaded, []})
            end

          {:error, _} ->
            send(self(), {:habits_loaded, []})
        end
      rescue
        _ -> send(self(), {:habits_loaded, []})
      end
    end)

    socket
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info({:habits_loaded, habits}, socket) do
    {:noreply, assign(socket, habits: habits, loading: false, selected_habit_index: 0)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    if Enum.empty?(socket.assigns.habits) do
      {:noreply, socket}
    else
      habits = socket.assigns.habits
      idx = socket.assigns.selected_habit_index
      new_idx = max(idx - 1, 0)
      {:noreply, assign(socket, selected_habit_index: new_idx, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    if Enum.empty?(socket.assigns.habits) do
      {:noreply, socket}
    else
      habits = socket.assigns.habits
      idx = socket.assigns.selected_habit_index
      new_idx = min(idx + 1, length(habits) - 1)
      {:noreply, assign(socket, selected_habit_index: new_idx, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    habit = Enum.at(socket.assigns.habits, socket.assigns.selected_habit_index)

    if habit do
      publish_habit_check_in(socket, habit)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  defp publish_habit_check_in(socket, habit) do
    Task.start_link(fn ->
      try do
        payload = %{
          "habit_id" => habit["id"],
          "name" => habit["name"],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.habit.check_in", Jason.encode!(payload)) do
          :ok ->
            send(self(), {:habit_checked_in, habit["name"]})

          _ ->
            send(self(), {:check_in_failed})
        end
      rescue
        _ -> send(self(), {:check_in_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Checking in...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:habit_checked_in, name}, socket) do
    {:noreply,
     socket
     |> assign(message: "✓ #{name} checked in")
     |> schedule_message_clear(3000)}
  end

  @impl true
  def handle_info({:check_in_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Check-in failed")
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="handheld-container habit-anchors">
      <%= if @loading do %>
        <div class="loading-state">
          <div class="spinner"></div>
          <p>Loading habits...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@habits) do %>
          <div class="empty-state">
            <p>No habits configured yet</p>
          </div>
        <% else %>
          <% current_habit = Enum.at(@habits, @selected_habit_index) %>
          <div class="habit-card">
            <div class="view-title">✓ Check In</div>

            <div class="habit-display">
              <div class="habit-name"><%= current_habit["name"] %></div>
              <div class="habit-category"><%= current_habit["category"] || "anchor" %></div>
            </div>

            <div class="habit-question">
              <p>Done today?</p>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">↑ ↓</span>
                <span class="action">Browse</span>
              </div>
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Check In</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Skip</span>
              </div>
            </div>

            <div class="progress-hint">
              <%= @selected_habit_index + 1 %> of <%= length(@habits) %>
            </div>
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

      .habit-card {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #00d4ff;
        border-radius: 8px;
        padding: 30px;
        width: 100%;
        max-width: 400px;
        box-shadow: 0 8px 32px rgba(0, 212, 255, 0.1);
      }

      .view-title {
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 20px;
        color: #00d4ff;
        text-align: center;
      }

      .habit-display {
        text-align: center;
        margin: 30px 0;
      }

      .habit-name {
        font-size: 32px;
        font-weight: bold;
        margin-bottom: 10px;
        color: #ecf0f1;
      }

      .habit-category {
        font-size: 14px;
        color: #b0b0b0;
        text-transform: uppercase;
        letter-spacing: 2px;
      }

      .habit-question {
        text-align: center;
        margin: 20px 0;
        font-size: 18px;
        color: #a0a0a0;
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

      .control-hint .key {
        background: #00d4ff;
        color: #1a1a2e;
        padding: 4px 8px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 40px;
        text-align: center;
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .progress-hint {
        text-align: center;
        font-size: 12px;
        color: #707070;
        margin-top: 20px;
      }

      .message {
        position: absolute;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(0, 212, 255, 0.2);
        border: 1px solid #00d4ff;
        padding: 12px 20px;
        border-radius: 4px;
        font-size: 14px;
        color: #ecf0f1;
        animation: slideUp 0.3s ease;
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

      .loading-state {
        text-align: center;
      }

      .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid #00d4ff;
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
