defmodule BotArmyDashboardLiveview.TimerPhoneLive do
  use Phoenix.LiveView
  import BotArmyDashboardLiveview.ReadError
  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.PhoneNavModal
  alias BotArmyDashboardLiveview.SyncStatus

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket_id = socket.id
    {:ok, _} = BotArmyDashboardLiveview.OfflineQueue.start_link(socket_id: socket_id)

    socket =
      socket
      |> assign(
        socket_id: socket_id,
        timer_state: :idle,
        durations: [15, 25, 45, 60, 90],
        selected_duration: 25,
        duration_index: 1,
        work_elapsed: 0,
        work_duration: 0,
        break_elapsed: 0,
        break_duration: 0,
        total_work_time: 0,
        total_break_time: 0,
        session_count: 0,
        message: nil,
        tasks: [],
        selected_task_index: 0,
        show_task_browser: false,
        session_note: "",
        show_nav_menu: false,
        search_query: "",
        sync_status: %{},
        is_online: true
      )
      |> fetch_tasks()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_tasks(socket) do
    BotRead.async(self(), :tasks_loaded, "bridge.task.list", %{}, timeout: 5000)
    socket
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 1000)
    socket
  end

  @impl true
  def handle_info({:tasks_loaded, answer}, socket) do
    case BotRead.list(answer, "tasks") do
      {:ok, tasks} -> {:noreply, assign(socket, tasks: tasks, selected_task_index: 0)}
      :error -> {:noreply, BotRead.failed(socket, :unexpected_reply)}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    case socket.assigns.timer_state do
      :working ->
        new_elapsed = socket.assigns.work_elapsed + 1

        {:noreply,
         socket
         |> assign(work_elapsed: new_elapsed)
         |> schedule_tick()}

      :breaking ->
        new_elapsed = socket.assigns.break_elapsed + 1

        {:noreply,
         socket
         |> assign(break_elapsed: new_elapsed)
         |> schedule_tick()}

      _ ->
        {:noreply, schedule_tick(socket)}
    end
  end

  # Gamepad handlers
  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        new_idx = max(socket.assigns.duration_index - 1, 0)
        new_duration = Enum.at(durations, new_idx)

        {:noreply,
         assign(socket, duration_index: new_idx, selected_duration: new_duration, message: nil)}

      :task_browser ->
        tasks = socket.assigns.tasks
        idx = socket.assigns.selected_task_index
        new_idx = max(idx - 1, 0)
        {:noreply, assign(socket, selected_task_index: new_idx)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        new_idx = min(socket.assigns.duration_index + 1, length(durations) - 1)
        new_duration = Enum.at(durations, new_idx)

        {:noreply,
         assign(socket, duration_index: new_idx, selected_duration: new_duration, message: nil)}

      :task_browser ->
        tasks = socket.assigns.tasks
        idx = socket.assigns.selected_task_index
        new_idx = min(idx + 1, length(tasks) - 1)
        {:noreply, assign(socket, selected_task_index: new_idx)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        {:noreply,
         socket
         |> assign(
           timer_state: :working,
           work_elapsed: 0,
           work_duration: socket.assigns.selected_duration * 60
         )
         |> schedule_tick()}

      :working ->
        total_work = socket.assigns.total_work_time + socket.assigns.work_elapsed

        {:noreply,
         socket
         |> assign(
           timer_state: :breaking,
           break_elapsed: 0,
           break_duration: socket.assigns.selected_duration * 60,
           total_work_time: total_work,
           message: "☕ Break time"
         )
         |> schedule_tick()}

      :breaking ->
        total_break = socket.assigns.total_break_time + socket.assigns.break_elapsed

        {:noreply,
         socket
         |> assign(
           timer_state: :idle,
           work_elapsed: 0,
           break_elapsed: 0,
           total_break_time: total_break,
           session_count: socket.assigns.session_count + 1,
           show_task_browser: false,
           message: nil
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.timer_state do
      :task_browser ->
        {:noreply, assign(socket, show_task_browser: false)}

      :working ->
        {:noreply, assign(socket, timer_state: :idle, work_elapsed: 0, message: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-x", _params, socket) do
    case socket.assigns.timer_state do
      :breaking ->
        {:noreply,
         socket
         |> assign(timer_state: :task_browser, show_task_browser: true, session_note: "")
         |> fetch_tasks()}

      :task_browser ->
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-y", _params, socket) do
    case socket.assigns.timer_state do
      :task_browser ->
        task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)

        if task do
          publish_work_session(socket, task)
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # Touch handlers (phone-specific)
  @impl true
  def handle_event("swipe-left", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        new_idx = min(socket.assigns.duration_index + 1, length(durations) - 1)
        new_duration = Enum.at(durations, new_idx)
        {:noreply, assign(socket, duration_index: new_idx, selected_duration: new_duration)}

      :task_browser ->
        tasks = socket.assigns.tasks
        idx = socket.assigns.selected_task_index
        new_idx = min(idx + 1, length(tasks) - 1)
        {:noreply, assign(socket, selected_task_index: new_idx)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("swipe-right", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        new_idx = max(socket.assigns.duration_index - 1, 0)
        new_duration = Enum.at(durations, new_idx)
        {:noreply, assign(socket, duration_index: new_idx, selected_duration: new_duration)}

      :task_browser ->
        tasks = socket.assigns.tasks
        idx = socket.assigns.selected_task_index
        new_idx = max(idx - 1, 0)
        {:noreply, assign(socket, selected_task_index: new_idx)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("tap", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        handle_event("gamepad-a", %{}, socket)

      :working ->
        handle_event("gamepad-a", %{}, socket)

      :breaking ->
        {:noreply, socket}

      :task_browser ->
        handle_event("gamepad-y", %{}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    # Open nav menu on long-press
    {:noreply, assign(socket, show_nav_menu: true, search_query: "")}
  end

  @impl true
  def handle_event("close-nav-menu", _params, socket) do
    {:noreply, assign(socket, show_nav_menu: false, search_query: "")}
  end

  @impl true
  def handle_event("stop-propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter-nav", %{"query" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  defp publish_work_session(socket, task) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{
          "task_id" => task["id"],
          "work_duration_seconds" => socket.assigns.work_elapsed,
          "break_duration_seconds" => socket.assigns.break_elapsed,
          "session_note" => socket.assigns.session_note,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        encoded_payload = Jason.encode!(payload)

        case Gnat.pub(:nats_connection, "events.timer.session_completed", encoded_payload) do
          :ok ->
            send(parent, {:session_published, task["title"]})

          _ ->
            BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
              socket.assigns.socket_id,
              "events.timer.session_completed",
              encoded_payload,
              %{"task_title" => task["title"]}
            )

            send(parent, {:publish_queued, task["title"]})
        end
      rescue
        _ ->
          BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
            socket.assigns.socket_id,
            "events.timer.session_completed",
            Jason.encode!(%{
              "task_id" => task["id"],
              "work_duration_seconds" => socket.assigns.work_elapsed,
              "break_duration_seconds" => socket.assigns.break_elapsed,
              "session_note" => socket.assigns.session_note,
              "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
            }),
            %{"task_title" => task["title"]}
          )

          send(parent, {:publish_queued, task["title"]})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Publishing session...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:session_published, title}, socket) do
    {:noreply,
     socket
     |> assign(
       timer_state: :idle,
       work_elapsed: 0,
       break_elapsed: 0,
       show_task_browser: false,
       session_note: "",
       message: "✓ Session linked to: #{title}"
     )
     |> schedule_message_clear(3000)}
  end

  @impl true
  def handle_info({:publish_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Failed to publish session")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:publish_queued, title}, socket) do
    {:noreply,
     socket
     |> assign(message: "⚠️ Session queued (offline)")
     |> schedule_message_clear(3000)}
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

  defp schedule_message_clear(socket, delay_ms) do
    Process.send_after(self(), :clear_message, delay_ms)
    socket
  end

  @impl true
  def handle_info(:clear_message, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>
    <div
      id="timer-phone-container"
      class="handheld-container timer-phone"
      phx-hook="TouchCarousel"
      phx-window-keydown="window-key"
    >
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <PhoneNavModal.modal
        show_menu={@show_nav_menu}
        current_route="/timer-phone"
        filtered_handhelds={PhoneNavModal.filter_handhelds(@search_query)}
        search_query={@search_query}
      />
      <div class="phone-card timer-card">
        <div class="view-title">⏱️ Focus Timer</div>

        <%= case @timer_state do %>
          <% :idle -> %>
            <div class="idle-state">
              <div class="duration-spinner">
                <div class="spinner-label">Choose Duration</div>
                <div class="spinner-wheel">
                  <%= for {duration, idx} <- Enum.with_index(@durations) do %>
                    <%= if idx == @duration_index do %>
                      <div class="spinner-item active"><%= duration %>m</div>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <div class="carousel-hint">
                <span>←</span>
                <span class="duration-value"><%= @selected_duration %> min</span>
                <span>→</span>
              </div>

              <div class="session-info">
                <p>Session <%= @session_count + 1 %></p>
              </div>
            </div>

          <% :working -> %>
            <div class="working-state">
              <div class="timer-display">
                <div class="time-large">
                  <%= format_time(@work_duration - @work_elapsed) %>
                </div>
                <div class="timer-label">Stay focused</div>
              </div>

              <div class="session-stats">
                <p>Elapsed: <%= format_time(@work_elapsed) %></p>
              </div>
            </div>

          <% :breaking -> %>
            <div class="breaking-state">
              <div class="break-display">
                <div class="time-large break-time">
                  <%= format_time(@break_elapsed) %>
                </div>
                <div class="timer-label">You worked</div>
              </div>

              <div class="break-message">
                <p>Rest your mind. You earned this.</p>
              </div>

              <%= if @show_task_browser do %>
                <div class="task-browser-state">
                  <div class="browser-title">📋 Link to Task</div>

                  <div class="task-list-phone">
                    <%= if Enum.empty?(@tasks) do %>
                      <div class="empty-state">
                        <p>No tasks found</p>
                      </div>
                    <% else %>
                      <%= for {task, idx} <- Enum.with_index(@tasks) do %>
                        <div class={["task-item-phone", idx == @selected_task_index && "active"]}>
                          <span class="task-title"><%= task["title"] %></span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
        <% end %>

        <div class="controls">
          <%= case @timer_state do %>
            <% :idle -> %>
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Start Focus</span>
              </div>

            <% :working -> %>
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Take Break</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Stop</span>
              </div>

            <% :breaking -> %>
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Next Session</span>
              </div>
              <div class="control-hint">
                <span class="key">X</span>
                <span class="action">Link Task</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Done</span>
              </div>
          <% end %>
        </div>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/timer-phone" />

    <style>
      .timer-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .duration-spinner {
        text-align: center;
        margin: 30px 0;
      }

      .spinner-label {
        font-size: 14px;
        color: #6b7fd7;
        text-transform: uppercase;
        letter-spacing: 2px;
        margin-bottom: 15px;
      }

      .spinner-wheel {
        width: 150px;
        height: 150px;
        margin: 0 auto;
        border: 3px solid #6b7fd7;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(107, 127, 215, 0.1);
        position: relative;
      }

      .spinner-item {
        font-size: 32px;
        font-weight: bold;
        opacity: 0.5;
      }

      .spinner-item.active {
        opacity: 1;
        color: #6b7fd7;
      }

      .duration-value {
        font-size: 20px;
        font-weight: bold;
        color: #ecf0f1;
        min-width: 80px;
      }

      .session-info {
        color: #707070;
        font-size: 12px;
      }

      .timer-display {
        text-align: center;
        margin: 40px 0;
      }

      .time-large {
        font-size: 56px;
        font-weight: bold;
        color: #6b7fd7;
        font-family: "Courier New", monospace;
        letter-spacing: 4px;
      }

      .time-large.break-time {
        color: #00d4ff;
      }

      .timer-label {
        font-size: 14px;
        color: #b0b0b0;
        margin-top: 15px;
      }

      .session-stats {
        text-align: center;
        font-size: 13px;
        color: #707070;
      }

      .break-display {
        text-align: center;
        margin: 30px 0;
      }

      .break-message {
        text-align: center;
        color: #a0a0a0;
        font-size: 16px;
        margin: 20px 0;
      }

      .task-browser-state {
        background: rgba(107, 127, 215, 0.1);
        border: 1px solid #6b7fd7;
        border-radius: 6px;
        padding: 15px;
        margin: 20px 0;
      }

      .browser-title {
        font-size: 14px;
        font-weight: bold;
        color: #6b7fd7;
        margin-bottom: 10px;
      }

      .task-list-phone {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 200px;
        overflow-y: auto;
      }

      .task-item-phone {
        padding: 10px;
        border-radius: 4px;
        background: rgba(0, 0, 0, 0.3);
        cursor: pointer;
        transition: all 0.2s ease;
        border: 1px solid transparent;
      }

      .task-item-phone.active {
        background: rgba(107, 127, 215, 0.3);
        border: 1px solid #6b7fd7;
        transform: scale(1.02);
      }

      .task-title {
        color: #ecf0f1;
        font-size: 14px;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 20px;
        color: #606060;
        font-size: 20px;
        margin: 20px 0;
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
        background: #6b7fd7;
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

      .message {
        position: fixed;
        bottom: 20px;
        left: 10px;
        right: 10px;
        background: rgba(107, 127, 215, 0.2);
        border: 1px solid #6b7fd7;
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

      @media (max-width: 768px) {
        .time-large {
          font-size: 48px;
        }

        .spinner-wheel {
          width: 140px;
          height: 140px;
        }

        .spinner-item {
          font-size: 28px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
