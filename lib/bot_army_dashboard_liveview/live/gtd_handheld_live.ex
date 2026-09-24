defmodule BotArmyDashboardLiveview.GTDHandheldLive do
  use Phoenix.LiveView
  import BotArmyDashboardLiveview.ReadError
  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       projects: [],
       tasks: [],
       selected_project_index: 0,
       selected_task_index: 0,
       view_mode: :projects,
       loading: true,
       message: nil,
       show_note_input: false,
       note_text: "",
       voice_enabled: true
     )
     |> fetch_projects()}
  end

  defp fetch_projects(socket) do
    BotRead.async(self(), :projects_loaded, "bridge.project.list", %{}, timeout: 5000)
    socket
  end

  defp fetch_tasks(socket, project_id) do
    BotRead.async(
      self(),
      :tasks_loaded,
      "bridge.task.list",
      %{"project_id" => project_id, "limit" => 20},
      timeout: 5000
    )

    socket
  end

  @impl true
  def handle_info({:projects_loaded, answer}, socket) do
    case BotRead.list(answer, "projects") do
      {:ok, projects} ->
        {:noreply,
         socket
         |> assign(projects: projects, loading: false)
         |> assign(message: if(Enum.empty?(projects), do: "No projects found", else: nil))}

      :error ->
        {:noreply, BotRead.failed(socket, :unexpected_reply)}
    end
  end

  @impl true
  def handle_info({:tasks_loaded, answer}, socket) do
    case BotRead.list(answer, "tasks") do
      {:ok, tasks} -> {:noreply, assign(socket, tasks: tasks, selected_task_index: 0)}
      :error -> {:noreply, BotRead.failed(socket, :unexpected_reply)}
    end
  end

  @impl true
  def handle_info({:task_updated, msg}, socket) do
    {:noreply, assign(socket, message: msg)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.view_mode do
      :projects ->
        index = max(socket.assigns.selected_project_index - 1, 0)
        {:noreply, assign(socket, selected_project_index: index, message: nil)}

      :tasks ->
        index = max(socket.assigns.selected_task_index - 1, 0)
        {:noreply, assign(socket, selected_task_index: index, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.view_mode do
      :projects ->
        count = length(socket.assigns.projects)
        index = min(socket.assigns.selected_project_index + 1, max(count - 1, 0))
        {:noreply, assign(socket, selected_project_index: index, message: nil)}

      :tasks ->
        count = length(socket.assigns.tasks)
        index = min(socket.assigns.selected_task_index + 1, max(count - 1, 0))
        {:noreply, assign(socket, selected_task_index: index, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.view_mode do
      :projects ->
        project = Enum.at(socket.assigns.projects, socket.assigns.selected_project_index)

        if project do
          socket
          |> assign(view_mode: :tasks, selected_task_index: 0, tasks: [])
          |> fetch_tasks(project["id"])
          |> (fn s -> {:noreply, s} end).()
        else
          {:noreply, socket}
        end

      :tasks ->
        task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)
        if task, do: complete_task(socket, task["id"]), else: {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.view_mode do
      :projects ->
        {:noreply, socket}

      :tasks ->
        {:noreply, assign(socket, view_mode: :projects)}
    end
  end

  @impl true
  def handle_event("gamepad-x", _params, socket) do
    case socket.assigns.view_mode do
      :tasks ->
        task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)
        if task, do: defer_task(socket, task["id"]), else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-y", _params, socket) do
    case socket.assigns.view_mode do
      :tasks ->
        {:noreply, assign(socket, show_note_input: !socket.assigns.show_note_input)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("note-input-change", %{"value" => text}, socket) do
    {:noreply, assign(socket, note_text: text)}
  end

  @impl true
  def handle_event("add-note", _params, socket) do
    task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)

    if task && socket.assigns.note_text != "" do
      add_note_to_task(socket, task["id"], socket.assigns.note_text)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("voice-note", %{"text" => voice_text}, socket) do
    task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)

    if task && voice_text != "" do
      add_note_to_task(socket, task["id"], voice_text)
    else
      {:noreply, socket}
    end
  end

  defp complete_task(socket, task_id) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{task_id: task_id}

        case Broker.request("bridge.task.complete", Jason.encode!(payload), timeout: 5000) do
          {:ok, _} ->
            send(parent, {:task_updated, "✓ Task completed"})

          {:error, _} ->
            send(parent, {:task_updated, "✗ Failed to complete"})
        end
      rescue
        _ -> send(parent, {:task_updated, "✗ Error"})
      end
    end)

    {:noreply, assign(socket, message: "Completing...")}
  end

  defp defer_task(socket, task_id) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{task_id: task_id, status: "someday"}

        case Broker.request("bridge.task.update", Jason.encode!(payload), timeout: 5000) do
          {:ok, _} ->
            send(parent, {:task_updated, "⏱ Deferred"})

          {:error, _} ->
            send(parent, {:task_updated, "✗ Failed to defer"})
        end
      rescue
        _ -> send(parent, {:task_updated, "✗ Error"})
      end
    end)

    {:noreply, assign(socket, message: "Deferring...")}
  end

  defp add_note_to_task(socket, task_id, note_text) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{
          task_id: task_id,
          note: note_text
        }

        case Broker.request("bridge.task.update", Jason.encode!(payload), timeout: 5000) do
          {:ok, _} ->
            send(parent, {:task_updated, "✓ Note added"})

          {:error, _} ->
            send(parent, {:task_updated, "✗ Failed to add note"})
        end
      rescue
        _ -> send(parent, {:task_updated, "✗ Error"})
      end
    end)

    {:noreply,
     socket
     |> assign(show_note_input: false, note_text: "", message: "Adding note...")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>
    <div class="gtd-handheld">
      <div class="handheld-container">
        <%= if @loading do %>
          <div class="loading-state">
            <div class="spinner"></div>
            <p>Loading projects...</p>
          </div>
        <% else %>
          <%= if @view_mode == :projects do %>
            <div class="projects-view">
              <div class="view-title">Projects</div>
              <%= if Enum.empty?(@projects) do %>
                <div class="empty-state">
                  <p><%= @message || "No projects" %></p>
                </div>
              <% else %>
                <div class="item-list">
                  <%= for {project, idx} <- Enum.with_index(@projects) do %>
                    <%= if idx == @selected_project_index do %>
                      <div class="current-item selected">
                        <div class="item-title"><%= project["name"] %></div>
                        <div class="item-meta">
                          <%= if project["progress"], do: "#{round(project["progress"] * 100)}% done" %>
                        </div>
                      </div>
                    <% else %>
                      <div class="current-item">
                        <div class="item-title"><%= project["name"] %></div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="controls">
                  <div class="control-hint">
                    <span class="key">↑ ↓</span>
                    <span class="action">Navigate</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">A</span>
                    <span class="action">View Tasks</span>
                  </div>
                </div>

                <%= if @message do %>
                  <div class="message"><%= @message %></div>
                <% end %>

                <div class="counter">
                  <%= @selected_project_index + 1 %> / <%= length(@projects) %>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="tasks-view">
              <div class="view-title">Tasks</div>
              <%= if Enum.empty?(@tasks) do %>
                <div class="empty-state">
                  <p>No tasks in this project</p>
                </div>
              <% else %>
                <div class="item-list">
                  <%= for {task, idx} <- Enum.with_index(@tasks) do %>
                    <%= if idx == @selected_task_index do %>
                      <div class="current-item selected">
                        <div class="item-title"><%= task["title"] %></div>
                        <div class="item-meta">
                          <span class="status"><%= task["status"] || "inbox" %></span>
                          <%= if task["due_date"] do %>
                            <span class="due">📅 <%= format_date(task["due_date"]) %></span>
                          <% end %>
                        </div>
                      </div>
                    <% else %>
                      <div class="current-item">
                        <div class="item-title"><%= task["title"] %></div>
                        <div class="item-meta">
                          <span class="status"><%= task["status"] || "inbox" %></span>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="controls">
                  <div class="control-hint">
                    <span class="key">↑ ↓</span>
                    <span class="action">Navigate</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">A</span>
                    <span class="action">Complete</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">X</span>
                    <span class="action">Defer</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">Y</span>
                    <span class="action">Add Note</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">B</span>
                    <span class="action">Back</span>
                  </div>
                </div>

                <%= if @show_note_input do %>
                  <div class="note-input-area">
                    <textarea
                      phx-change="note-input-change"
                      placeholder="Add a note..."
                      class="note-textarea"
                    ><%= @note_text %></textarea>
                    <button phx-click="add-note" class="add-note-btn">Save Note</button>
                    <button phx-click="gamepad-y" class="cancel-btn">Cancel</button>
                    <%= if @voice_enabled do %>
                      <button class="voice-btn" id="voice-input-btn">🎙️ Voice</button>
                    <% end %>
                  </div>
                <% end %>

                <%= if @message do %>
                  <div class="message"><%= @message %></div>
                <% end %>

                <div class="counter">
                  <%= @selected_task_index + 1 %> / <%= length(@tasks) %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <script>
        document.addEventListener("DOMContentLoaded", function() {
          let gamepadIndex = null;
          let lastPressed = {};

          function pollGamepad() {
            const gamepads = navigator.getGamepads();

            for (let i = 0; i < gamepads.length; i++) {
              const gp = gamepads[i];
              if (!gp) continue;

              gamepadIndex = i;

              // D-Pad: up (12), down (13), left (14), right (15)
              if (gp.buttons[12].pressed && !lastPressed[12]) {
                lastPressed[12] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-up"));
              } else if (!gp.buttons[12].pressed) {
                lastPressed[12] = false;
              }

              if (gp.buttons[13].pressed && !lastPressed[13]) {
                lastPressed[13] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-down"));
              } else if (!gp.buttons[13].pressed) {
                lastPressed[13] = false;
              }

              // A (0), B (1), X (2), Y (3)
              if (gp.buttons[0].pressed && !lastPressed[0]) {
                lastPressed[0] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-a"));
              } else if (!gp.buttons[0].pressed) {
                lastPressed[0] = false;
              }

              if (gp.buttons[1].pressed && !lastPressed[1]) {
                lastPressed[1] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-b"));
              } else if (!gp.buttons[1].pressed) {
                lastPressed[1] = false;
              }

              if (gp.buttons[2].pressed && !lastPressed[2]) {
                lastPressed[2] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-x"));
              } else if (!gp.buttons[2].pressed) {
                lastPressed[2] = false;
              }

              if (gp.buttons[3].pressed && !lastPressed[3]) {
                lastPressed[3] = true;
                const el = document.querySelector("[data-phx-main]");
                if (el) el.dispatchEvent(new Event("gamepad-y"));
              } else if (!gp.buttons[3].pressed) {
                lastPressed[3] = false;
              }
            }

            requestAnimationFrame(pollGamepad);
          }

          // Voice input button
          const voiceBtn = document.getElementById("voice-input-btn");
          if (voiceBtn && "webkitSpeechRecognition" in window) {
            const recognition = new webkitSpeechRecognition();
            recognition.continuous = false;
            recognition.interimResults = false;

            voiceBtn.addEventListener("click", function(e) {
              e.preventDefault();
              voiceBtn.textContent = "🎙️ Listening...";
              recognition.start();
            });

            recognition.onresult = function(event) {
              let transcript = "";
              for (let i = event.resultIndex; i < event.results.length; i++) {
                transcript += event.results[i][0].transcript;
              }
              const el = document.querySelector("[data-phx-main]");
              if (el) {
                const event = new CustomEvent("voice-note", {
                  detail: {text: transcript}
                });
                el.dispatchEvent(event);
              }
              voiceBtn.textContent = "🎙️ Voice";
            };

            recognition.onerror = function() {
              voiceBtn.textContent = "🎙️ Voice";
            };
          }

          pollGamepad();
        });
      </script>

      <style>
        .gtd-handheld {
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          padding: 20px;
        }

        .handheld-container {
          width: 100%;
          max-width: 400px;
          background: #1a1a2e;
          border-radius: 20px;
          padding: 30px 20px;
          box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
          color: #fff;
        }

        .loading-state {
          text-align: center;
          padding: 40px 20px;
        }

        .spinner {
          border: 4px solid #667eea;
          border-top: 4px solid transparent;
          border-radius: 50%;
          width: 50px;
          height: 50px;
          animation: spin 1s linear infinite;
          margin: 0 auto 20px;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #999;
        }

        .view-title {
          font-size: 24px;
          font-weight: bold;
          margin-bottom: 20px;
          color: #00ffcc;
        }

        .item-list {
          background: #0f3460;
          border-radius: 15px;
          padding: 15px;
          margin-bottom: 20px;
          max-height: 300px;
          overflow-y: auto;
        }

        .current-item {
          padding: 15px;
          margin-bottom: 10px;
          background: rgba(0, 212, 255, 0.05);
          border-left: 3px solid #333;
          border-radius: 5px;
          cursor: pointer;
          transition: all 0.2s;
        }

        .current-item.selected {
          background: rgba(0, 212, 255, 0.15);
          border-left-color: #00ffcc;
          transform: translateX(5px);
        }

        .item-title {
          font-size: 16px;
          font-weight: bold;
          color: #fff;
          margin-bottom: 5px;
        }

        .item-meta {
          font-size: 12px;
          color: #999;
          display: flex;
          gap: 10px;
          flex-wrap: wrap;
        }

        .status {
          background: rgba(102, 126, 234, 0.3);
          padding: 2px 6px;
          border-radius: 3px;
          color: #00ffcc;
        }

        .due {
          color: #ffb347;
        }

        .controls {
          background: rgba(102, 126, 234, 0.2);
          border-radius: 10px;
          padding: 15px;
          margin-bottom: 15px;
        }

        .control-hint {
          display: flex;
          align-items: center;
          margin: 8px 0;
          font-size: 12px;
        }

        .control-hint .key {
          background: #667eea;
          color: #fff;
          padding: 4px 8px;
          border-radius: 4px;
          font-weight: bold;
          margin-right: 10px;
          min-width: 35px;
          text-align: center;
          font-size: 11px;
        }

        .control-hint .action {
          color: #ccc;
        }

        .note-input-area {
          background: rgba(0, 212, 255, 0.1);
          border: 1px solid #00ffcc;
          border-radius: 10px;
          padding: 15px;
          margin-bottom: 15px;
        }

        .note-textarea {
          width: 100%;
          height: 80px;
          background: #0f3460;
          color: #fff;
          border: 1px solid #333;
          border-radius: 5px;
          padding: 10px;
          font-size: 14px;
          margin-bottom: 10px;
          font-family: inherit;
        }

        .add-note-btn, .cancel-btn, .voice-btn {
          background: #667eea;
          color: #fff;
          border: none;
          padding: 8px 12px;
          border-radius: 5px;
          font-size: 12px;
          cursor: pointer;
          margin-right: 5px;
          margin-bottom: 5px;
        }

        .cancel-btn {
          background: #666;
        }

        .voice-btn {
          background: #ff6b6b;
        }

        .message {
          background: rgba(0, 212, 255, 0.2);
          color: #00ffcc;
          padding: 10px;
          border-radius: 8px;
          text-align: center;
          font-size: 12px;
          margin-bottom: 10px;
        }

        .counter {
          text-align: center;
          color: #667eea;
          font-size: 12px;
          font-weight: bold;
        }
      </style>
    </div>
    """
  end

  defp format_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%m/%d")

      _ ->
        date_string
    end
  end
end
