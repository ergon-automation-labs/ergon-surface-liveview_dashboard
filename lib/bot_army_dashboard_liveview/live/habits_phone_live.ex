defmodule BotArmyDashboardLiveview.HabitsPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  import BotArmyDashboardLiveview.PhoneNav

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

  # Touch handlers
  @impl true
  def handle_event("swipe-left", _params, socket) do
    if Enum.empty?(socket.assigns.habits) do
      {:noreply, socket}
    else
      habits = socket.assigns.habits
      idx = socket.assigns.selected_habit_index
      new_idx = min(idx + 1, length(habits) - 1)
      {:noreply, assign(socket, selected_habit_index: new_idx)}
    end
  end

  @impl true
  def handle_event("swipe-right", _params, socket) do
    if Enum.empty?(socket.assigns.habits) do
      {:noreply, socket}
    else
      habits = socket.assigns.habits
      idx = socket.assigns.selected_habit_index
      new_idx = max(idx - 1, 0)
      {:noreply, assign(socket, selected_habit_index: new_idx)}
    end
  end

  @impl true
  def handle_event("tap", _params, socket) do
    handle_event("gamepad-a", %{}, socket)
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    {:noreply, socket}
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
    <div id="habits-phone-container" class="handheld-container habits-phone" phx-hook="TouchCarousel">
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
          <div class="phone-card habit-card-phone">
            <div class="view-title">✓ Daily Check-In</div>

            <div class="carousel-hint">
              <span>←</span>
              <span>swipe</span>
              <span>→</span>
            </div>

            <div class="habit-carousel-container">
              <div class="habit-display-large">
                <div class="habit-emoji">✓</div>
                <div class="habit-name-large"><%= current_habit["name"] %></div>
                <div class="habit-category-badge"><%= current_habit["category"] || "anchor" %></div>
              </div>
            </div>

            <div class="habit-question">
              <p>Done today?</p>
            </div>

            <div class="progress-indicator">
              <%= @selected_habit_index + 1 %> of <%= length(@habits) %>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Check In</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Skip</span>
              </div>
            </div>

            <div class="hint-text">
              <p>✨ Small habits, big changes</p>
            </div>
          </div>
        <% end %>
      <% end %>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/habits-phone" />

    <style>
      .habits-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .habit-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #00d4ff;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #00d4ff;
        text-align: center;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 20px;
        color: #606060;
        font-size: 18px;
        margin: 15px 0;
      }

      .habit-carousel-container {
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 250px;
        perspective: 1000px;
      }

      .habit-display-large {
        text-align: center;
        transform: scale(1);
        animation: slideInHabit 0.4s ease;
      }

      @keyframes slideInHabit {
        0% {
          opacity: 0;
          transform: scale(0.95);
        }
        100% {
          opacity: 1;
          transform: scale(1);
        }
      }

      .habit-emoji {
        font-size: 56px;
        margin-bottom: 15px;
      }

      .habit-name-large {
        font-size: 32px;
        font-weight: bold;
        color: #ecf0f1;
        margin-bottom: 10px;
        word-wrap: break-word;
      }

      .habit-category-badge {
        display: inline-block;
        background: rgba(0, 212, 255, 0.2);
        border: 1px solid #00d4ff;
        padding: 6px 12px;
        border-radius: 20px;
        font-size: 12px;
        color: #00d4ff;
        text-transform: uppercase;
        letter-spacing: 1px;
      }

      .habit-question {
        text-align: center;
        font-size: 18px;
        color: #a0a0a0;
        margin: 20px 0;
      }

      .progress-indicator {
        text-align: center;
        font-size: 12px;
        color: #707070;
        margin: 15px 0;
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
        background: #00d4ff;
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

      .hint-text {
        text-align: center;
        font-size: 13px;
        color: #707070;
        font-style: italic;
      }

      .hint-text p {
        margin: 0;
      }

      .message {
        position: fixed;
        bottom: 20px;
        left: 10px;
        right: 10px;
        background: rgba(0, 212, 255, 0.2);
        border: 1px solid #00d4ff;
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

      @media (max-width: 768px) {
        .habit-card-phone {
          padding: 15px;
        }

        .habit-name-large {
          font-size: 28px;
        }

        .habit-carousel-container {
          min-height: 200px;
        }

        .habit-emoji {
          font-size: 48px;
        }

        .carousel-hint {
          gap: 15px;
          font-size: 16px;
        }
      }
    </style>
    """
  end
end
