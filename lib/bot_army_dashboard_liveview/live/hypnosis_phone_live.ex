defmodule BotArmyDashboardLiveview.HypnosisPhoneLive do
  @moduledoc """
  Her shelf on the handheld: the phrases she has asked to hear, and the two reductions
  this screen is allowed to make.

  The bot has held the shelf for a while — the phrases that are in the air, the ones she
  took away, the earlier wording of the ones she reworded — and the control surface can
  read it. Nothing drew it on the handheld, so the shelf had a floor and no door. This
  screen is that door, reached from the nav bar the way the reporting screens are.

  It offers only the two verbs the shelf's own rule allows anyone to make — **Switch
  off** ("anyone may take a phrase out of the air") and **Take away** ("only she may put
  one in") — and writes them as `actor: "operator"`, because this dashboard is open and
  proves nothing about who is holding the phone. Everything a tap has to obey — a phrase
  the card is not drawing refused before anything is sent, the re-read that is the whole
  truth of the sentence after it, the bot's own words for a refusal, and the difference
  between a dead broker and the shelf saying no — lives in
  `BotArmyDashboardLiveview.HypnosisShelf`.

  It is also a witness to the house saying a phrase of its own accord: the bridge hands it
  `events.wife_care.hypnosis.said` on `dashboard:hypnosis`, the saying is named off the
  shelf this screen has read — the event has no words in it — and the shelf is re-read so
  the counts under the card are the read that followed the saying.
  """

  use Phoenix.LiveView

  alias Phoenix.PubSub

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.HypnosisShelf
  alias BotArmyDashboardLiveview.PhoneNav

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:hypnosis")

    {:ok, HypnosisShelf.start(socket)}
  end

  @impl true
  def handle_info({:hypnosis, answer}, socket), do: {:noreply, HypnosisShelf.info(socket, answer)}

  # The bridge's broadcast for a saying. The event says which phrase and when, and never
  # what was said, so the sentence is named off the shelf this screen has already read.
  @impl true
  def handle_info({:hypnosis_event, _subject, event}, socket),
    do: {:noreply, HypnosisShelf.said(socket, event)}

  @impl true
  def handle_event("act", %{"verb" => "switch_off", "id" => id}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :switch_off, id)}

  def handle_event("act", %{"verb" => "take_away", "id" => id}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :take_away, id)}

  # A tap with no phrase on it is a tap this screen cannot route; it is refused the same
  # way rather than matching nothing and taking the screen down.
  def handle_event("act", %{"verb" => "switch_off"}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :switch_off, nil)}

  def handle_event("act", %{"verb" => "take_away"}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :take_away, nil)}

  # Anything else is a verb this screen does not do — including one of the three that
  # are hers, which this screen never sends.
  def handle_event("act", _params, socket),
    do: {:noreply, HypnosisShelf.click(socket, :unknown, nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav hypnosis-phone">
      <div class="phone-card">
        <div class="view-title">🌀 Her shelf</div>
        <HypnosisShelf.card shelf={@shelf} act={@act} read_error={@read_error} said={@said} />
      </div>
    </div>

    <PhoneNav.nav current_route="/hypnosis-phone" />
    """
  end
end
