defmodule BotArmyDashboardLiveview.QuestStatusLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.QuestPayload

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        quest: nil,
        narrative: nil,
        images: nil,
        quest_type: nil,
        quest_metadata: nil,
        mechanics: nil,
        current_image_index: 0,
        next_quest_preview: nil,
        message: nil,
        loading: true,
        narrative_loading: false
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
          case Gnat.request(:nats_connection, "bridge.quest.current", Jason.encode!(%{}),
                 timeout: 5000
               ) do
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

  defp fetch_narrative(socket, quest) do
    task_id = quest["id"]
    parent = self()

    Task.start_link(fn ->
      result =
        try do
          payload = %{
            "task_id" => task_id,
            "force" => false,
            "user_id" => "abby"
          }

          case Gnat.request(:nats_connection, "bridge.narrative.refresh", Jason.encode!(payload),
                 receive_timeout: 5000
               ) do
            {:ok, %{body: body}} ->
              response = Jason.decode!(body)
              response["narrative"] || nil

            {:error, _} ->
              nil
          end
        rescue
          _ -> nil
        end

      send(parent, {:narrative_loaded, result})
    end)

    assign(socket, narrative_loading: true)
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info({:quest_loaded, quest}, socket) do
    socket =
      socket
      |> assign(quest: quest, loading: false)
      |> then(fn s ->
        if quest, do: fetch_narrative(s, quest), else: s
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:narrative_loaded, response}, socket) when is_map(response) do
    narrative = response["narrative"]
    images = response["images"]
    quest_type = response["quest_type"] || :combat
    quest_metadata = response["quest_metadata"] || %{}
    mechanics = response["mechanics"] || %{}

    socket =
      socket
      |> assign(
        narrative: narrative,
        images: images,
        quest_type: quest_type,
        quest_metadata: quest_metadata,
        mechanics: mechanics,
        current_image_index: 0,
        narrative_loading: false
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:narrative_loaded, narrative}, socket) do
    {:noreply, assign(socket, narrative: narrative, narrative_loading: false)}
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

  @impl true
  def handle_event("gamepad-x", _params, socket) do
    if socket.assigns.quest do
      task_id = socket.assigns.quest["id"]
      parent = self()

      Task.start_link(fn ->
        payload = %{
          "task_id" => task_id,
          "force" => true,
          "user_id" => "abby"
        }

        result =
          try do
            case Gnat.request(
                   :nats_connection,
                   "bridge.narrative.refresh",
                   Jason.encode!(payload),
                   receive_timeout: 5000
                 ) do
              {:ok, %{body: body}} ->
                response = Jason.decode!(body)
                response["narrative"] || nil

              {:error, _} ->
                nil
            end
          rescue
            _ -> nil
          end

        send(parent, {:narrative_loaded, result})
      end)

      {:noreply, assign(socket, narrative_loading: true)}
    else
      {:noreply, socket}
    end
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

  defp render_quest_type_narrative(quest_type, narrative, metadata, mechanics, quest) do
    case quest_type do
      :combat -> render_combat_narrative(narrative, metadata, mechanics, quest)
      :reflection -> render_reflection_narrative(narrative, metadata, mechanics)
      :maintenance -> render_maintenance_narrative(narrative, metadata)
      :exploration -> render_exploration_narrative(narrative, metadata)
      :collaboration -> render_collaboration_narrative(narrative, metadata)
      :creation -> render_creation_narrative(narrative, metadata)
      _ -> render_default_narrative(narrative)
    end
  end

  defp render_combat_narrative(narrative, metadata, mechanics, quest) do
    assigns = %{narrative: narrative, metadata: metadata, mechanics: mechanics, quest: quest}
    {completed, total} = calculate_progress(quest)
    progress_percent = if total > 0, do: div(completed * 100, total), else: 0
    difficulty = mechanics["difficulty"] || 1
    max_hp = mechanics["max_hp"] || 10

    remaining_hp =
      if max_hp > 0, do: max(1, max_hp - div(max_hp * progress_percent, 100)), else: 1

    hp_percent = div(remaining_hp * 100, max_hp)

    ~H"""
    <div class="narrative-section combat">
      <div class="quest-type-indicator">⚔️ <%= @metadata["emoji"] %> BOSS FIGHT</div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Attack:</span> <%= @narrative["beat_next"] %></div>
      
      <div class="boss-hp-section">
        <div class="hp-label">Enemy Health</div>
        <div class="hp-bar-container">
          <div class="hp-bar-fill" style={"width: #{hp_percent}%"}></div>
        </div>
        <div class="hp-text"><%= remaining_hp %> / <%= max_hp %> HP</div>
      </div>
    </div>
    """
  end

  defp render_reflection_narrative(narrative, metadata, mechanics) do
    assigns = %{narrative: narrative, metadata: metadata, mechanics: mechanics || %{}}

    ~H"""
    <div class="narrative-section reflection">
      <div class="quest-type-indicator">🪞 <%= @metadata["emoji"] %> REFLECTION</div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><em><%= @narrative["scene_flavor"] %></em></div>
      <div class="beat-next"><span class="beat-label">Consider:</span> <%= @narrative["beat_next"] %></div>

      <%= if @mechanics["reflection_prompts"] && length(@mechanics["reflection_prompts"]) > 0 do %>
        <div class="reflection-prompts-section">
          <div class="prompts-label">Companion asks:</div>
          <div class="prompts-list">
            <%= for prompt <- Enum.take(@mechanics["reflection_prompts"], 3) do %>
              <div class="prompt-item">• <%= prompt %></div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_maintenance_narrative(narrative, metadata) do
    assigns = %{narrative: narrative, metadata: metadata}

    ~H"""
    <div class="narrative-section maintenance">
      <div class="quest-type-indicator">🔥 <%= @metadata["emoji"] %></div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Ritual:</span> <%= @narrative["beat_next"] %></div>
    </div>
    """
  end

  defp render_exploration_narrative(narrative, metadata) do
    assigns = %{narrative: narrative, metadata: metadata}

    ~H"""
    <div class="narrative-section exploration">
      <div class="quest-type-indicator">🗺️ <%= @metadata["emoji"] %></div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Discover:</span> <%= @narrative["beat_next"] %></div>
    </div>
    """
  end

  defp render_collaboration_narrative(narrative, metadata) do
    assigns = %{narrative: narrative, metadata: metadata}

    ~H"""
    <div class="narrative-section collaboration">
      <div class="quest-type-indicator">🤝 <%= @metadata["emoji"] %></div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Connect:</span> <%= @narrative["beat_next"] %></div>
    </div>
    """
  end

  defp render_creation_narrative(narrative, metadata) do
    assigns = %{narrative: narrative, metadata: metadata}

    ~H"""
    <div class="narrative-section creation">
      <div class="quest-type-indicator">🔨 <%= @metadata["emoji"] %></div>
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Craft:</span> <%= @narrative["beat_next"] %></div>
    </div>
    """
  end

  defp render_default_narrative(narrative) do
    assigns = %{narrative: narrative}

    ~H"""
    <div class="narrative-section">
      <div class="quest-title-narrative"><%= @narrative["quest_title"] %></div>
      <div class="scene-flavor"><%= @narrative["scene_flavor"] %></div>
      <div class="beat-next"><span class="beat-label">Next:</span> <%= @narrative["beat_next"] %></div>
    </div>
    """
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
          <% emotional_frame = @narrative && @narrative["emotional_frame"] || "neutral" %>
          <div class="quest-card" data-emotion={emotional_frame}>
            <div class="view-title">⚔️ Your Quest</div>

            <%= if @images and @images["urls"] and length(@images["urls"]) > 0 do %>
              <% current_image_url = Enum.at(@images["urls"], @current_image_index) %>
              <% image_count = length(@images["urls"]) %>
              <div class="quest-image-section">
                <div class="quest-image">
                  <img src={current_image_url} alt={"Scene: #{@images["emotional_frame"]}"} />
                </div>
                <%= if image_count > 1 do %>
                  <div class="image-indicator">
                    <%= @current_image_index + 1 %> / <%= image_count %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%= if @narrative_loading do %>
              <div class="narrative-loading">
                <div class="spinner-small"></div>
                <p>Weaving narrative...</p>
              </div>
            <% else %>
              <%= if @narrative do %>
                <%= render_quest_type_narrative(@quest_type, @narrative, @quest_metadata, @mechanics, @quest) %>
              <% end %>
            <% end %>

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
                <span class="key">X</span>
                <span class="action">Rewrite Scene</span>
              </div>
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

      .quest-card[data-emotion="hopeful"] {
        border-color: #4ade80;
        box-shadow: 0 8px 32px rgba(74, 222, 128, 0.2);
      }

      .quest-card[data-emotion="playful"] {
        border-color: #fbbf24;
        box-shadow: 0 8px 32px rgba(251, 191, 36, 0.2);
      }

      .quest-card[data-emotion="defiant"] {
        border-color: #ef4444;
        box-shadow: 0 8px 32px rgba(239, 68, 68, 0.2);
      }

      .quest-card[data-emotion="tender"] {
        border-color: #ec4899;
        box-shadow: 0 8px 32px rgba(236, 72, 153, 0.2);
      }

      .quest-card[data-emotion="melancholic_resolve"] {
        border-color: #8b5cf6;
        box-shadow: 0 8px 32px rgba(139, 92, 246, 0.2);
      }

      .quest-card[data-emotion="weary_but_moving"] {
        border-color: #60a5fa;
        box-shadow: 0 8px 32px rgba(96, 165, 250, 0.2);
      }

      .quest-image-section {
        position: relative;
        margin: 20px 0;
        border-radius: 6px;
        overflow: hidden;
        box-shadow: 0 4px 12px rgba(255, 215, 0, 0.15);
      }

      .quest-image {
        width: 100%;
        aspect-ratio: 16 / 9;
        background: rgba(0, 0, 0, 0.3);
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }

      .quest-image img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .image-indicator {
        position: absolute;
        bottom: 10px;
        right: 12px;
        background: rgba(0, 0, 0, 0.7);
        color: #ffd700;
        padding: 4px 10px;
        border-radius: 3px;
        font-size: 12px;
        font-weight: bold;
      }

      .narrative-section {
        background: rgba(255, 215, 0, 0.05);
        border-left: 3px solid #ffd700;
        padding: 15px;
        margin: 20px 0;
        border-radius: 4px;
        animation: narrativeSlideIn 0.5s ease;
      }

      .narrative-section.combat {
        background: rgba(239, 68, 68, 0.08);
        border-left-color: #ef4444;
        border-left-width: 4px;
      }

      .narrative-section.reflection {
        background: rgba(139, 92, 246, 0.08);
        border-left-color: #8b5cf6;
      }

      .narrative-section.maintenance {
        background: rgba(245, 158, 11, 0.08);
        border-left-color: #f59e0b;
      }

      .narrative-section.exploration {
        background: rgba(6, 182, 212, 0.08);
        border-left-color: #06b6d4;
      }

      .narrative-section.collaboration {
        background: rgba(16, 185, 129, 0.08);
        border-left-color: #10b981;
      }

      .narrative-section.creation {
        background: rgba(249, 115, 22, 0.08);
        border-left-color: #f97316;
      }

      .quest-type-indicator {
        font-size: 14px;
        font-weight: bold;
        margin-bottom: 8px;
        opacity: 0.8;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }

      @keyframes narrativeSlideIn {
        from {
          opacity: 0;
          transform: translateX(-10px);
        }
        to {
          opacity: 1;
          transform: translateX(0);
        }
      }

      .quest-title-narrative {
        font-size: 18px;
        font-weight: bold;
        color: #ffd700;
        margin-bottom: 10px;
        text-transform: uppercase;
        letter-spacing: 1px;
      }

      .scene-flavor {
        font-size: 13px;
        color: #d4d4d4;
        margin-bottom: 12px;
        line-height: 1.5;
        font-style: italic;
      }

      .beat-next {
        font-size: 12px;
        color: #b0b0b0;
        background: rgba(0, 0, 0, 0.3);
        padding: 8px;
        border-radius: 3px;
        margin-top: 10px;
      }

      .beat-label {
        display: block;
        font-size: 10px;
        text-transform: uppercase;
        color: #ffd700;
        letter-spacing: 0.5px;
        margin-bottom: 4px;
      }

      .narrative-loading {
        text-align: center;
        padding: 15px;
        color: #ffd700;
      }

      .spinner-small {
        width: 20px;
        height: 20px;
        border: 2px solid #ffd700;
        border-top-color: transparent;
        border-radius: 50%;
        animation: spin 1s linear infinite;
        margin: 0 auto 10px;
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

      .boss-hp-section {
        background: rgba(239, 68, 68, 0.15);
        border: 1px solid #ef4444;
        border-radius: 4px;
        padding: 12px;
        margin-top: 15px;
      }

      .hp-label {
        font-size: 11px;
        text-transform: uppercase;
        color: #ef4444;
        letter-spacing: 0.5px;
        margin-bottom: 8px;
        font-weight: bold;
      }

      .hp-bar-container {
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid #ef4444;
        border-radius: 3px;
        height: 16px;
        overflow: hidden;
        margin-bottom: 8px;
      }

      .hp-bar-fill {
        background: linear-gradient(90deg, #ef4444, #dc2626);
        height: 100%;
        transition: width 0.3s ease;
      }

      .hp-text {
        font-size: 12px;
        color: #ef4444;
        text-align: center;
        font-weight: bold;
      }

      .reflection-prompts-section {
        background: rgba(139, 92, 246, 0.15);
        border: 1px solid #8b5cf6;
        border-radius: 4px;
        padding: 12px;
        margin-top: 15px;
      }

      .prompts-label {
        font-size: 11px;
        text-transform: uppercase;
        color: #8b5cf6;
        letter-spacing: 0.5px;
        margin-bottom: 10px;
        font-weight: bold;
      }

      .prompts-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .prompt-item {
        font-size: 13px;
        color: #d4d4d4;
        line-height: 1.4;
        padding: 4px 0;
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
