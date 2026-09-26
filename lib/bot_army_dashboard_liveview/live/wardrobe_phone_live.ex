defmodule BotArmyDashboardLiveview.WardrobePhoneLive do
  @moduledoc """
  The wardrobe on the handheld: what is in it, what is on her, and which of the two
  ways it got there.

  The bot has held the cupboard for a while — the sets, the wearing that is open now,
  the catalogue — and the authenticated control surface can change it. The handheld,
  which is the screen she actually carries, could not put a set on at all, so the
  wardrobe only ever changed from a laptop. This screen is that missing half, reached
  from the nav bar the way the reporting screens are.

  It offers both verbs the bot accepts, and marks which one a wearing came from: **Wear
  this** sends `by: "subject"` (hers, `chosen: true`) and **Assign** sends
  `by: "louiza"` (the house putting a set on her, `chosen: false`). Everything a wear
  has to obey — a set the card is not drawing refused before anything is sent, the
  re-read that is today's, the bot's own words for a refusal, and the difference
  between a dead broker and the wardrobe saying no — lives in
  `BotArmyDashboardLiveview.Wardrobe`.
  """

  use Phoenix.LiveView

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.Wardrobe

  @impl true
  def mount(_params, _session, socket), do: {:ok, Wardrobe.start(socket)}

  @impl true
  def handle_info({:wardrobe, answer}, socket), do: {:noreply, Wardrobe.info(socket, answer)}

  @impl true
  def handle_event("wear_set", %{"id" => id}, socket),
    do: {:noreply, Wardrobe.click(socket, :wear, id)}

  def handle_event("assign_set", %{"id" => id}, socket),
    do: {:noreply, Wardrobe.click(socket, :assign, id)}

  # A tap with no id on it is a tap with no set to put on; it is refused like any other
  # tap this screen cannot route, rather than matching nothing and taking the screen
  # down.
  def handle_event("wear_set", _params, socket),
    do: {:noreply, Wardrobe.click(socket, :wear, nil)}

  def handle_event("assign_set", _params, socket),
    do: {:noreply, Wardrobe.click(socket, :assign, nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav wardrobe-phone">
      <div class="phone-card">
        <div class="view-title">👗 The wardrobe</div>
        <Wardrobe.card closet={@closet} act={@act} read_error={@read_error} />
      </div>
    </div>

    <PhoneNav.nav current_route="/wardrobe-phone" />
    """
  end
end
