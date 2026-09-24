defmodule BotArmyDashboardLiveview.HabitAnchorsLive do
  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  require Logger
  alias BotArmyDashboardLiveview.HabitItems
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        habits: [],
        habits_error: nil,
        selected_habit_index: 0,
        message: nil,
        loading: true
      )
      |> fetch_habits()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_habits(socket) do
    live_view_pid = self()

    Task.start_link(fn ->
      case hygiene_items() do
        {:ok, items} -> send(live_view_pid, {:habits_loaded, hygiene_items_to_habits(items)})
        {:error, reason} -> send(live_view_pid, {:habits_unavailable, reason})
      end
    end)

    socket
  end

  # The exit case (`:noproc` when the broker is down) is handled by Broker; the
  # rescue/catch here are the backstop for anything else. Every way of getting
  # nothing back answers with a reason *and* leaves a trace, because a screen
  # saying "can't reach the bot" with an empty log is indistinguishable from a
  # screen nobody opened.
  defp hygiene_items do
    case Broker.request("wife_care.control_panel.hygiene", Jason.encode!(%{}), timeout: 5000) do
      {:ok, %{body: body}} ->
        decode_hygiene(body)

      {:error, reason} ->
        note_failure(reason)
        {:error, unavailable_reason(reason)}
    end
  rescue
    error ->
      note_failure(error)
      {:error, unavailable_reason({:raised, error})}
  catch
    kind, reason ->
      note_failure({kind, reason})
      {:error, "the bot is not reachable right now"}
  end

  defp note_failure(reason) do
    Logger.warning("[HabitAnchors] hygiene answered nothing: #{inspect(reason)}")
  end

  defp decode_hygiene(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => %{"hygiene" => %{"items" => items}}}} when is_list(items) ->
        {:ok, items}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error_message(error)}

      _ ->
        {:error, "the bot answered something unreadable"}
    end
  end

  # A read that answers nothing is not an empty list: "no habits configured"
  # over a dead bot is a claim about her data that the bot never made.
  defp error_message(error) when is_map(error), do: error["message"] || "the bot refused the read"
  defp error_message(error) when is_binary(error), do: error
  defp error_message(_error), do: "the bot refused the read"

  defp unavailable_reason(:no_broker), do: "the bot is not reachable right now"
  defp unavailable_reason(:timeout), do: "the bot did not answer in time"
  defp unavailable_reason(reason) when is_atom(reason), do: to_string(reason)
  defp unavailable_reason(_reason), do: "the request failed"

  # The bot already orders these for reading (overdue first, then never logged,
  # then in rhythm), and it is the only party that knows how long ago each one
  # was logged. Both live in HabitItems, tested on its own.
  defp hygiene_items_to_habits(items), do: HabitItems.to_habits(items)

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info({:habits_loaded, habits}, socket) do
    {:noreply,
     assign(socket,
       habits: habits,
       habits_error: nil,
       loading: false,
       selected_habit_index: 0
     )}
  end

  @impl true
  def handle_info({:habits_unavailable, reason}, socket) do
    {:noreply,
     assign(socket, habits: [], habits_error: reason, loading: false, selected_habit_index: 0)}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, socket |> assign(loading: true, habits_error: nil, message: nil) |> fetch_habits()}
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
    live_view_pid = self()

    Task.start_link(fn ->
      try do
        payload = %{"event" => habit["id"], "reason" => "dashboard check-in"}

        case Broker.request(
               "wife_care.control_panel.record_hygiene_event",
               Jason.encode!(payload),
               timeout: 5000
             ) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"ok" => true}} ->
                send(live_view_pid, {:habit_checked_in, habit["name"]})

              _ ->
                send(live_view_pid, {:check_in_failed})
            end

          {:error, _} ->
            send(live_view_pid, {:check_in_failed})
        end
      rescue
        _ -> send(live_view_pid, {:check_in_failed})
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
     |> schedule_message_clear(3000)
     |> fetch_habits()}
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
        <%= if @habits_error do %>
          <div class="empty-state">
            <p>Can't reach the bot</p>
            <p class="empty-detail"><%= @habits_error %></p>
            <button class="retry-button" phx-click="retry">Try again</button>
          </div>
        <% else %>
          <%= if Enum.empty?(@habits) do %>
            <div class="empty-state">
              <p>No items to check in yet</p>
              <p class="empty-detail">The bot answered with an empty list.</p>
              <button class="retry-button" phx-click="retry">Try again</button>
            </div>
          <% else %>
          <% current_habit = Enum.at(@habits, @selected_habit_index) %>
          <div class="habit-card">
            <div class="view-title">✓ Check In</div>

            <div class="habit-display">
              <div class="habit-name"><%= current_habit["name"] %></div>
              <div class="habit-category"><%= current_habit["category"] || "anchor" %></div>
              <div class="habit-logged"><%= current_habit["logged"] %></div>
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

      .habit-logged {
        margin-top: 10px;
        font-size: 13px;
        color: #909090;
      }

      .empty-detail {
        font-size: 13px;
        color: #808080;
        margin: 8px 0 16px;
      }

      .retry-button {
        background: transparent;
        border: 1px solid #00d4ff;
        color: #00d4ff;
        padding: 10px 18px;
        border-radius: 6px;
        font-size: 14px;
        min-height: 44px;
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
