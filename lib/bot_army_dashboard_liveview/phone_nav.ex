defmodule BotArmyDashboardLiveview.PhoneNav do
  @moduledoc """
  Shared navigation component for phone handhelds.
  Provides quick access between all phone pages.

  The household HUD is first on purpose. It is the screen the slave lives on —
  what the house is doing, where she is in it, and what the house knows about her
  — and until this bar carried it the page had no way in except a URL someone had
  to remember. A screen nobody can navigate to is not a screen.

  ## What is not on this bar, and the two reasons

  **Yearning and Body used to be here** (with Devotion, Habits and Anchors). They were
  her own screens, and this bar was their way in. They are gone because the write on each
  one was the wrong half: the bot files `record_body_reading`, `record_goddess_proximity`,
  `record_hygiene_event` and the three cage writes under `:slave` **without being told**,
  so the identity is not on the wire at all and the page that sent it was the only thing
  here that knew whose hand was on the screen — on a surface anyone on the network can
  reach. Her panel makes all five reports behind her own link now, and the cards here
  still *read* what they wrote (the house screen draws both numbers), so nothing is lost
  by the bar dropping them. Their paths are retired into her **How I am** group.

  The wardrobe is **not** on this bar, and it is not on it for a harder reason than the
  shelf's. It sat here, and it did put sets on her from the screen she carries — but this
  surface is open, and a wear is a write whose whole meaning is *whose voice it was*: the
  bot records `chosen` from the name the surface claims, and a screen anyone on the
  network can reach was claiming both of them. The closet is hers, on her own panel,
  behind her own link, where the name it files under is the session it came from and not
  a constant in a component. Nothing is lost by the bar dropping it: the panel puts a set
  on, adds one, edits one and puts one away, and it now says the same thing this screen
  said about which of the two ways it got there.

  The shelf is not on this bar, and that is a decision rather than an omission. It did
  sit here, labelled the way someone would look for it; what she asked to hear is a
  moment rather than a place, though, and a bar that is on every page at once offers it
  in the middle of every other thing she is doing. The shelf is drawn inside the window
  — the party screen — which is where the moments are, and the way in is the call card
  on the house screen, drawn only while a call is open, so the entry follows the fact
  the house already reports rather than a static bar.

  The window is second because it is the only screen here she is *in* rather than
  reading about herself from: what gathered, who joined, and what has been said.
  """

  use Phoenix.Component

  @handhelds [
    {"/household-hud", "🏠", "House"},
    {"/party-phone", "🎭", "Window"},
    {"/timer-phone", "⏱️", "Timer"},
    {"/quest-phone", "⚔️", "Quest"},
    {"/reflect-phone", "📝", "Reflect"},
    {"/energy-mood-phone", "🌡️", "Energy"},
    {"/fitness-phone", "💪", "Fitness"},
    {"/gtd-phone", "📋", "GTD"},
    {"/system-health-phone", "⚙️", "Health"}
  ]

  def render(assigns) do
    ~H"""
    <nav class="phone-nav-bar">
      <%= for {route, emoji, label} <- @handhelds do %>
        <a
          href={route}
          class={["nav-item", if(route == @current_route, do: "active")]}
          title={label}
        >
          <div class="nav-emoji"><%= emoji %></div>
          <div><%= label %></div>
        </a>
      <% end %>
    </nav>
    """
  end

  @doc """
  Returns navigation HTML component for use in LiveView templates.
  Pass current_route to highlight active page.

  `handhelds` defaults to the full list, so a screen that just wants the bar
  at the bottom does not have to know it.

  Usage in render:
    <.phone_nav current_route={request_path} />
  """
  def nav(assigns) do
    assigns = Map.put_new(assigns, :handhelds, @handhelds)
    render(assigns)
  end

  @doc """
  Get all handhelds for programmatic access
  """
  def all_handhelds, do: @handhelds

  @doc """
  Get handhelds with emoji only (for compact views)
  """
  def get_emoji(route) do
    Enum.find_value(@handhelds, fn {r, e, _} -> r == route && e end)
  end
end
