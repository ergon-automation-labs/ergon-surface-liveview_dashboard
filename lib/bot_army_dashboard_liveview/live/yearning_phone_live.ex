defmodule BotArmyDashboardLiveview.YearningPhoneLive do
  @moduledoc """
  The yearning ladder, on a screen of its own.

  Yearning is the goddess-focus indicator, and it is the one number that is
  *only* hers to say: the house reads it (§19) and never measures it. It is a
  page rather than a corner of another screen because a report belongs on the
  screen that is for reporting — reached from the nav bar the way fitness and
  gtd are, so it does not need a URL from memory.

  Everything a tap has to obey — the six points, the re-read that confirms it,
  the bot's own words for a refusal, and "nothing was recorded" when the broker
  is dead — lives in `BotArmyDashboardLiveview.SelfReport`.
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
  def handle_event("record_yearning", %{"level" => raw}, socket) do
    {:noreply, SelfReport.click(socket, :yearning, raw)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @read_error do %><.read_error reason={@read_error} /><% end %>

    <div class="handheld-container with-nav yearning-phone">
      <div class="phone-card">
        <div class="view-title">💗 Yearning</div>
        <SelfReport.card which={:yearning} report={@report} tap={@tap} />
      </div>
    </div>

    <PhoneNav.nav current_route="/yearning-phone" />
    """
  end
end
