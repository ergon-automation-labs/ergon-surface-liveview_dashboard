defmodule BotArmyDashboardLiveview.BodyPhoneLive do
  @moduledoc """
  The body log, on a screen of its own.

  Five channels — arousal, breathing, hands, pulse, cage — each on the house's
  six-point scale. A reading here is a report ("what she said"), never a
  measurement, and the row the bot writes says so: the channel list and the
  scale come from the bot, so this screen cannot offer a channel the bot would
  refuse or draw a scale it does not use.

  A channel nobody has read stays empty rather than reading as nothing at all —
  "nothing recorded" and "at nothing" are different facts.

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
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav body-phone">
      <div class="phone-card">
        <div class="view-title">🫀 Body</div>
        <SelfReport.card which={:body} report={@report} tap={@tap} />
      </div>
    </div>

    <PhoneNav.nav current_route="/body-phone" />
    """
  end
end
