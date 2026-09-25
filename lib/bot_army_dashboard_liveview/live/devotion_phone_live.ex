defmodule BotArmyDashboardLiveview.DevotionPhoneLive do
  @moduledoc """
  Writing a devotion back to the goddess, on a screen of its own.

  This is the missing half of the window. The bot has held the subject a reply
  comes back on for a while (`wife_care.control_panel.subject_reply`, kind
  `note`) and the desktop control panel has a note box for it, but the handheld
  — the screen she actually carries — had no way to say anything at all. So the
  record of her words was only ever written from a laptop, which in practice
  meant it was not written.

  It is a page rather than a corner of another screen for the same reason
  yearning and body are: a report belongs on the screen that is for reporting,
  reached from the nav bar the way fitness and gtd are.

  Everything a send has to obey — the empty note refused before it is sent, the
  re-read that confirms it, the bot's own words for a refusal, and "nothing was
  recorded" when the broker is dead — lives in
  `BotArmyDashboardLiveview.Devotion`.
  """

  use Phoenix.LiveView

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.Devotion
  alias BotArmyDashboardLiveview.PhoneNav

  @impl true
  def mount(_params, _session, socket), do: {:ok, Devotion.start(socket)}

  @impl true
  def handle_info({:devotion_notes, answer}, socket) do
    {:noreply, Devotion.info(socket, :devotion_notes, answer)}
  end

  def handle_info({:devotion_facts, answer}, socket) do
    {:noreply, Devotion.info(socket, :devotion_facts, answer)}
  end

  @impl true
  def handle_event("draft_devotion", %{"text" => raw}, socket) do
    {:noreply, Devotion.draft(socket, raw)}
  end

  def handle_event("write_devotion", %{"text" => raw}, socket) do
    {:noreply, Devotion.click(socket, raw)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav devotion-phone">
      <div class="phone-card">
        <div class="view-title">🕯️ Devotion</div>
        <Devotion.seeds facts={@facts} />
        <Devotion.composer draft={@draft} outcome={@outcome} />
        <Devotion.past notes={@notes} />
      </div>
    </div>

    <PhoneNav.nav current_route="/devotion-phone" />
    """
  end
end
