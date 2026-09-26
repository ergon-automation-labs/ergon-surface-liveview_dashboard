defmodule BotArmyDashboardLiveview.PhoneNav do
  @moduledoc """
  Shared navigation component for phone handhelds.
  Provides quick access between all phone pages.

  The household HUD is first on purpose. It is the screen the maid lives on —
  what the house is doing, where she is in it, and what the house knows about her
  — and until this bar carried it the page had no way in except a URL someone had
  to remember. A screen nobody can navigate to is not a screen.

  Yearning and body follow it because they are hers to say, and they are their
  own screens rather than corners of the house's read: a report belongs on the
  screen that is for reporting. They sit next to the house, ahead of the timer,
  because the two things only she can report are closer to her than the work.

  The wardrobe follows the body for a plainer reason: what she is wearing is the
  one thing the house kept changing and the handheld had no way to touch at all.

  The shelf follows reflect for the same kind of reason, one step further in: the bot
  has held what she asked to hear since the day it was built, the panel could read it,
  and the screen she carries could neither see it nor take a phrase out of the air. It
  is labelled with the word someone would look for — the domain calls it a shelf, and
  nothing on this bar was called hypnosis.
  """

  use Phoenix.Component

  @handhelds [
    {"/household-hud", "🏠", "House"},
    {"/yearning-phone", "💗", "Yearning"},
    {"/body-phone", "🫀", "Body"},
    {"/wardrobe-phone", "👗", "Wardrobe"},
    {"/devotion-phone", "🕯️", "Devotion"},
    {"/timer-phone", "⏱️", "Timer"},
    {"/habits-phone", "✓", "Habits"},
    {"/habit-anchors", "🪥", "Anchors"},
    {"/quest-phone", "⚔️", "Quest"},
    {"/reflect-phone", "📝", "Reflect"},
    {"/hypnosis-phone", "🌀", "Hypnosis"},
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
