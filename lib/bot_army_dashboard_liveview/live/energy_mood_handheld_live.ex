defmodule BotArmyDashboardLiveview.EnergyMoodHandheldLive do
  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       energy_levels: ["Low", "Medium", "High"],
       moods: ["Focused", "Creative", "Energized", "Calm", "Recovering", "Scattered"],
       selected_energy_index: 1,
       selected_mood_index: 0,
       view_mode: :energy,
       message: nil,
       last_saved: nil
     )
     |> load_last_state()}
  end

  defp load_last_state(socket) do
    # Try to load the last saved state from NATS
    parent = self()

    Task.start_link(fn ->
      try do
        case Broker.request(
               "context.state.query",
               Jason.encode!(%{"type" => "energy_mood"}),
               timeout: 2000
             ) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"energy" => energy, "mood" => mood}} ->
                send(parent, {:state_loaded, energy, mood})

              _ ->
                :ok
            end

          _ ->
            :ok
        end
      rescue
        _ -> :ok
      end
    end)

    socket
  end

  @impl true
  def handle_info({:state_loaded, energy, mood}, socket) do
    energy_index = Enum.find_index(socket.assigns.energy_levels, &(&1 == energy)) || 1
    mood_index = Enum.find_index(socket.assigns.moods, &(&1 == mood)) || 0

    {:noreply,
     socket
     |> assign(selected_energy_index: energy_index, selected_mood_index: mood_index)
     |> assign(last_saved: "Restored previous state")}
  end

  def handle_info({:state_saved, energy, mood}, socket) do
    Logger.info("[EnergyMoodHandheld] Saved state: #{energy}, #{mood}")

    {:noreply,
     socket
     |> assign(message: "✓ Saved")
     |> assign(last_saved: "#{energy} energy, #{mood}")
     |> schedule_message_clear(1500)}
  end

  def handle_info({:save_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Failed to save")
     |> schedule_message_clear(2000)}
  end

  def handle_info(:clear_message, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    case socket.assigns.view_mode do
      :energy ->
        index = max(socket.assigns.selected_energy_index - 1, 0)
        {:noreply, assign(socket, selected_energy_index: index, message: nil)}

      :mood ->
        index = max(socket.assigns.selected_mood_index - 1, 0)
        {:noreply, assign(socket, selected_mood_index: index, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    case socket.assigns.view_mode do
      :energy ->
        count = length(socket.assigns.energy_levels)
        index = min(socket.assigns.selected_energy_index + 1, max(count - 1, 0))
        {:noreply, assign(socket, selected_energy_index: index, message: nil)}

      :mood ->
        count = length(socket.assigns.moods)
        index = min(socket.assigns.selected_mood_index + 1, max(count - 1, 0))
        {:noreply, assign(socket, selected_mood_index: index, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns.view_mode do
      :energy ->
        {:noreply, assign(socket, view_mode: :mood, message: nil)}

      :mood ->
        save_state(socket)
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns.view_mode do
      :energy ->
        {:noreply, socket}

      :mood ->
        {:noreply, assign(socket, view_mode: :energy)}
    end
  end

  defp save_state(socket) do
    energy = Enum.at(socket.assigns.energy_levels, socket.assigns.selected_energy_index)
    mood = Enum.at(socket.assigns.moods, socket.assigns.selected_mood_index)

    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{
          "energy" => energy,
          "mood" => mood,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.context.updated", Jason.encode!(payload)) do
          :ok ->
            send(parent, {:state_saved, energy, mood})

          _ ->
            send(parent, {:save_failed})
        end
      rescue
        _ -> send(parent, {:save_failed})
      end
    end)

    {:noreply, assign(socket, message: "Saving...")}
  end

  defp schedule_message_clear(socket, delay_ms) do
    Process.send_after(self(), :clear_message, delay_ms)
    socket
  end

  defp mood_emoji(mood) do
    case mood do
      "Focused" -> "🎯"
      "Creative" -> "✨"
      "Energized" -> "⚡"
      "Calm" -> "🧘"
      "Recovering" -> "🌙"
      "Scattered" -> "🌀"
      _ -> "•"
    end
  end

  defp energy_emoji(energy) do
    case energy do
      "Low" -> "🔋"
      "Medium" -> "⚙️"
      "High" -> "🔥"
      _ -> "•"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="energy-mood-handheld">
      <div class="handheld-container">
        <%= if @view_mode == :energy do %>
          <div class="energy-view">
            <div class="view-title">Your Energy</div>

            <div class="selector-display">
              <div class="emoji"><%= energy_emoji(Enum.at(@energy_levels, @selected_energy_index)) %></div>

              <div class="levels-list">
                <%= for {level, idx} <- Enum.with_index(@energy_levels) do %>
                  <%= if idx == @selected_energy_index do %>
                    <div class="level-item selected">
                      <span class="level-name"><%= level %></span>
                    </div>
                  <% else %>
                    <div class="level-item">
                      <span class="level-name"><%= level %></span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div class="description">
              <%= case Enum.at(@energy_levels, @selected_energy_index) do %>
                <% "Low" -> %>
                  <p>Resting, recovering, low capacity</p>
                <% "Medium" -> %>
                  <p>Steady state, normal operations</p>
                <% "High" -> %>
                  <p>Energized, ready for challenge</p>
                <% _ -> %>
                  <p>Select your current energy level</p>
              <% end %>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">↑ ↓</span>
                <span class="action">Navigate</span>
              </div>
              <div class="control-hint">
                <span class="key">A</span>
                <span class="action">Next: Mood</span>
              </div>
            </div>

            <%= if @message do %>
              <div class="message"><%= @message %></div>
            <% end %>
          </div>
        <% else %>
          <div class="mood-view">
            <div class="view-title">Your Mood</div>

            <div class="selector-display">
              <div class="emoji"><%= mood_emoji(Enum.at(@moods, @selected_mood_index)) %></div>

              <div class="moods-grid">
                <%= for {mood, idx} <- Enum.with_index(@moods) do %>
                  <%= if idx == @selected_mood_index do %>
                    <div class="mood-item selected">
                      <span class="mood-emoji"><%= mood_emoji(mood) %></span>
                      <span class="mood-name"><%= mood %></span>
                    </div>
                  <% else %>
                    <div class="mood-item">
                      <span class="mood-emoji"><%= mood_emoji(mood) %></span>
                      <span class="mood-name"><%= mood %></span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div class="description">
              <%= case Enum.at(@moods, @selected_mood_index) do %>
                <% "Focused" -> %>
                  <p>Deep work, minimize distractions</p>
                <% "Creative" -> %>
                  <p>Brainstorm, explore, build</p>
                <% "Energized" -> %>
                  <p>Push hard, tackle challenges</p>
                <% "Calm" -> %>
                  <p>Gentle, grounded, present</p>
                <% "Recovering" -> %>
                  <p>Rest, gentle tasks, recharge</p>
                <% "Scattered" -> %>
                  <p>Context-switching, flexible</p>
                <% _ -> %>
                  <p>How are you feeling?</p>
              <% end %>
            </div>

            <div class="controls">
              <div class="control-hint">
                <span class="key">↑ ↓</span>
                <span class="action">Navigate</span>
              </div>
              <div class="control-hint">
                <span class="key">A</span>
                <span class="action">Save</span>
              </div>
              <div class="control-hint">
                <span class="key">B</span>
                <span class="action">Back</span>
              </div>
            </div>

            <%= if @message do %>
              <div class="message"><%= @message %></div>
            <% end %>

            <%= if @last_saved do %>
              <div class="last-saved">Last: <%= @last_saved %></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <style>
        .energy-mood-handheld {
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

        .view-title {
          font-size: 28px;
          font-weight: bold;
          color: #00ff88;
          margin-bottom: 30px;
        }

        .selector-display {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 30px;
          margin-bottom: 20px;
        }

        .emoji {
          font-size: 80px;
          animation: gentle-pulse 2s ease-in-out infinite;
        }

        @keyframes gentle-pulse {
          0%, 100% { transform: scale(1); }
          50% { transform: scale(1.05); }
        }

        .levels-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
          width: 100%;
          max-width: 300px;
        }

        .level-item {
          padding: 16px 20px;
          background: #1a2540;
          border: 2px solid #1e2749;
          border-radius: 8px;
          text-align: center;
          transition: all 0.2s;
          cursor: pointer;
        }

        .level-item.selected {
          background: #1e3540;
          border-color: #00ff88;
          box-shadow: 0 0 12px rgba(0, 255, 136, 0.3);
          transform: scale(1.05);
        }

        .level-name {
          font-size: 16px;
          font-weight: 600;
          color: #e0e0e0;
        }

        .level-item.selected .level-name {
          color: #00ff88;
        }

        .moods-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 12px;
          width: 100%;
          max-width: 400px;
        }

        .mood-item {
          padding: 16px;
          background: #1a2540;
          border: 2px solid #1e2749;
          border-radius: 8px;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 8px;
          transition: all 0.2s;
          cursor: pointer;
        }

        .mood-item.selected {
          background: #1e3540;
          border-color: #00ff88;
          box-shadow: 0 0 12px rgba(0, 255, 136, 0.3);
          transform: scale(1.08);
        }

        .mood-emoji {
          font-size: 32px;
        }

        .mood-name {
          font-size: 12px;
          font-weight: 600;
          color: #aaa;
          text-align: center;
        }

        .mood-item.selected .mood-name {
          color: #00ff88;
        }

        .description {
          text-align: center;
          min-height: 40px;
          margin-bottom: 20px;
        }

        .description p {
          margin: 0;
          font-size: 14px;
          color: #aaa;
          font-style: italic;
        }

        .controls {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
          gap: 8px;
          margin-bottom: 15px;
        }

        .control-hint {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 8px;
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
          padding: 10px 16px;
          border-radius: 6px;
          text-align: center;
          font-size: 13px;
          font-weight: 600;
          margin-bottom: 10px;
        }

        .last-saved {
          text-align: center;
          font-size: 11px;
          color: #666;
          padding-top: 10px;
          border-top: 1px solid #1e2749;
        }
      </style>
    </div>
    """
  end
end
