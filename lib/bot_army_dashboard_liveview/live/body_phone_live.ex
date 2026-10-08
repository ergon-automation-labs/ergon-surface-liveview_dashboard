defmodule BotArmyDashboardLiveview.BodyPhoneLive do
  @moduledoc """
  The body log, on a screen of its own, with the cage escape log beside it.

  Each channel the bot keeps — listed by the bot, never here — on the house's
  six-point scale. A reading here is a report ("what she said"), never a
  measurement, and the row the bot writes says so: the channel list and the
  scale come from the bot, so this screen cannot offer a channel the bot would
  refuse or draw a scale it does not use.

  A channel nobody has read stays empty rather than reading as nothing at all —
  "nothing recorded" and "at nothing" are different facts.

  The escape card is not one of those channels. An escape is an *event* rather
  than a level: the cage channel answers "how much strain is it taking", while an
  escape is a thing that happened at a time, so it is counted rather than scored.
  It shares this screen because it is a fact about the same body, not because it
  is the same kind of fact.

  Everything a tap has to obey lives in
  `BotArmyDashboardLiveview.SelfReport`.
  """

  use Phoenix.LiveView

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.SelfReport

  @impl true
  def mount(_params, _session, socket), do: {:ok, SelfReport.start(socket)}

  @impl true
  def handle_info({:self_report, answer}, socket), do: {:noreply, SelfReport.info(socket, answer)}

  @impl true
  def handle_event("record_body_reading", %{"kind" => kind, "level" => raw}, socket) do
    {:noreply, SelfReport.click(socket, {:body, kind}, raw)}
  end

  @impl true
  def handle_event("record_cage_escape", _params, socket) do
    {:noreply, SelfReport.escape(socket, :record, %{})}
  end

  @impl true
  def handle_event("undo_cage_escape", _params, socket) do
    {:noreply, SelfReport.escape(socket, :undo, %{})}
  end

  @impl true
  def handle_event("flip_cage_escape", params, socket) do
    {:noreply, SelfReport.escape(socket, :flip, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav body-phone">
      <div class="phone-card">
        <div class="view-title">🫀 Body</div>
        <SelfReport.card which={:body} report={@report} tap={@tap} />
        <SelfReport.card which={:cage_escapes} report={@report} tap={@tap} />
      </div>
    </div>

    <PhoneNav.nav current_route="/body-phone" />
    """
  end
end
