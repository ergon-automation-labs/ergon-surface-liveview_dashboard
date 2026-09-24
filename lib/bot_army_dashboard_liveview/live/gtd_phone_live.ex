defmodule BotArmyDashboardLiveview.GtdPhoneLive do
  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.SyncStatus
  alias BotArmyDashboardLiveview.PhoneNavModal

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        sync_status: SyncStatus.initial(),
        is_online: true,
        state: :projects,
        projects: [],
        tasks: [],
        selected_project_index: 0,
        selected_task_index: 0,
        selected_project: nil,
        selected_task: nil,
        message: nil,
        loading: true,
        show_nav_menu: false,
        search_query: ""
      )
      |> fetch_projects()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_projects(socket) do
    Task.start_link(fn ->
      try do
        case Broker.request("bridge.project.list", Jason.encode!(%{}), timeout: 5000) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"projects" => projects}} ->
                send(self(), {:projects_loaded, projects})

              {:error, _} ->
                send(self(), {:projects_loaded, []})
            end

          {:error, _} ->
            send(self(), {:projects_loaded, []})
        end
      rescue
        _ -> send(self(), {:projects_loaded, []})
      end
    end)

    socket
  end

  defp fetch_tasks(socket, project_id) do
    Task.start_link(fn ->
      try do
        case Broker.request(
               "bridge.task.list",
               Jason.encode!(%{"project_id" => project_id}),
               timeout: 5000
             ) do
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
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info({:projects_loaded, projects}, socket) do
    {:noreply, assign(socket, projects: projects, loading: false, selected_project_index: 0)}
  end

  @impl true
  def handle_info({:tasks_loaded, tasks}, socket) do
    {:noreply, assign(socket, tasks: tasks, selected_task_index: 0)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.state do
      :projects ->
        if Enum.empty?(socket.assigns.projects) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_project_index
          new_idx = max(idx - 1, 0)
          {:noreply, assign(socket, selected_project_index: new_idx, message: nil)}
        end

      :tasks ->
        if Enum.empty?(socket.assigns.tasks) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_task_index
          new_idx = max(idx - 1, 0)
          {:noreply, assign(socket, selected_task_index: new_idx, message: nil)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.state do
      :projects ->
        if Enum.empty?(socket.assigns.projects) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_project_index
          new_idx = min(idx + 1, length(socket.assigns.projects) - 1)
          {:noreply, assign(socket, selected_project_index: new_idx, message: nil)}
        end

      :tasks ->
        if Enum.empty?(socket.assigns.tasks) do
          {:noreply, socket}
        else
          idx = socket.assigns.selected_task_index
          new_idx = min(idx + 1, length(socket.assigns.tasks) - 1)
          {:noreply, assign(socket, selected_task_index: new_idx, message: nil)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.state do
      :projects ->
        project = Enum.at(socket.assigns.projects, socket.assigns.selected_project_index)

        if project do
          {:noreply,
           socket
           |> assign(selected_project: project, state: :tasks)
           |> fetch_tasks(project["id"])}
        else
          {:noreply, socket}
        end

      :tasks ->
        task = Enum.at(socket.assigns.tasks, socket.assigns.selected_task_index)

        if task do
          {:noreply, assign(socket, selected_task: task, state: :actions)}
        else
          {:noreply, socket}
        end

      :actions ->
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.state do
      :projects ->
        {:noreply, socket}

      :tasks ->
        {:noreply, assign(socket, state: :projects, tasks: [])}

      :actions ->
        {:noreply, assign(socket, state: :tasks)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-x", _params, socket) do
    case socket.assigns.state do
      :actions ->
        publish_task_action(socket, socket.assigns.selected_task, "complete")

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-y", _params, socket) do
    case socket.assigns.state do
      :actions ->
        publish_task_action(socket, socket.assigns.selected_task, "defer")

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
    # Open nav menu on long-press
    {:noreply, assign(socket, show_nav_menu: true, search_query: "")}
  end

  @impl true
  def handle_event(
        "quick-action",
        %{"action" => action, "itemId" => item_id, "itemType" => "task"},
        socket
      ) do
    # Handle swipe-to-complete on tasks
    if socket.assigns.state == :tasks do
      task = Enum.find(socket.assigns.tasks, &(&1["id"] == item_id))

      if task do
        publish_task_action(socket, task, action)
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
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

  defp publish_task_action(socket, task, action) do
    Task.start_link(fn ->
      try do
        payload = %{
          "task_id" => task["id"],
          "action" => action,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        subject =
          case action do
            "complete" -> "events.task.completed"
            "defer" -> "events.task.deferred"
            _ -> "events.task.updated"
          end

        case Gnat.pub(:nats_connection, subject, Jason.encode!(payload)) do
          :ok ->
            send(self(), {:action_published, action, task["title"]})

          _ ->
            send(self(), {:action_failed})
        end
      rescue
        _ -> send(self(), {:action_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "#{String.capitalize(action)}ing task...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:action_published, action, title}, socket) do
    emoji = if action == "complete", do: "✓", else: "→"

    {:noreply,
     socket
     |> assign(state: :tasks, selected_task: nil, message: "#{emoji} #{title} #{action}d")
     |> schedule_message_clear(3000)}
  end

  @impl true
  def handle_info({:action_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Failed to update task")
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
    <div id="gtd-phone-container" class="handheld-container gtd-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <PhoneNavModal.modal
        show_menu={@show_nav_menu}
        current_route="/gtd-phone"
        filtered_handhelds={PhoneNavModal.filter_handhelds(@search_query)}
        search_query={@search_query}
      />

      <div class="phone-card gtd-card-phone">
        <div class="view-title">📋 GTD</div>

        <%= if @loading do %>
          <div class="loading-state">
            <div class="spinner"></div>
            <p>Loading projects...</p>
          </div>
        <% else %>
          <%= case @state do %>
            <% :projects -> %>
              <%= if Enum.empty?(@projects) do %>
                <div class="empty-state">
                  <p>No projects found</p>
                </div>
              <% else %>
                <% current_project = Enum.at(@projects, @selected_project_index) %>
                <div class="gtd-section-phone">
                  <div class="section-title">Projects</div>

                  <div class="carousel-hint">
                    <span>↑</span>
                    <span>↓</span>
                  </div>

                  <div class="project-display">
                    <div class="project-name"><%= current_project["name"] %></div>
                    <%= if current_project["description"] do %>
                      <div class="project-description"><%= current_project["description"] %></div>
                    <% end %>
                  </div>

                  <div class="progress-indicator">
                    <%= @selected_project_index + 1 %> of <%= length(@projects) %>
                  </div>

                  <div class="controls">
                    <div class="control-hint">
                      <span class="key">Y</span>
                      <span class="action">View Tasks</span>
                    </div>
                  </div>
                </div>
              <% end %>

            <% :tasks -> %>
              <%= if Enum.empty?(@tasks) do %>
                <div class="empty-state">
                  <p>No tasks in this project</p>
                </div>
              <% else %>
                <% current_task = Enum.at(@tasks, @selected_task_index) %>
                <div class="gtd-section-phone">
                  <div class="section-breadcrumb"><%= @selected_project.name %></div>
                  <div class="section-title">Tasks</div>

                  <div class="carousel-hint">
                    <span>↑</span>
                    <span>↓</span>
                  </div>

                  <div
                    class="task-display"
                    data-swipeable="true"
                    data-item-id={current_task["id"]}
                    data-item-type="task"
                    data-swipe-action="complete"
                  >
                    <div class="task-name"><%= current_task["title"] %></div>
                    <%= if current_task["description"] do %>
                      <div class="task-description"><%= current_task["description"] %></div>
                    <% end %>
                    <div class="swipe-hint">← Swipe to complete</div>
                  </div>

                  <div class="progress-indicator">
                    <%= @selected_task_index + 1 %> of <%= length(@tasks) %>
                  </div>

                  <div class="controls">
                    <div class="control-hint">
                      <span class="key">Y</span>
                      <span class="action">Actions</span>
                    </div>
                    <div class="control-hint">
                      <span class="key">B</span>
                      <span class="action">Back</span>
                    </div>
                  </div>
                </div>
              <% end %>

            <% :actions -> %>
              <div class="gtd-section-phone">
                <div class="section-breadcrumb"><%= @selected_project.name %></div>
                <div class="section-title"><%= @selected_task.title %></div>

                <div class="actions-list">
                  <div class="action-button complete">
                    <div class="action-emoji">✓</div>
                    <div class="action-label">Complete</div>
                    <div class="action-key">X</div>
                  </div>

                  <div class="action-button defer">
                    <div class="action-emoji">→</div>
                    <div class="action-label">Defer</div>
                    <div class="action-key">Y</div>
                  </div>

                  <div class="action-button note">
                    <div class="action-emoji">📝</div>
                    <div class="action-label">Add Note</div>
                    <div class="action-key">A</div>
                  </div>
                </div>

                <div class="controls">
                  <div class="control-hint">
                    <span class="key">B</span>
                    <span class="action">Back</span>
                  </div>
                </div>
              </div>
          <% end %>
        <% end %>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/gtd-phone" />

    <style>
      .gtd-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .gtd-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #3498db;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #3498db;
        text-align: center;
      }

      .gtd-section-phone {
        display: flex;
        flex-direction: column;
        gap: 15px;
      }

      .section-breadcrumb {
        font-size: 11px;
        color: #707070;
        text-transform: uppercase;
        letter-spacing: 1px;
      }

      .section-title {
        font-size: 16px;
        font-weight: bold;
        color: #3498db;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 15px;
        color: #606060;
        font-size: 16px;
      }

      .project-display,
      .task-display {
        background: rgba(52, 152, 219, 0.1);
        border: 1px solid rgba(52, 152, 219, 0.3);
        border-radius: 8px;
        padding: 15px;
      }

      .project-name,
      .task-name {
        font-size: 18px;
        font-weight: bold;
        color: #ecf0f1;
        margin-bottom: 8px;
        word-wrap: break-word;
      }

      .project-description,
      .task-description {
        font-size: 12px;
        color: #b0b0b0;
        line-height: 1.5;
      }

      .swipe-hint {
        font-size: 11px;
        color: #707070;
        margin-top: 12px;
        font-style: italic;
      }

      .progress-indicator {
        font-size: 11px;
        color: #707070;
        text-align: center;
      }

      .actions-list {
        display: grid;
        grid-template-columns: 1fr 1fr 1fr;
        gap: 10px;
        margin: 20px 0;
      }

      .action-button {
        padding: 15px;
        border-radius: 8px;
        text-align: center;
        cursor: pointer;
        transition: all 0.3s ease;
        border: 1px solid rgba(52, 152, 219, 0.3);
      }

      .action-button.complete {
        background: rgba(39, 174, 96, 0.1);
        border-color: rgba(39, 174, 96, 0.3);
      }

      .action-button.complete:hover {
        background: rgba(39, 174, 96, 0.2);
        border-color: #27ae60;
      }

      .action-button.defer {
        background: rgba(155, 89, 182, 0.1);
        border-color: rgba(155, 89, 182, 0.3);
      }

      .action-button.defer:hover {
        background: rgba(155, 89, 182, 0.2);
        border-color: #9b59b6;
      }

      .action-button.note {
        background: rgba(241, 196, 15, 0.1);
        border-color: rgba(241, 196, 15, 0.3);
      }

      .action-button.note:hover {
        background: rgba(241, 196, 15, 0.2);
        border-color: #f1c40f;
      }

      .action-emoji {
        font-size: 24px;
        margin-bottom: 8px;
      }

      .action-label {
        font-size: 12px;
        color: #ecf0f1;
        font-weight: bold;
        margin-bottom: 6px;
      }

      .action-key {
        font-size: 10px;
        color: #707070;
      }

      .controls {
        display: flex;
        flex-direction: column;
        gap: 8px;
        border-top: 1px solid #333;
        border-bottom: 1px solid #333;
        padding: 15px 0;
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
        background: #3498db;
        color: #fff;
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
        background: rgba(52, 152, 219, 0.2);
        border: 1px solid #3498db;
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
        padding: 30px 0;
      }

      .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid #3498db;
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

      .empty-state {
        text-align: center;
        color: #a0a0a0;
        padding: 30px 0;
      }

      @media (max-width: 768px) {
        .gtd-card-phone {
          padding: 15px;
        }

        .project-name,
        .task-name {
          font-size: 16px;
        }

        .actions-list {
          grid-template-columns: 1fr;
        }

        .action-button {
          padding: 12px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
