defmodule BotArmyDashboardLiveview.SystemHealthPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  import BotArmyDashboardLiveview.PhoneNav

  @impl true
  def mount(_params, _session, socket) do
    {:ok, _} = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        bots: [],
        selected_bot_index: 0,
        nats_status: :checking,
        message: nil,
        loading: true
      )
      |> fetch_bot_health()
      |> fetch_nats_status()
      |> schedule_tick()

    {:ok, socket}
  end

  defp fetch_bot_health(socket) do
    Task.start_link(fn ->
      try do
        case Gnat.request(:nats_connection, "system.health.bots", Jason.encode!(%{}),
               timeout: 5000
             ) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"bots" => bots}} ->
                send(self(), {:bots_loaded, bots})

              {:error, _} ->
                send(self(), {:bots_loaded, []})
            end

          {:error, _} ->
            send(self(), {:bots_loaded, []})
        end
      rescue
        _ -> send(self(), {:bots_loaded, []})
      end
    end)

    socket
  end

  defp fetch_nats_status(socket) do
    Task.start_link(fn ->
      try do
        case Gnat.request(:nats_connection, "system.health.nats", Jason.encode!(%{}),
               timeout: 2000
             ) do
          {:ok, _} ->
            send(self(), {:nats_status, :healthy})

          {:error, _} ->
            send(self(), {:nats_status, :unhealthy})
        end
      rescue
        _ -> send(self(), {:nats_status, :unhealthy})
      end
    end)

    socket
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 1000)
    socket
  end

  @impl true
  def handle_info({:bots_loaded, bots}, socket) do
    {:noreply, assign(socket, bots: bots, loading: false)}
  end

  @impl true
  def handle_info({:nats_status, status}, socket) do
    {:noreply, assign(socket, nats_status: status)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    if Enum.empty?(socket.assigns.bots) do
      {:noreply, socket}
    else
      idx = socket.assigns.selected_bot_index
      new_idx = max(idx - 1, 0)
      {:noreply, assign(socket, selected_bot_index: new_idx, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    if Enum.empty?(socket.assigns.bots) do
      {:noreply, socket}
    else
      idx = socket.assigns.selected_bot_index
      new_idx = min(idx + 1, length(socket.assigns.bots) - 1)
      {:noreply, assign(socket, selected_bot_index: new_idx, message: nil)}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    {:noreply, assign(socket, message: nil)}
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
  def handle_event("tap", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    {:noreply, socket}
  end

  defp health_status_emoji(status) when is_binary(status) do
    case String.downcase(status) do
      "healthy" -> "✅"
      "degraded" -> "⚠️"
      "unhealthy" -> "❌"
      _ -> "❓"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="system-health-phone-container" class="handheld-container system-health-phone" phx-hook="TouchCarousel">
      <div class="phone-card system-health-card-phone">
        <div class="view-title">⚙️ System Health</div>

        <%= if @loading do %>
          <div class="loading-state">
            <div class="spinner"></div>
            <p>Checking system...</p>
          </div>
        <% else %>
          <div class="health-overview">
            <div class="nats-status">
              <div class="status-label">NATS</div>
              <div class="status-indicator">
                <%= if @nats_status == :healthy do %>
                  <span class="status-badge healthy">🟢 Connected</span>
                <% else %>
                  <span class="status-badge unhealthy">🔴 Offline</span>
                <% end %>
              </div>
            </div>
          </div>

          <%= if Enum.empty?(@bots) do %>
            <div class="empty-state">
              <p>No bots found</p>
            </div>
          <% else %>
            <% current_bot = Enum.at(@bots, @selected_bot_index) %>
            <div class="bot-health-display">
              <div class="bot-name"><%= current_bot["name"] || current_bot["id"] %></div>

              <div class="status-badge-large">
                <%= health_status_emoji(current_bot["status"]) %>
                <%= String.capitalize(current_bot["status"] || "unknown") %>
              </div>

              <%= if current_bot["uptime"] do %>
                <div class="bot-stat">
                  <span class="stat-label">Uptime</span>
                  <span class="stat-value"><%= current_bot["uptime"] %></span>
                </div>
              <% end %>

              <%= if current_bot["last_heartbeat"] do %>
                <div class="bot-stat">
                  <span class="stat-label">Last Heartbeat</span>
                  <span class="stat-value"><%= current_bot["last_heartbeat"] %></span>
                </div>
              <% end %>

              <div class="carousel-hint">
                <span>↑</span>
                <span>↓</span>
              </div>

              <div class="progress-indicator">
                <%= @selected_bot_index + 1 %> of <%= length(@bots) %>
              </div>
            </div>
          <% end %>
        <% end %>

        <div class="controls">
          <div class="control-hint">
            <span class="key">⟳</span>
            <span class="action">Refresh</span>
          </div>
          <div class="control-hint">
            <span class="key">B</span>
            <span class="action">Close</span>
          </div>
        </div>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/system-health-phone" />

    <style>
      .system-health-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .system-health-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #27ae60;
        border-radius: 12px;
        padding: 20px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        margin-bottom: 15px;
        color: #27ae60;
        text-align: center;
      }

      .health-overview {
        background: rgba(39, 174, 96, 0.1);
        border: 1px solid rgba(39, 174, 96, 0.3);
        border-radius: 8px;
        padding: 15px;
        margin-bottom: 20px;
      }

      .nats-status {
        text-align: center;
      }

      .status-label {
        font-size: 11px;
        color: #27ae60;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 8px;
      }

      .status-indicator {
        margin: 0;
      }

      .status-badge {
        display: inline-block;
        padding: 8px 12px;
        border-radius: 16px;
        font-size: 13px;
        font-weight: bold;
      }

      .status-badge.healthy {
        background: rgba(39, 174, 96, 0.2);
        color: #27ae60;
        border: 1px solid #27ae60;
      }

      .status-badge.unhealthy {
        background: rgba(231, 76, 60, 0.2);
        color: #e74c3c;
        border: 1px solid #e74c3c;
      }

      .bot-health-display {
        text-align: center;
        padding: 20px 0;
        animation: fadeIn 0.3s ease;
      }

      @keyframes fadeIn {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }

      .bot-name {
        font-size: 20px;
        font-weight: bold;
        color: #ecf0f1;
        margin-bottom: 15px;
        word-wrap: break-word;
      }

      .status-badge-large {
        font-size: 24px;
        font-weight: bold;
        margin: 15px 0;
        padding: 12px;
        background: rgba(39, 174, 96, 0.1);
        border-radius: 8px;
        color: #27ae60;
      }

      .bot-stat {
        display: flex;
        justify-content: space-between;
        padding: 8px 0;
        border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        font-size: 12px;
      }

      .bot-stat:last-child {
        border-bottom: none;
      }

      .stat-label {
        color: #b0b0b0;
      }

      .stat-value {
        color: #ecf0f1;
        font-weight: bold;
        font-family: "Courier New", monospace;
      }

      .carousel-hint {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 15px;
        color: #606060;
        font-size: 16px;
        margin: 15px 0;
      }

      .progress-indicator {
        font-size: 11px;
        color: #707070;
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
        background: #27ae60;
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
        background: rgba(39, 174, 96, 0.2);
        border: 1px solid #27ae60;
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
        border: 3px solid #27ae60;
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
        .system-health-card-phone {
          padding: 15px;
        }

        .bot-name {
          font-size: 18px;
        }

        .bot-stat {
          font-size: 11px;
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
