defmodule BotArmyDashboardLiveview.FitnessPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.SyncStatus

  @workout_types [:run, :walk, :strength, :yoga, :swim, :bike, :sports, :stretch]
  @intensity_levels [:light, :moderate, :intense]

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        sync_status: SyncStatus.initial(),
        is_online: true,
        state: :type,
        selected_type_index: 0,
        selected_intensity_index: 1,
        duration_minutes: 30,
        selected_type: :run,
        selected_intensity: :moderate,
        message: nil,
        workout_types: @workout_types,
        intensity_levels: @intensity_levels
      )
      |> schedule_tick()

    {:ok, socket}
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
      :type ->
        idx = socket.assigns.selected_type_index
        new_idx = max(idx - 1, 0)
        new_type = Enum.at(@workout_types, new_idx)
        {:noreply, assign(socket, selected_type_index: new_idx, selected_type: new_type)}

      :intensity ->
        idx = socket.assigns.selected_intensity_index
        new_idx = max(idx - 1, 0)
        new_intensity = Enum.at(@intensity_levels, new_idx)

        {:noreply,
         assign(socket, selected_intensity_index: new_idx, selected_intensity: new_intensity)}

      :duration ->
        duration = socket.assigns.duration_minutes
        new_duration = max(duration - 5, 5)
        {:noreply, assign(socket, duration_minutes: new_duration)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.state do
      :type ->
        idx = socket.assigns.selected_type_index
        new_idx = min(idx + 1, length(@workout_types) - 1)
        new_type = Enum.at(@workout_types, new_idx)
        {:noreply, assign(socket, selected_type_index: new_idx, selected_type: new_type)}

      :intensity ->
        idx = socket.assigns.selected_intensity_index
        new_idx = min(idx + 1, length(@intensity_levels) - 1)
        new_intensity = Enum.at(@intensity_levels, new_idx)

        {:noreply,
         assign(socket, selected_intensity_index: new_idx, selected_intensity: new_intensity)}

      :duration ->
        duration = socket.assigns.duration_minutes
        new_duration = min(duration + 5, 180)
        {:noreply, assign(socket, duration_minutes: new_duration)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.state do
      :type ->
        {:noreply, assign(socket, state: :intensity, selected_intensity_index: 1)}

      :intensity ->
        {:noreply, assign(socket, state: :duration)}

      :duration ->
        publish_workout(socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.state do
      :type ->
        {:noreply, socket}

      :intensity ->
        {:noreply, assign(socket, state: :type)}

      :duration ->
        {:noreply, assign(socket, state: :intensity)}

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

  defp publish_workout(socket) do
    Task.start_link(fn ->
      try do
        payload = %{
          "type" => to_string(socket.assigns.selected_type),
          "intensity" => to_string(socket.assigns.selected_intensity),
          "duration_minutes" => socket.assigns.duration_minutes,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.fitness.workout_logged", Jason.encode!(payload)) do
          :ok ->
            send(self(), {:workout_logged})

          _ ->
            send(self(), {:publish_failed})
        end
      rescue
        _ -> send(self(), {:publish_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Logging workout...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:workout_logged}, socket) do
    emoji = emoji_for_type(socket.assigns.selected_type)

    {:noreply,
     socket
     |> assign(
       state: :type,
       selected_type_index: 0,
       selected_intensity_index: 1,
       duration_minutes: 30,
       message: "#{emoji} Workout logged!"
     )
     |> schedule_message_clear(3000)}
  end

  @impl true
  def handle_info({:publish_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Failed to log workout")
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

  defp emoji_for_type(:run), do: "🏃"
  defp emoji_for_type(:walk), do: "🚶"
  defp emoji_for_type(:strength), do: "💪"
  defp emoji_for_type(:yoga), do: "🧘"
  defp emoji_for_type(:swim), do: "🏊"
  defp emoji_for_type(:bike), do: "🚴"
  defp emoji_for_type(:sports), do: "⚽"
  defp emoji_for_type(:stretch), do: "🤸"

  defp label_for_type(:run), do: "Run"
  defp label_for_type(:walk), do: "Walk"
  defp label_for_type(:strength), do: "Strength"
  defp label_for_type(:yoga), do: "Yoga"
  defp label_for_type(:swim), do: "Swim"
  defp label_for_type(:bike), do: "Bike"
  defp label_for_type(:sports), do: "Sports"
  defp label_for_type(:stretch), do: "Stretch"

  defp label_for_intensity(:light), do: "Light"
  defp label_for_intensity(:moderate), do: "Moderate"
  defp label_for_intensity(:intense), do: "Intense"

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
    <div id="fitness-phone-container" class="handheld-container fitness-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <div class="phone-card fitness-card-phone">
        <div class="view-title">💪 Log Workout</div>

        <%= case @state do %>
          <% :type -> %>
            <div class="step-header">
              <div class="step-number">1 of 3</div>
              <div class="step-label">Workout Type</div>
            </div>

            <div class="carousel-hint">
              <span>↑</span>
              <span>↓</span>
            </div>

            <div class="workout-type-display">
              <div class="type-emoji"><%= emoji_for_type(@selected_type) %></div>
              <div class="type-name"><%= label_for_type(@selected_type) %></div>
            </div>

            <div class="all-types-hint">
              <%= Enum.map(@workout_types, &emoji_for_type/1) |> Enum.join(" ") %>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Next</span>
              </div>
            </div>

          <% :intensity -> %>
            <div class="step-header">
              <div class="step-number">2 of 3</div>
              <div class="step-label">Intensity</div>
            </div>

            <div class="carousel-hint">
              <span>↑</span>
              <span>↓</span>
            </div>

            <div class="intensity-grid">
              <%= for {intensity, idx} <- Enum.with_index(@intensity_levels) do %>
                <div class={["intensity-option", idx == @selected_intensity_index && "active"]}>
                  <div class="intensity-emoji">
                    <%= if intensity == :light, do: "🌤️" %>
                    <%= if intensity == :moderate, do: "⚡" %>
                    <%= if intensity == :intense, do: "🔥" %>
                  </div>
                  <div class="intensity-label"><%= label_for_intensity(intensity) %></div>
                </div>
              <% end %>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Next</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Back</span>
              </div>
            </div>

          <% :duration -> %>
            <div class="step-header">
              <div class="step-number">3 of 3</div>
              <div class="step-label">Duration</div>
            </div>

            <div class="carousel-hint">
              <span>↑ -5</span>
              <span>↓ +5</span>
            </div>

            <div class="duration-display">
              <div class="duration-number"><%= @duration_minutes %></div>
              <div class="duration-label">minutes</div>
            </div>

            <div class="duration-slider-hint">
              5 min — 180 min
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">Y</span>
                <span class="action">Log It!</span>
              </div>
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

    <PhoneNav.nav current_route="/fitness-phone" />

    <style>
      .fitness-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .fitness-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #e74c3c;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #e74c3c;
        text-align: center;
      }

      .step-header {
        text-align: center;
        margin-bottom: 15px;
      }

      .step-number {
        font-size: 11px;
        color: #e74c3c;
        text-transform: uppercase;
        letter-spacing: 1px;
      }

      .step-label {
        font-size: 18px;
        font-weight: bold;
        color: #ecf0f1;
        margin-top: 5px;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 15px;
        color: #606060;
        font-size: 14px;
        margin: 15px 0;
      }

      .workout-type-display {
        text-align: center;
        padding: 30px 0;
        animation: slideInType 0.4s ease;
      }

      @keyframes slideInType {
        from {
          opacity: 0;
          transform: scale(0.9);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }

      .type-emoji {
        font-size: 56px;
        margin-bottom: 12px;
      }

      .type-name {
        font-size: 24px;
        font-weight: bold;
        color: #ecf0f1;
      }

      .all-types-hint {
        text-align: center;
        font-size: 24px;
        opacity: 0.4;
        margin: 15px 0;
      }

      .intensity-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 10px;
        margin: 25px 0;
      }

      .intensity-option {
        padding: 15px;
        border-radius: 8px;
        background: rgba(231, 76, 60, 0.1);
        border: 1px solid rgba(231, 76, 60, 0.3);
        text-align: center;
        cursor: pointer;
        transition: all 0.3s ease;
      }

      .intensity-option.active {
        background: rgba(231, 76, 60, 0.3);
        border: 2px solid #e74c3c;
        transform: scale(1.08);
        box-shadow: 0 0 15px rgba(231, 76, 60, 0.3);
      }

      .intensity-emoji {
        font-size: 32px;
        margin-bottom: 8px;
      }

      .intensity-label {
        font-size: 12px;
        color: #ecf0f1;
        font-weight: bold;
      }

      .duration-display {
        text-align: center;
        padding: 40px 0;
      }

      .duration-number {
        font-size: 56px;
        font-weight: bold;
        color: #e74c3c;
        font-family: "Courier New", monospace;
      }

      .duration-label {
        font-size: 14px;
        color: #b0b0b0;
        margin-top: 8px;
      }

      .duration-slider-hint {
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
        background: #e74c3c;
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
        background: rgba(231, 76, 60, 0.2);
        border: 1px solid #e74c3c;
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
        .fitness-card-phone {
          padding: 15px;
        }

        .type-emoji {
          font-size: 48px;
        }

        .duration-number {
          font-size: 48px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
