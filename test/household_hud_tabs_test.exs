defmodule BotArmyDashboardLiveview.HouseholdHUDTabsTest do
  # This module swaps the broker transport and sets process-wide application env,
  # so it is not async. `household_hud_live_test.exs` covers the same screen with
  # no broker at all, which is why it can only assert the strip and the exit; the
  # cards themselves only exist once something has answered.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  # The shape the live bot sends: `data` carries the state itself. One body
  # answers both reads on this screen, which is all the cards need — every title
  # below is drawn from the template, and the numbers are the bot's business.
  @answer Jason.encode!(%{
            "ok" => true,
            "data" => %{"intent" => %{"intensity_level" => 7}, "containment" => "held"},
            "schema_version" => "1.0"
          })

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_reply, @answer)
    # The reads happen in `start_async`'s task, so the stub has to be told where
    # to report: its default listener is whoever called it, which is that task.
    Application.put_env(@app, :broker_stub_listener, self())

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  # The two reads on mount are the only questions this screen ever asks.
  defp drain(0), do: :ok

  defp drain(n) do
    receive do
      {:broker_stub_request, _conn, _subject, _payload, _opts} -> drain(n - 1)
    after
      0 -> :ok
    end
  end

  defp answered do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    render_async(view)
    view
  end

  # One card belongs to one lens. If a lens drew a card from another lens the
  # screen would be the stack of boxes again, just behind a button.
  test "each lens draws its own cards and no others" do
    view = answered()

    assert render(view) =~ "Active state"
    assert render(view) =~ "Containment"
    # The card's title, not the bare word: the nav bar carries a "Yearning"
    # entry on every screen, so the bare word would pass on the bar alone.
    assert render(view) =~ "Yearning — the goddess-focus indicator"
    refute render(view) =~ "The chorus — ask the house"
    refute render(view) =~ "Calls she has sent"

    goddess = render_click(view, "tab", %{"tab" => "goddess"})
    assert goddess =~ "Calls she has sent"
    assert goddess =~ "Mood and wishes"
    assert goddess =~ "Exit — always available"
    refute goddess =~ "Containment"
    refute goddess =~ "The ladder"
    refute goddess =~ "The chorus — ask the house"

    house = render_click(view, "tab", %{"tab" => "house"})
    assert house =~ "The ladder — who answers to whom"
    assert house =~ "Pet layer — who may be warm"
    assert house =~ "Exit — always available"
    refute house =~ "Calls she has sent"
    refute house =~ "Yearning — the goddess-focus indicator"

    ask = render_click(view, "tab", %{"tab" => "ask"})
    assert ask =~ "The chorus — ask the house"
    assert ask =~ "Exit — always available"
    refute ask =~ "Pet layer"
    refute ask =~ "Active state"

    now = render_click(view, "tab", %{"tab" => "now"})
    assert now =~ "Active state"
    assert now =~ "Yearning — the goddess-focus indicator"
    refute now =~ "The chorus"
  end

  # The shelf is not an entry in the nav bar: what she asked to hear is offered while a
  # call is open, and the card that already draws that fact is where the offer belongs.
  # The offer is drawn by the same list the card draws, so the two cannot disagree about
  # whether a call is open.
  test "a call that is still open is where the shelf is offered from" do
    open =
      Jason.encode!(%{
        "ok" => true,
        "data" => %{
          "louiza" => %{
            "demands" => %{
              "today_count" => 1,
              "pending" => [%{"category" => "proximity", "label" => "come here now"}]
            }
          }
        }
      })

    Application.put_env(@app, :broker_stub_reply, open)
    view = answered()

    now = render(view)
    refute now =~ "the shelf is offered here"

    goddess = render_click(view, "tab", %{"tab" => "goddess"})
    assert goddess =~ "come here now"
    assert goddess =~ "A call is still open, so the shelf is offered here"
    assert goddess =~ ~s(href="/hypnosis-phone")
  end

  # And the other half of it: a house that reports nothing waiting offers no shelf, with
  # no link to a page that would refuse in its own words anyway.
  test "a house with nothing waiting offers no shelf" do
    empty =
      Jason.encode!(%{
        "ok" => true,
        "data" => %{"louiza" => %{"demands" => %{"today_count" => 0, "pending" => []}}}
      })

    Application.put_env(@app, :broker_stub_reply, empty)
    goddess = render_click(answered(), "tab", %{"tab" => "goddess"})

    assert goddess =~ "Calls she has sent"
    assert goddess =~ "nothing waiting"
    refute goddess =~ "the shelf is offered here"
    refute goddess =~ ~s(href="/hypnosis-phone")
  end

  # Switching lenses must not go back to the bot. The stub records every question
  # it is asked, so a switch that asked again would show up here as a second read.
  test "a switch is a lens, not a second read" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    render_async(view)

    drain(2)

    render_click(view, "tab", %{"tab" => "house"})
    render_click(view, "tab", %{"tab" => "ask"})

    refute_received {:broker_stub_request, _conn, _subject, _payload, _opts}
    # …and the strip is still there, so the two clicks did reach the screen.
    assert has_element?(view, "button[phx-value-tab=ask].tab.on")
  end
end
