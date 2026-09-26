defmodule BotArmyDashboardLiveview.HypnosisPhoneLive do
  @moduledoc """
  Her shelf on the handheld: the phrases she has asked to hear, and the two reductions
  this screen is allowed to make.

  The bot has held the shelf for a while — the phrases that are in the air, the ones she
  took away, the earlier wording of the ones she reworded — and the control surface can
  read it. Nothing drew it on the handheld, so the shelf had a floor and no door. This
  screen is that door.

  It is not on the nav bar, and that is the point rather than an oversight. A phrase in
  the air is a moment, not a place: the shelf is offered while there is one — the house
  has called her and she has not answered yet — so the way in is the call card on the
  house screen, where that fact already lives, and not a bar that is on every page at
  once. This screen asks the same question the house screen asks, on the same subject,
  so the two cannot disagree about whether a call is open: `HypnosisShelf.open_call/1`
  answers `:open`, `:none`, or `:unreported`, and only a plain `:none` takes the shelf
  off the page. An answer that never mentioned calls is not a report of nothing waiting,
  and hiding a screen on the strength of a question nobody answered is its own lie.

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

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.HypnosisShelf
  alias BotArmyDashboardLiveview.PhoneNav

  @call_timeout 3_000

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:hypnosis")

    BotRead.async(self(), :open_call, HypnosisShelf.call_subject(), %{}, timeout: @call_timeout)

    {:ok, socket |> HypnosisShelf.start() |> assign(open_call: nil)}
  end

  @impl true
  def handle_info({:hypnosis, answer}, socket), do: {:noreply, HypnosisShelf.info(socket, answer)}

  # The window the shelf is offered in. A failed read of it arrives through the read hooks
  # instead, so this clause only ever sees an answer — which is why the render has to ask
  # both whether the answer came and whether it said anything.
  @impl true
  def handle_info({:open_call, answer}, socket),
    do: {:noreply, assign(socket, open_call: HypnosisShelf.open_call(answer))}

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
    <%= if shelf_error(@read_error, @read_failed_tag) do %>
      <.read_error reason={@read_error} />
    <% end %>

    <div class="handheld-container with-nav hypnosis-phone">
      <div class="phone-card">
        <div class="view-title">🌀 Her shelf</div>
        <HypnosisShelf.card
          shelf={@shelf}
          act={@act}
          read_error={shelf_error(@read_error, @read_failed_tag)}
          said={@said}
          open_call={@open_call}
        />

        <%= if window_line(@open_call, @read_error, @read_failed_tag) != "" do %>
          <p style="color:#8b93b0; font-size:12px; margin:0; text-align:center;">
            <%= window_line(@open_call, @read_error, @read_failed_tag) %>
          </p>
        <% end %>
      </div>
    </div>

    <PhoneNav.nav current_route="/hypnosis-phone" />
    """
  end

  # Two reads on one screen means a failure belongs to one of them. The error card says
  # that nothing below it is a reading, and that is true of a shelf read that failed and
  # false of a call read that did: the shelf underneath came back, so an unanswered
  # question about a call may not report the shelf as unread.
  defp shelf_error(nil, _failed_tag), do: nil
  defp shelf_error(error, tag) when tag in [nil, :hypnosis], do: error
  defp shelf_error(_error, _failed_tag), do: nil

  # Why the shelf is on this page at all, said in the terms the answer came in. The
  # screen never claims a window it was not told about: an answer that did not mention
  # calls, and a question that never came back, are both named as exactly that.
  defp window_line(:open, _read_error, _failed_tag),
    do: "A call is open, and this shelf is offered while one is."

  defp window_line(:none, _read_error, _failed_tag), do: ""

  defp window_line(:unreported, _read_error, _failed_tag),
    do:
      "The bot did not say whether a call is open, so this screen is not claiming a window — it is showing the shelf it read."

  defp window_line(nil, read_error, :open_call) when not is_nil(read_error),
    do:
      "The question about an open call did not come back, so this screen is not claiming a window."

  defp window_line(nil, _read_error, _failed_tag), do: "Asking the house whether a call is open…"
end
