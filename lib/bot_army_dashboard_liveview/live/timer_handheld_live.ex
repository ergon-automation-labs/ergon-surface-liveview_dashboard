defmodule BotArmyDashboardLiveview.TimerHandheldLive do
  use Phoenix.LiveView
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       timer_state: :idle,
       work_duration: 25,
       work_elapsed: 0,
       break_elapsed: 0,
       total_work_time: 0,
       total_break_time: 0,
       selected_duration: 25,
       durations: [15, 25, 45, 60, 90],
       message: nil,
       session_count: 0,
       tasks: [],
       selected_task_index: 0,
       session_note: "",
       show_task_browser: false
     )
     |> schedule_tick()}
  end

  defp fetch_tasks(socket) do
    Task.start_link(fn ->
      try do
        case Gnat.request(:nats_connection, "bridge.task.list", Jason.encode!(%{}), timeout: 5000) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"tasks" => tasks}} ->
                send(self(), {:tasks_loaded, tasks})

              {:ok, tasks} when is_list(tasks) ->
                send(self(), {:tasks_loaded, tasks})

              {:error, _} ->
                send(self(), {:tasks_loaded, []})
            end

          {:error, _} ->
            send(self(), {:tasks_loaded, []})
        end
      rescue
        _ -> send(self(), {:tasks_loaded, []})
      end
    end)

    socket
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 1000)
    socket
  end

  @impl true
  def handle_info({:tasks_loaded, tasks}, socket) do
    {:noreply, assign(socket, tasks: tasks, selected_task_index: 0)}
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

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        idx = Enum.find_index(durations, &(&1 == socket.assigns.selected_duration))
        new_idx = max(idx - 1, 0)
        new_duration = Enum.at(durations, new_idx)
        {:noreply, assign(socket, selected_duration: new_duration, message: nil)}

      :task_browser ->
        count = length(socket.assigns.tasks)

        if count > 0 do
          index = max(socket.assigns.selected_task_index - 1, 0)
          {:noreply, assign(socket, selected_task_index: index)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        durations = socket.assigns.durations
        idx = Enum.find_index(durations, &(&1 == socket.assigns.selected_duration))
        new_idx = min(idx + 1, length(durations) - 1)
        new_duration = Enum.at(durations, new_idx)
        {:noreply, assign(socket, selected_duration: new_duration, message: nil)}

      :task_browser ->
        count = length(socket.assigns.tasks)

        if count > 0 do
          index = min(socket.assigns.selected_task_index + 1, max(count - 1, 0))
          {:noreply, assign(socket, selected_task_index: index)}
        else
          {:noreply, socket}
        end

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
           work_duration: socket.assigns.selected_duration,
           work_elapsed: 0,
           message: "⏱️  Focus time started"
         )
         |> schedule_message_clear(2000)}

      :working ->
        {:noreply,
         socket
         |> assign(
           timer_state: :breaking,
           total_work_time: socket.assigns.total_work_time + socket.assigns.work_elapsed,
           break_elapsed: 0,
           message: "☕ Break time - you earned this"
         )
         |> schedule_message_clear(3000)}

      :breaking ->
        session_count = socket.assigns.session_count + 1

        {:noreply,
         socket
         |> assign(
           timer_state: :idle,
           total_break_time: socket.assigns.total_break_time + socket.assigns.break_elapsed,
           work_elapsed: 0,
           break_elapsed: 0,
           session_count: session_count,
           message: "✓ Session complete. Ready for another?"
         )
         |> schedule_message_clear(3000)}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.timer_state do
      :idle ->
        {:noreply, socket}

      :task_browser ->
        {:noreply, assign(socket, show_task_browser: false)}

      _ ->
        {:noreply,
         socket
         |> assign(
           timer_state: :idle,
           work_elapsed: 0,
           break_elapsed: 0,
           message: "⏹️  Timer stopped"
         )
         |> schedule_message_clear(2000)}
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

  defp publish_work_session(socket, task) do
    Task.start_link(fn ->
      try do
        payload = %{
          "task_id" => task["id"],
          "work_duration_seconds" => socket.assigns.work_elapsed,
          "break_duration_seconds" => socket.assigns.break_elapsed,
          "session_note" => socket.assigns.session_note,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.timer.session_completed", Jason.encode!(payload)) do
          :ok ->
            send(self(), {:session_published, task["title"]})

          _ ->
            send(self(), {:publish_failed})
        end
      rescue
        _ -> send(self(), {:publish_failed})
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

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp progress_percent(elapsed, total) when total > 0 do
    div(elapsed * 100, total)
  end

  defp progress_percent(_elapsed, _total), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div class="timer-handheld">
      <div class="handheld-container">
        <div class="timer-view">
          <%= case @timer_state do %>
            <% :idle -> %>
              <div class="idle-state">
                <div class="view-title">Focus Timer</div>

                <div class="duration-selector">
                  <div class="label">Select duration</div>
                  <div class="durations">
                    <%= for duration <- @durations do %>
                      <%= if duration == @selected_duration do %>
                        <div class="duration-item selected">
                          <%= duration %><span class="unit">m</span>
                        </div>
                      <% else %>
                        <div class="duration-item">
                          <%= duration %><span class="unit">m</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <div class="session-stats">
                  <div class="stat">
                    <span class="label">Today</span>
                    <span class="value"><%= format_time(@total_work_time) %></span>
                  </div>
                  <div class="stat">
                    <span class="label">Sessions</span>
                    <span class="value"><%= @session_count %></span>
                  </div>
                </div>

                <div class="controls">
                  <div class="control-hint">
                    <span class="key">↑ ↓</span>
                    <span class="action">Duration</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">A</span>
                    <span class="action">Start</span>
                  </div>
                </div>
              </div>

            <% :working -> %>
              <div class="working-state">
                <div class="view-title">🎯 In Focus</div>

                <div class="timer-display">
                  <div class="time">
                    <%= format_time(@work_elapsed) %>
                  </div>
                  <div class="target">
                    Target: <%= @work_duration %>m
                  </div>
                </div>

                <div class="progress-bar">
                  <div class="progress-fill" style={"width: #{progress_percent(@work_elapsed, @work_duration * 60)}%"}></div>
                </div>

                <div class="status-text">
                  Keep going. You're in the zone.
                </div>

                <div class="controls">
                  <div class="control-hint">
                    <span class="key">A</span>
                    <span class="action">Take Break</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">B</span>
                    <span class="action">Stop</span>
                  </div>
                </div>
              </div>

            <% :breaking -> %>
              <%= if @show_task_browser do %>
                <div class="task-browser-state">
                  <div class="view-title">📋 Link to Task</div>

                  <div class="task-list">
                    <%= if Enum.empty?(@tasks) do %>
                      <div class="empty-state">
                        <p>No tasks found</p>
                      </div>
                    <% else %>
                      <%= for {task, idx} <- Enum.with_index(@tasks) do %>
                        <%= if idx == @selected_task_index do %>
                          <div class="task-item selected">
                            <span class="task-title"><%= task["title"] %></span>
                          </div>
                        <% else %>
                          <div class="task-item">
                            <span class="task-title"><%= task["title"] %></span>
                          </div>
                        <% end %>
                      <% end %>
                    <% end %>
                    </div>

                  <div class="controls">
                    <div class="control-hint">
                      <span class="key">↑ ↓</span>
                      <span class="action">Navigate</span>
                    </div>
                    <div class="control-hint">
                      <span class="key">Y</span>
                      <span class="action">Save</span>
                    </div>
                    <div class="control-hint">
                      <span class="key">B</span>
                      <span class="action">Close</span>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="breaking-state">
                  <div class="view-title">☕ Break Time</div>

                  <div class="break-info">
                    <div class="work-summary">
                      <span class="label">You worked</span>
                      <span class="time"><%= format_time(@work_elapsed) %></span>
                    </div>
                    <div class="break-duration">
                      <span class="label">Break time</span>
                      <span class="time"><%= format_time(@break_elapsed) %></span>
                    </div>
                  </div>

                  <div class="break-message">
                    <p>Rest your mind. You earned this.</p>
                  </div>

                  <div class="controls">
                    <div class="control-hint">
                      <span class="key">A</span>
                      <span class="action">Next Session</span>
                    </div>
                    <div class="control-hint">
                      <span class="key">X</span>
                      <span class="action">Link Task</span>
                    </div>
                    <div class="control-hint">
                      <span class="key">B</span>
                      <span class="action">Stop</span>
                    </div>
                  </div>
                </div>
              <% end %>
          <% end %>

          <%= if @message do %>
            <div class="message"><%= @message %></div>
          <% end %>
        </div>
      </div>

      <style>
        .timer-handheld {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          background: linear-gradient(135deg, #0a0e27 0%, #0f1535 100%);
          color: #e0e0e0;
          height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 20px;
        }

        .handheld-container {
          width: 100%;
          max-width: 800px;
          aspect-ratio: 16 / 9;
          background: #0f1535;
          border: 2px solid #1e2749;
          border-radius: 12px;
          display: flex;
          flex-direction: column;
          padding: 30px;
          overflow: hidden;
          box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
        }

        .timer-view {
          height: 100%;
          display: flex;
          flex-direction: column;
        }

        .view-title {
          font-size: 28px;
          font-weight: bold;
          color: #00ff88;
          margin-bottom: 25px;
        }

        .idle-state,
        .working-state,
        .breaking-state {
          flex: 1;
          display: flex;
          flex-direction: column;
        }

        .duration-selector {
          margin-bottom: 30px;
        }

        .label {
          font-size: 12px;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 12px;
          display: block;
          font-weight: 600;
        }

        .durations {
          display: flex;
          gap: 10px;
          flex-wrap: wrap;
        }

        .duration-item {
          padding: 12px 16px;
          background: #1a2540;
          border: 2px solid #1e2749;
          border-radius: 8px;
          text-align: center;
          cursor: pointer;
          transition: all 0.2s;
          font-weight: 600;
        }

        .duration-item.selected {
          background: #1e3540;
          border-color: #00ff88;
          box-shadow: 0 0 12px rgba(0, 255, 136, 0.3);
          transform: scale(1.05);
        }

        .unit {
          font-size: 11px;
          color: #888;
          margin-left: 4px;
        }

        .session-stats {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 15px;
          margin-bottom: 25px;
        }

        .stat {
          background: #1a2540;
          padding: 15px;
          border-radius: 8px;
          border-left: 3px solid #00ff88;
        }

        .stat .label {
          font-size: 11px;
          color: #888;
          margin-bottom: 6px;
        }

        .stat .value {
          font-size: 18px;
          font-weight: bold;
          color: #00ff88;
        }

        .timer-display {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          margin-bottom: 20px;
        }

        .time {
          font-size: 72px;
          font-weight: bold;
          color: #00ff88;
          font-family: monospace;
          text-shadow: 0 0 20px rgba(0, 255, 136, 0.3);
        }

        .target {
          font-size: 14px;
          color: #888;
          margin-top: 10px;
        }

        .progress-bar {
          width: 100%;
          height: 8px;
          background: #1a2540;
          border-radius: 4px;
          overflow: hidden;
          margin-bottom: 20px;
        }

        .progress-fill {
          height: 100%;
          background: linear-gradient(90deg, #00ff88, #00cc6a);
          transition: width 0.1s linear;
        }

        .status-text {
          text-align: center;
          font-size: 14px;
          color: #aaa;
          margin-bottom: 20px;
          font-style: italic;
        }

        .break-info {
          flex: 1;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 20px;
          margin-bottom: 20px;
        }

        .work-summary,
        .break-duration {
          background: #1a2540;
          padding: 20px;
          border-radius: 8px;
          border-left: 3px solid #00ff88;
        }

        .work-summary .label,
        .break-duration .label {
          display: block;
          font-size: 12px;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 8px;
        }

        .work-summary .time,
        .break-duration .time {
          font-size: 32px;
          font-weight: bold;
          color: #00ff88;
          font-family: monospace;
        }

        .break-message {
          text-align: center;
          margin-bottom: 20px;
        }

        .break-message p {
          font-size: 16px;
          color: #aaa;
          font-style: italic;
        }

        .controls {
          display: grid;
          grid-template-columns: repeat(2, 1fr);
          gap: 8px;
        }

        .control-hint {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 10px;
          background: #1a2540;
          border-radius: 4px;
          font-size: 12px;
        }

        .control-hint .key {
          font-weight: bold;
          color: #00ff88;
          min-width: 24px;
        }

        .control-hint .action {
          color: #aaa;
        }

        .message {
          background: #1a3a1a;
          color: #00ff88;
          padding: 12px 16px;
          border-radius: 6px;
          text-align: center;
          font-size: 13px;
          font-weight: 600;
          margin-top: 15px;
        }

        .task-browser-state {
          flex: 1;
          display: flex;
          flex-direction: column;
        }

        .task-list {
          flex: 1;
          overflow-y: auto;
          margin-bottom: 15px;
        }

        .task-item {
          padding: 12px;
          margin-bottom: 8px;
          background: #1a2540;
          border-left: 3px solid transparent;
          border-radius: 4px;
          transition: all 0.2s;
        }

        .task-item.selected {
          background: #1e3540;
          border-left-color: #00ff88;
          box-shadow: 0 0 8px rgba(0, 255, 136, 0.2);
        }

        .task-title {
          font-size: 13px;
          color: #e0e0e0;
          display: block;
        }

        .task-item.selected .task-title {
          color: #00ff88;
          font-weight: 600;
        }

        .empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #666;
        }
      </style>
    </div>
    """
  end
end
