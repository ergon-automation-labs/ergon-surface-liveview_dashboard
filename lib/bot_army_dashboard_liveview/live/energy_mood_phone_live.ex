defmodule BotArmyDashboardLiveview.EnergyMoodPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  import BotArmyDashboardLiveview.PhoneNav
  import BotArmyDashboardLiveview.SyncStatus

  @energy_levels [:low, :medium, :high]
  @moods [:focused, :creative, :energized, :calm, :recovering, :scattered]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, _} = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        state: :energy,
        selected_energy_index: 1,
        selected_mood_index: 0,
        selected_energy: :medium,
        selected_mood: :focused,
        message: nil,
        energy_levels: @energy_levels,
        moods: @moods
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
      :energy ->
        idx = socket.assigns.selected_energy_index
        new_idx = max(idx - 1, 0)
        new_energy = Enum.at(@energy_levels, new_idx)
        {:noreply, assign(socket, selected_energy_index: new_idx, selected_energy: new_energy)}

      :mood ->
        idx = socket.assigns.selected_mood_index
        new_idx = max(idx - 1, 0)
        new_mood = Enum.at(@moods, new_idx)
        {:noreply, assign(socket, selected_mood_index: new_idx, selected_mood: new_mood)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.state do
      :energy ->
        idx = socket.assigns.selected_energy_index
        new_idx = min(idx + 1, length(@energy_levels) - 1)
        new_energy = Enum.at(@energy_levels, new_idx)
        {:noreply, assign(socket, selected_energy_index: new_idx, selected_energy: new_energy)}

      :mood ->
        idx = socket.assigns.selected_mood_index
        new_idx = min(idx + 1, length(@moods) - 1)
        new_mood = Enum.at(@moods, new_idx)
        {:noreply, assign(socket, selected_mood_index: new_idx, selected_mood: new_mood)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.state do
      :energy ->
        {:noreply, assign(socket, state: :mood, selected_mood_index: 0, message: nil)}

      :mood ->
        publish_energy_mood(socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    {:noreply, assign(socket, state: :energy, selected_energy_index: 1, message: nil)}
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
    case socket.assigns.state do
      :energy -> handle_event("gamepad-a", %{}, socket)
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("swipe-right", _params, socket) do
    case socket.assigns.state do
      :mood -> handle_event("gamepad-b", %{}, socket)
      _ -> {:noreply, socket}
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

  defp publish_energy_mood(socket) do
    Task.start_link(fn ->
      try do
        payload = %{
          "energy" => to_string(socket.assigns.selected_energy),
          "mood" => to_string(socket.assigns.selected_mood),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.context.updated", Jason.encode!(payload)) do
          :ok ->
            send(self(), {:context_updated})

          _ ->
            send(self(), {:publish_failed})
        end
      rescue
        _ -> send(self(), {:publish_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Saving context...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:context_updated}, socket) do
    energy_emoji = emoji_for_energy(socket.assigns.selected_energy)
    mood_emoji = emoji_for_mood(socket.assigns.selected_mood)

    {:noreply,
     socket
     |> assign(
       state: :energy,
       selected_energy_index: 1,
       message: "#{energy_emoji} #{mood_emoji} Context saved"
     )
     |> schedule_message_clear(3000)}
  end

  @impl true
  def handle_info({:publish_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Failed to save")
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

  defp emoji_for_energy(:low), do: "🔋"
  defp emoji_for_energy(:medium), do: "⚡"
  defp emoji_for_energy(:high), do: "🚀"

  defp emoji_for_mood(:focused), do: "🎯"
  defp emoji_for_mood(:creative), do: "🎨"
  defp emoji_for_mood(:energized), do: "✨"
  defp emoji_for_mood(:calm), do: "🌊"
  defp emoji_for_mood(:recovering), do: "🌙"
  defp emoji_for_mood(:scattered), do: "🌪️"

  defp label_for_energy(:low), do: "Low"
  defp label_for_energy(:medium), do: "Medium"
  defp label_for_energy(:high), do: "High"

  defp label_for_mood(:focused), do: "Focused"
  defp label_for_mood(:creative), do: "Creative"
  defp label_for_mood(:energized), do: "Energized"
  defp label_for_mood(:calm), do: "Calm"
  defp label_for_mood(:recovering), do: "Recovering"
  defp label_for_mood(:scattered), do: "Scattered"

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
    <div id="energy-mood-phone-container" class="handheld-container energy-mood-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <div class="phone-card energy-mood-card-phone">
        <div class="view-title">🌡️ How Are You?</div>

        <%= case @state do %>
          <% :energy -> %>
            <div class="energy-selection-phone">
              <div class="section-label">Energy Level</div>

              <div class="carousel-hint">
                <span>↑</span>
                <span>↓</span>
              </div>

              <div class="energy-display-phone">
                <%= for {energy, idx} <- Enum.with_index(@energy_levels) do %>
                  <%= if idx == @selected_energy_index do %>
                    <div class="energy-item active">
                      <div class="energy-emoji"><%= emoji_for_energy(energy) %></div>
                      <div class="energy-label"><%= label_for_energy(energy) %></div>
                    </div>
                  <% else %>
                    <div class="energy-item inactive">
                      <div class="energy-emoji opacity-50"><%= emoji_for_energy(energy) %></div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <div class="selection-guide">
                <%= emoji_for_energy(@selected_energy) %> <%= label_for_energy(@selected_energy) %>
              </div>

              <div class="controls">
                <div class="control-hint">
                  <span class="key">Y</span>
                  <span class="action">Next: Mood</span>
                </div>
              </div>
            </div>

          <% :mood -> %>
            <div class="mood-selection-phone">
              <div class="section-label">What's Your Mood?</div>

              <div class="carousel-hint">
                <span>↑</span>
                <span>↓</span>
              </div>

              <div class="mood-grid-phone">
                <%= for {mood, idx} <- Enum.with_index(@moods) do %>
                  <div class={["mood-button", idx == @selected_mood_index && "active"]}>
                    <div class="mood-emoji"><%= emoji_for_mood(mood) %></div>
                    <div class="mood-label"><%= label_for_mood(mood) %></div>
                  </div>
                <% end %>
              </div>

              <div class="controls">
                <div class="control-hint">
                  <span class="key">Y</span>
                  <span class="action">Save Context</span>
                </div>
                <div class="control-hint">
                  <span class="key">B</span>
                  <span class="action">Back</span>
                </div>
              </div>
            </div>
        <% end %>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/energy-mood-phone" />

    <style>
      .energy-mood-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .energy-mood-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #9b59b6;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #9b59b6;
        text-align: center;
      }

      .section-label {
        font-size: 12px;
        color: #9b59b6;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 15px;
        text-align: center;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 15px;
        color: #606060;
        font-size: 16px;
        margin-bottom: 20px;
      }

      .energy-display-phone {
        display: flex;
        justify-content: space-around;
        align-items: center;
        min-height: 150px;
        margin: 20px 0;
      }

      .energy-item {
        text-align: center;
        padding: 15px;
        transition: all 0.3s ease;
      }

      .energy-item.active {
        transform: scale(1.2);
        opacity: 1;
      }

      .energy-item.inactive {
        opacity: 0.4;
      }

      .energy-emoji {
        font-size: 40px;
        margin-bottom: 8px;
      }

      .energy-label {
        font-size: 12px;
        color: #ecf0f1;
        font-weight: bold;
      }

      .opacity-50 {
        opacity: 0.5;
      }

      .selection-guide {
        text-align: center;
        font-size: 18px;
        font-weight: bold;
        color: #9b59b6;
        margin: 20px 0;
      }

      .mood-grid-phone {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 12px;
        margin: 20px 0;
      }

      .mood-button {
        padding: 15px;
        border-radius: 8px;
        background: rgba(155, 89, 182, 0.1);
        border: 1px solid rgba(155, 89, 182, 0.3);
        text-align: center;
        cursor: pointer;
        transition: all 0.3s ease;
      }

      .mood-button.active {
        background: rgba(155, 89, 182, 0.3);
        border: 2px solid #9b59b6;
        transform: scale(1.05);
        box-shadow: 0 0 15px rgba(155, 89, 182, 0.3);
      }

      .mood-emoji {
        font-size: 32px;
        margin-bottom: 8px;
      }

      .mood-label {
        font-size: 11px;
        color: #ecf0f1;
        font-weight: bold;
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
        background: #9b59b6;
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
        background: rgba(155, 89, 182, 0.2);
        border: 1px solid #9b59b6;
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
        .energy-mood-card-phone {
          padding: 15px;
        }

        .mood-grid-phone {
          grid-template-columns: repeat(3, 1fr);
          gap: 10px;
        }

        .mood-button {
          padding: 12px;
        }

        .mood-emoji {
          font-size: 28px;
        }

        .energy-emoji {
          font-size: 36px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
