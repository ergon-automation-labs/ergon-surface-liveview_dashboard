defmodule BotArmyDashboardLiveview.SystemHealthHandheldLive do
  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       bots: [],
       selected_bot_index: 0,
       view_mode: :bots,
       loading: true,
       message: nil,
       nats_status: :unknown,
       system_metrics: %{}
     )
     |> fetch_bots_and_health()}
  end

  defp fetch_bots_and_health(socket) do
    Task.start_link(fn ->
      try do
        case Broker.request("bot_army.registry.bots.list", Jason.encode!({}), timeout: 5000) do
          {:ok, %{body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"data" => %{"bots" => bot_list}}} when is_list(bot_list) ->
                send(self(), {:bots_loaded, bot_list})

              {:ok, %{"data" => bot_list}} when is_list(bot_list) ->
                send(self(), {:bots_loaded, bot_list})

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

  @impl true
  def handle_info({:bots_loaded, bots}, socket) do
    formatted_bots =
      Enum.map(bots, fn bot ->
        %{
          name: bot["name"] || "Unknown",
          status: derive_status(bot),
          last_heartbeat: bot["last_heartbeat"],
          subjects: bot["subjects"] || []
        }
      end)

    {:noreply,
     socket
     |> assign(bots: formatted_bots, loading: false, nats_status: :connected)
     |> assign(message: if(Enum.empty?(formatted_bots), do: "No bots found", else: nil))}
  end

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    count = length(socket.assigns.bots)

    if count > 0 do
      index = max(socket.assigns.selected_bot_index - 1, 0)
      {:noreply, assign(socket, selected_bot_index: index, message: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    count = length(socket.assigns.bots)

    if count > 0 do
      index = min(socket.assigns.selected_bot_index + 1, max(count - 1, 0))
      {:noreply, assign(socket, selected_bot_index: index, message: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    bot = Enum.at(socket.assigns.bots, socket.assigns.selected_bot_index)

    if bot do
      {:noreply, assign(socket, view_mode: :bot_detail, message: "#{bot.name}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    if socket.assigns.view_mode == :bot_detail do
      {:noreply, assign(socket, view_mode: :bots)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("gamepad-x", _params, socket) do
    {:noreply, assign(socket, :message, "Refreshing health...")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="system-health-handheld">
      <div class="handheld-container">
        <%= if @loading do %>
          <div class="loading-state">
            <div class="spinner"></div>
            <p>Loading bot health...</p>
          </div>
        <% else %>
          <%= if @view_mode == :bots do %>
            <div class="bots-view">
              <div class="view-title">Bot Health 🏥</div>

              <div class="nats-status">
                <%= if @nats_status == :connected do %>
                  <span class="status-badge healthy">🟢 NATS Connected</span>
                <% else %>
                  <span class="status-badge error">🔴 NATS Offline</span>
                <% end %>
              </div>

              <%= if Enum.empty?(@bots) do %>
                <div class="empty-state">
                  <p><%= @message || "No bots found" %></p>
                </div>
              <% else %>
                <div class="item-list">
                  <%= for {bot, idx} <- Enum.with_index(@bots) do %>
                    <%= if idx == @selected_bot_index do %>
                      <div class="current-item selected">
                        <div class="item-header">
                          <span class={["status-indicator", bot.status]}><%= status_emoji(bot.status) %></span>
                          <div class="item-title"><%= bot.name %></div>
                        </div>
                        <div class="item-meta">
                          <span class="status-badge"><%= bot.status %></span>
                          <%= if bot.last_heartbeat do %>
                            <span class="heartbeat">#{format_heartbeat(bot.last_heartbeat)}</span>
                          <% end %>
                        </div>
                      </div>
                    <% else %>
                      <div class="current-item">
                        <div class="item-header">
                          <span class={["status-indicator", bot.status]}><%= status_emoji(bot.status) %></span>
                          <div class="item-title"><%= bot.name %></div>
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
                    <span class="action">Details</span>
                  </div>
                  <div class="control-hint">
                    <span class="key">X</span>
                    <span class="action">Refresh</span>
                  </div>
                </div>

                <%= if @message do %>
                  <div class="message"><%= @message %></div>
                <% end %>

                <div class="counter">
                  <%= @selected_bot_index + 1 %> / <%= length(@bots) %>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="detail-view">
              <div class="view-title">
                <span><%= status_emoji(Enum.at(@bots, @selected_bot_index, %{}).status) %></span>
                <span><%= Enum.at(@bots, @selected_bot_index, %{}).name %></span>
              </div>

              <div class="detail-content">
                <div class="detail-section">
                  <div class="section-label">Status</div>
                  <div class="section-value">
                    <span class={["status-badge", Enum.at(@bots, @selected_bot_index, %{}).status]}>
                      <%= Enum.at(@bots, @selected_bot_index, %{}).status %>
                    </span>
                  </div>
                </div>

                <div class="detail-section">
                  <div class="section-label">Last Heartbeat</div>
                  <div class="section-value">
                    <%= format_heartbeat(Enum.at(@bots, @selected_bot_index, %{}).last_heartbeat) %>
                  </div>
                </div>

                <div class="detail-section">
                  <div class="section-label">Subjects</div>
                  <div class="section-value">
                    <%= if Enum.empty?(Enum.at(@bots, @selected_bot_index, %{}).subjects || []) do %>
                      <p class="muted">—</p>
                    <% else %>
                      <div class="subject-list">
                        <%= for subject <- Enum.take(Enum.at(@bots, @selected_bot_index, %{}).subjects || [], 3) do %>
                          <div class="subject-item"><%= subject %></div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
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

      <style>
        .system-health-handheld {
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
          padding: 20px;
          overflow: hidden;
        }

        .loading-state {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          gap: 20px;
        }

        .spinner {
          width: 40px;
          height: 40px;
          border: 3px solid #1e2749;
          border-top-color: #00ff88;
          border-radius: 50%;
          animation: spin 1s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .view-title {
          font-size: 24px;
          font-weight: bold;
          color: #00ff88;
          margin-bottom: 20px;
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .nats-status {
          margin-bottom: 15px;
        }

        .status-badge {
          display: inline-block;
          padding: 6px 12px;
          border-radius: 4px;
          font-size: 12px;
          font-weight: 600;
          text-transform: uppercase;
          background: #1a3a1a;
          color: #00ff88;
        }

        .status-badge.error {
          background: #3a1a1a;
          color: #ff4444;
        }

        .status-badge.offline {
          background: #3a3a1a;
          color: #ffaa44;
        }

        .status-badge.healthy {
          background: #1a3a1a;
          color: #00ff88;
        }

        .item-list {
          flex: 1;
          overflow-y: auto;
          margin-bottom: 10px;
        }

        .current-item {
          padding: 12px;
          margin-bottom: 8px;
          border-left: 3px solid transparent;
          background: #1a2540;
          border-radius: 4px;
          transition: all 0.2s;
        }

        .current-item.selected {
          border-left-color: #00ff88;
          background: #1e3540;
          box-shadow: 0 0 8px rgba(0, 255, 136, 0.2);
        }

        .item-header {
          display: flex;
          align-items: center;
          gap: 10px;
          margin-bottom: 4px;
        }

        .status-indicator {
          font-size: 18px;
          width: 24px;
          text-align: center;
        }

        .item-title {
          font-weight: 600;
          color: #e0e0e0;
          flex: 1;
        }

        .item-meta {
          font-size: 11px;
          color: #888;
          margin-left: 34px;
          display: flex;
          gap: 8px;
          align-items: center;
        }

        .heartbeat {
          padding: 2px 6px;
          background: #2a2a2a;
          border-radius: 2px;
        }

        .empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #666;
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .controls {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
          gap: 8px;
          margin-bottom: 10px;
          font-size: 12px;
        }

        .control-hint {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 8px;
          background: #1a2540;
          border-radius: 4px;
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
          padding: 8px 12px;
          border-radius: 4px;
          font-size: 12px;
          text-align: center;
          margin-bottom: 10px;
        }

        .counter {
          text-align: center;
          font-size: 11px;
          color: #666;
          padding-top: 10px;
          border-top: 1px solid #1e2749;
        }

        .detail-view {
          display: flex;
          flex-direction: column;
          height: 100%;
        }

        .detail-content {
          flex: 1;
          overflow-y: auto;
          margin-bottom: 15px;
        }

        .detail-section {
          margin-bottom: 20px;
          padding-bottom: 15px;
          border-bottom: 1px solid #1e2749;
        }

        .detail-section:last-child {
          border-bottom: none;
        }

        .section-label {
          font-size: 11px;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 6px;
          font-weight: 600;
        }

        .section-value {
          font-size: 14px;
          color: #e0e0e0;
        }

        .muted {
          color: #666;
        }

        .subject-list {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .subject-item {
          padding: 4px 8px;
          background: #1a2540;
          border-left: 2px solid #00ff88;
          font-family: monospace;
          font-size: 11px;
          color: #00ff88;
          border-radius: 2px;
        }
      </style>
    </div>
    """
  end

  defp derive_status(bot) do
    case bot["last_heartbeat"] do
      nil ->
        :offline

      hb when is_binary(hb) ->
        case DateTime.from_iso8601(hb) do
          {:ok, hb_time, _} ->
            seconds_ago = DateTime.diff(DateTime.utc_now(), hb_time, :second)

            cond do
              seconds_ago < 30 -> :healthy
              seconds_ago < 300 -> :idle
              true -> :offline
            end

          _ ->
            :offline
        end

      _ ->
        :offline
    end
  end

  defp status_emoji(:healthy), do: "✓"
  defp status_emoji(:idle), do: "⏸"
  defp status_emoji(:offline), do: "✗"
  defp status_emoji(_), do: "?"

  defp format_heartbeat(nil), do: "No heartbeat"

  defp format_heartbeat(hb) when is_binary(hb) do
    case DateTime.from_iso8601(hb) do
      {:ok, hb_time, _} ->
        seconds_ago = DateTime.diff(DateTime.utc_now(), hb_time, :second)

        cond do
          seconds_ago < 60 -> "now"
          seconds_ago < 3600 -> "#{div(seconds_ago, 60)}m ago"
          seconds_ago < 86400 -> "#{div(seconds_ago, 3600)}h ago"
          true -> "#{div(seconds_ago, 86400)}d ago"
        end

      _ ->
        "unknown"
    end
  end

  defp format_heartbeat(_), do: "unknown"
end
