defmodule BotArmyDashboardLiveview.SyncStatus do
  @moduledoc """
  Sync status component for offline mode.
  Shows current sync queue state and allows manual retry.
  """

  use Phoenix.Component

  @doc """
  Render sync status indicator for phone handhelds.

  Usage in render:
    <.sync_status
      status={@sync_status}
      is_online={@is_online}
    />
  """
  def render(assigns) do
    ~H"""
    <div class="sync-status-bar">
      <%= if !@is_online do %>
        <div class="sync-offline">
          <span class="offline-icon">⚠️</span>
          <span class="offline-text">Offline</span>
          <%= if @status["queued"] > 0 do %>
            <span class="queue-count">
              <%= @status["queued"] %> queued
            </span>
          <% end %>
        </div>
      <% else %>
        <%= if @status["syncing"] > 0 do %>
          <div class="sync-syncing">
            <span class="spinner-small">⟳</span>
            <span class="sync-text">Syncing...</span>
            <span class="count"><%= @status["syncing"] %></span>
          </div>
        <% else %>
          <%= if @status["failed"] > 0 do %>
            <div class="sync-failed">
              <span class="error-icon">✕</span>
              <span class="error-text"><%= @status["failed"] %> failed to sync</span>
              <button
                class="retry-btn"
                phx-click="sync-queue-retry"
                type="button"
              >
                Retry
              </button>
            </div>
          <% else %>
            <%= if @status["total"] > 0 do %>
              <div class="sync-synced">
                <span class="success-icon">✓</span>
                <span class="success-text">
                  <%= @status["synced"] %> of <%= @status["total"] %> synced
                </span>
              </div>
            <% end %>
          <% end %>
        <% end %>
      <% end %>
    </div>

    <style>
      .sync-status-bar {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        z-index: 999;
        height: 32px;
        display: flex;
        align-items: center;
        padding: 0 12px;
        font-size: 12px;
        font-family: "Courier New", monospace;
        background: rgba(0, 0, 0, 0.8);
        border-bottom: 1px solid #333;
      }

      .sync-offline {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #f39c12;
        width: 100%;
      }

      .offline-icon {
        font-size: 14px;
      }

      .offline-text {
        font-weight: bold;
      }

      .queue-count {
        margin-left: auto;
        background: rgba(243, 156, 18, 0.2);
        padding: 2px 6px;
        border-radius: 3px;
      }

      .sync-syncing {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #3498db;
        width: 100%;
      }

      .spinner-small {
        display: inline-block;
        animation: spin 1s linear infinite;
        font-size: 14px;
      }

      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }

      .sync-text {
        font-weight: bold;
      }

      .count {
        margin-left: auto;
        background: rgba(52, 152, 219, 0.2);
        padding: 2px 6px;
        border-radius: 3px;
      }

      .sync-failed {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #e74c3c;
        width: 100%;
      }

      .error-icon {
        font-size: 14px;
      }

      .error-text {
        font-weight: bold;
        flex-grow: 1;
      }

      .retry-btn {
        background: #e74c3c;
        color: white;
        border: none;
        padding: 3px 8px;
        border-radius: 3px;
        font-size: 11px;
        cursor: pointer;
        font-weight: bold;
        transition: background 0.2s ease;
      }

      .retry-btn:active {
        background: #c0392b;
      }

      .sync-synced {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #27ae60;
        width: 100%;
      }

      .success-icon {
        font-size: 14px;
      }

      .success-text {
        font-weight: bold;
        margin-left: auto;
        font-size: 11px;
      }

      /* Adjust for safe area on notched phones */
      @supports (padding: max(0px)) {
        .sync-status-bar {
          padding-left: max(12px, env(safe-area-inset-left));
          padding-right: max(12px, env(safe-area-inset-right));
          padding-top: max(4px, env(safe-area-inset-top));
        }
      }
    </style>
    """
  end

  @doc """
  Inline helper for basic online/offline indicator.
  """
  def online_indicator(assigns) do
    ~H"""
    <div class={"online-badge #{if @is_online, do: "online", else: "offline"}"}>
      <%= if @is_online do %>
        <span>🌐</span>
      <% else %>
        <span>📡</span>
      <% end %>
    </div>

    <style>
      .online-badge {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 4px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: bold;
      }

      .online-badge.online {
        background: rgba(39, 174, 96, 0.2);
        color: #27ae60;
      }

      .online-badge.offline {
        background: rgba(243, 156, 18, 0.2);
        color: #f39c12;
        animation: pulse 2s infinite;
      }

      @keyframes pulse {
        0%, 100% {
          opacity: 1;
        }
        50% {
          opacity: 0.6;
        }
      }
    </style>
    """
  end
end
