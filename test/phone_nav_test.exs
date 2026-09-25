defmodule BotArmyDashboardLiveview.PhoneNavTest do
  @moduledoc """
  The two reporting screens are navigation entries, not corners of another page.

  Yearning and a body reading used to be two cards under the timer, which made
  the place a report is made the place a timer is run — so a tap on a point was
  one touch away from starting a countdown, and the only way to the ladders was a
  screen that had nothing to do with them. They are peer options in the nav bar
  now, the way fitness and gtd are, and this module pins that:

    * both routes are in the bar, and each screen offers itself as its own entry;
    * each screen carries **only its own** card and **only its own** write;
    * neither screen carries a `TouchCarousel` hook, so a tap on a point means
      one thing and cannot reach a second handler;
    * the timer screen no longer carries either ladder.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.PhoneNav

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @yearning_page "/yearning-phone"
  @body_page "/body-phone"
  @devotion_page "/devotion-phone"

  defp reporting_pages, do: [@yearning_page, @body_page, @devotion_page]

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())
    # An empty panel state still builds both cards: the house scale and the five
    # channels are the bot's defaults, and every channel reads "not reported".
    Application.put_env(@app, :broker_stub_reply, Jason.encode!(%{"ok" => true, "data" => %{}}))

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  test "the nav bar carries the reporting screens, as peers of the others" do
    handhelds = PhoneNav.all_handhelds()

    assert {@yearning_page, "💗", "Yearning"} in handhelds
    assert {@body_page, "🫀", "Body"} in handhelds
    assert {@devotion_page, "🕯️", "Devotion"} in handhelds

    # One option each, not one page with modes.
    assert length(handhelds) == 13
    routes = Enum.map(handhelds, &elem(&1, 0))
    assert Enum.uniq(routes) == routes
  end

  test "each reporting screen is its own page, and says so in the bar" do
    for route <- reporting_pages() do
      html = render(page(route, "nav-item"))

      assert html =~ ~s(href="#{route}")
      assert html =~ ~s(class="nav-item active")
    end
  end

  test "each screen draws its own card, and not the other one" do
    yearning = render(page(@yearning_page, "Yearning — the goddess-focus indicator"))
    assert yearning =~ "never measured"
    refute yearning =~ "The body — five channels"

    body = render(page(@body_page, "The body — five channels"))
    refute body =~ "the goddess-focus indicator"
  end

  test "each screen carries only its own write" do
    yearning = render(page(@yearning_page, ~s(phx-click="record_yearning")))
    refute yearning =~ "record_body_reading"

    body = render(page(@body_page, ~s(phx-click="record_body_reading")))
    refute body =~ "record_yearning"
  end

  # The placement rule, behaviourally: the hook is what pushes a bare `tap`, and
  # on a screen that had it a tap on a point would drive whatever listens for
  # that. It is not on these screens at all.
  test "a reporting screen has no touch carousel, so a tap means one thing" do
    for route <- reporting_pages() do
      refute render(page(route, "nav-item")) =~ ~s(phx-hook="TouchCarousel")
    end
  end

  test "the timer screen no longer carries either ladder" do
    html = render(page("/timer-phone", "nav-item"))

    refute html =~ "record_yearning"
    refute html =~ "record_body_reading"
    refute html =~ "tap a point to log it"
  end

  # A settled page: the read has landed by the time `text` is on screen.
  defp page(route, text) do
    {:ok, view, _html} = live(build_conn(), route)
    await(view, text)
    view
  end

  # The read is a hand-rolled task, not `start_async`, so wait for the text
  # rather than for a frame — the same bounded poll the read-path tests use.
  defp await(view, text), do: await(view, text, 50)

  defp await(_view, text, 0), do: flunk("the screen never showed #{inspect(text)}")

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end
end
