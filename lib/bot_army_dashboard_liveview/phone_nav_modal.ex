defmodule BotArmyDashboardLiveview.PhoneNavModal do
  @moduledoc """
  Context menu modal for long-press page switching.
  Triggered by long-press on any phone handheld.
  """

  use Phoenix.Component

  @handhelds [
    {"/household-hud", "🏠", "House", "What is waiting, and what she asked for"},
    {"/party-phone", "🎭", "Window", "The window she is in with the party"},
    {"/yearning-phone", "💗", "Yearning", "Her own number, never measured"},
    {"/body-phone", "🫀", "Body", "Five channels, her own points"},
    {"/wardrobe-phone", "👗", "Wardrobe", "What is in it, and what is on her"},
    {"/devotion-phone", "🕯️", "Devotion", "Words back to the goddess"},
    {"/timer-phone", "⏱️", "Timer", "Focus sessions with task linking"},
    {"/habits-phone", "✓", "Habits", "Daily shame-free check-ins"},
    {"/quest-phone", "⚔️", "Quest", "Story progression tracker"},
    {"/reflect-phone", "📝", "Reflect", "Post-work narrative capture"},
    {"/hypnosis-phone", "🌀", "Hypnosis",
     "What she asked to hear, and two ways to take it out of the air"},
    {"/energy-mood-phone", "🌡️", "Energy", "Energy & mood context"},
    {"/fitness-phone", "💪", "Fitness", "Workout logging"},
    {"/gtd-phone", "📋", "GTD", "Projects & tasks"},
    {"/system-health-phone", "⚙️", "Health", "Bot & NATS status"}
  ]

  def render(assigns) do
    ~H"""
    <%= if @show_menu do %>
      <div class="phone-nav-modal-overlay" phx-click="close-nav-menu">
        <div class="phone-nav-modal" phx-click="stop-propagation">
          <div class="modal-header">
            <div class="modal-title">🚀 Quick Nav</div>
            <button class="modal-close" phx-click="close-nav-menu">✕</button>
          </div>

          <div class="modal-search">
            <input
              type="text"
              class="search-input"
              placeholder="Search handhelds..."
              phx-change="filter-nav"
              phx-value-query={@search_query}
              autocomplete="off"
            />
          </div>

          <div class="modal-grid">
            <%= for {route, emoji, label, desc} <- @filtered_handhelds do %>
              <a href={route} class={["modal-item", if(route == @current_route, do: "active")]}>
                <div class="item-emoji"><%= emoji %></div>
                <div class="item-name"><%= label %></div>
                <div class="item-desc"><%= desc %></div>
              </a>
            <% end %>
          </div>

          <div class="modal-footer">
            <div class="footer-hint">Tap to navigate • Long-press to open menu</div>
          </div>
        </div>
      </div>
    <% end %>

    <style>
      .phone-nav-modal-overlay {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.6);
        z-index: 2000;
        backdrop-filter: blur(4px);
        display: flex;
        align-items: center;
        justify-content: center;
        animation: fadeIn 0.2s ease;
      }

      @keyframes fadeIn {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }

      .phone-nav-modal {
        background: rgba(15, 15, 30, 0.95);
        border: 2px solid #6b7fd7;
        border-radius: 16px;
        padding: 20px;
        width: 90%;
        max-width: 500px;
        max-height: 80vh;
        display: flex;
        flex-direction: column;
        gap: 15px;
        box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
        animation: slideUp 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
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

      .modal-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-bottom: 1px solid rgba(107, 127, 215, 0.3);
        padding-bottom: 12px;
      }

      .modal-title {
        font-size: 20px;
        font-weight: bold;
        color: #6b7fd7;
      }

      .modal-close {
        background: none;
        border: none;
        color: #707070;
        font-size: 24px;
        cursor: pointer;
        padding: 0;
        min-width: 40px;
        min-height: 40px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 4px;
        transition: all 0.2s ease;
      }

      .modal-close:active {
        background: rgba(107, 127, 215, 0.2);
        color: #ecf0f1;
      }

      .modal-search {
        display: flex;
      }

      .search-input {
        width: 100%;
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid rgba(107, 127, 215, 0.3);
        border-radius: 8px;
        padding: 10px 12px;
        color: #ecf0f1;
        font-size: 14px;
        font-family: "Courier New", monospace;
      }

      .search-input::placeholder {
        color: #606060;
      }

      .search-input:focus {
        outline: none;
        border-color: #6b7fd7;
        background: rgba(107, 127, 215, 0.1);
      }

      .modal-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 10px;
        overflow-y: auto;
        flex-grow: 1;
        padding-right: 8px;
      }

      .modal-grid::-webkit-scrollbar {
        width: 6px;
      }

      .modal-grid::-webkit-scrollbar-track {
        background: transparent;
      }

      .modal-grid::-webkit-scrollbar-thumb {
        background: rgba(107, 127, 215, 0.3);
        border-radius: 3px;
      }

      .modal-grid::-webkit-scrollbar-thumb:hover {
        background: rgba(107, 127, 215, 0.5);
      }

      .modal-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 15px;
        border-radius: 10px;
        background: rgba(107, 127, 215, 0.1);
        border: 1px solid rgba(107, 127, 215, 0.2);
        text-decoration: none;
        color: #ecf0f1;
        transition: all 0.2s ease;
        cursor: pointer;
        min-height: 100px;
      }

      .modal-item:active {
        background: rgba(107, 127, 215, 0.3);
        border-color: #6b7fd7;
        transform: scale(0.95);
      }

      .modal-item.active {
        background: rgba(107, 127, 215, 0.2);
        border: 2px solid #6b7fd7;
      }

      .item-emoji {
        font-size: 32px;
        margin-bottom: 8px;
      }

      .item-name {
        font-size: 14px;
        font-weight: bold;
        margin-bottom: 4px;
      }

      .item-desc {
        font-size: 11px;
        color: #b0b0b0;
        text-align: center;
        line-height: 1.3;
      }

      .modal-footer {
        border-top: 1px solid rgba(107, 127, 215, 0.3);
        padding-top: 12px;
        text-align: center;
      }

      .footer-hint {
        font-size: 11px;
        color: #707070;
      }

      @media (max-width: 768px) {
        .phone-nav-modal {
          width: 95%;
          max-height: 90vh;
          padding: 15px;
        }

        .modal-grid {
          grid-template-columns: 1fr;
        }

        .modal-item {
          min-height: 80px;
        }
      }
    </style>
    """
  end

  @doc """
  Render the context menu modal.
  Use in any phone handheld:

    <PhoneNavModal.modal show_menu={@show_nav_menu} current_route={@current_route} filtered_handhelds={@filtered_handhelds} search_query={@search_query} />
  """
  def modal(assigns) do
    render(assigns)
  end

  @doc """
  Get all handhelds for filtering
  """
  def all_handhelds, do: @handhelds

  @doc """
  Filter handhelds by search query
  """
  def filter_handhelds(query) when is_binary(query) do
    query_lower = String.downcase(query)

    Enum.filter(@handhelds, fn {_route, _emoji, label, desc} ->
      label_match = String.contains?(String.downcase(label), query_lower)
      desc_match = String.contains?(String.downcase(desc), query_lower)
      label_match or desc_match
    end)
  end

  def filter_handhelds(_), do: @handhelds
end
