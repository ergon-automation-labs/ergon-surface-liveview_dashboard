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

  **GTD used to be here**, and it is the smaller half of that defect rather than the same
  one: its writes did carry an identity — the screen sent `slave` through the bridge — but
  the list was still drawn on an open surface, and a task list is an answer to *what should
  I do next*. Her panel's **Tasks** group draws the same box with the same verbs (§45), so
  the bar keeps the copy she is holding. Nothing is lost by dropping this one either: the
  panel reads the same task box and offers the same done and not-now. Its path is retired
  into the Tasks group, and its handheld twin went with it.

  **Reflect used to be here too**, and it is the *worst* of these rather than the smaller
  half of one: the screen wrote her own words into her journal, and the write carried **no
  identity at all**. A reflection knows text, a prompt and a `dedupe_key` — the store has no
  notion of a person — so the page that sent it was the whole answer to *whose words are
  these*, and this surface is open. Her panel's **Reflect** group holds that write under her
  own login, with the same question, the same box and the same journal (§47). Both reflect
  paths are retired into that group. Nothing is lost by dropping it from the bar: the panel
  reads the same two subjects, and the journal is drawn where the hand that wrote it is
  known.

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

  The timer and the quest were on this bar and are not, and they are the last two to
  leave. `/timer-phone` is the energy screen's defect a second time — it filed the session
  with a publish nobody had to read, and kept the running session's id in the page, so a
  reload lost both — and her panel's Timers group holds the session **in the bridge**
  (§51). `/quest-phone` is the GTD screen's defect: it drew a progress bar over the box her
  tasks live in, and her panel's Quest group draws the open steps as a count (§50). A bar
  that still offered either would be a promise that the screen is here.

  The fitness pair was the last thing on this bar to go, and it left for a reason none of the
  others had: it was not the write that was wrong but the **words**. The phone screen carried
  its own list of what a workout is — a sixth copy of a vocabulary the bot had already
  retired five times — so it could offer an activity the bot folds onto `"other"` and then
  draw the row back under a name it invented. Her panel's **Fitness** group asks
  `fitness.workout.options` and draws the bot's own activities, intensities and words (§46),
  so nothing on this bar has to know the vocabulary to write a workout.
  """

  use Phoenix.Component

  @handhelds [
    {"/household-hud", "🏠", "House"},
    {"/party-phone", "🎭", "Window"},
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
