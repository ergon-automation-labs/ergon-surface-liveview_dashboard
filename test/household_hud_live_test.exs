defmodule BotArmyDashboardLiveview.HouseholdHUDLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  # The NATS bridge is off in test (config/test.exs), so every read here takes the
  # "nothing answered" path. That is the state the HUD must never lie in.
  @endpoint BotArmyDashboardLiveview.Endpoint

  # The screen before the bot has answered: it must say it is asking, and offer
  # nothing that implies a reading.
  test "is honest while it is still asking" do
    {:ok, _view, html} = live(build_conn(), "/household-hud")

    assert html =~ "Household HUD"
    assert html =~ "asking the house…"
  end

  test "says nothing answered, and offers a way to try again" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "No answer from the wife care bot yet."
    assert html =~ "ask again"
    refute html =~ "asking the house…"
  end

  # The screen says "no answer" whether the broker is dead, the bot stayed quiet,
  # or the reply was not an ok tuple. Only the log can tell those apart, so every
  # one of them has to write a line. (Measured in production: a live broker
  # answering {:error, :no_responders} was swallowed with no log at all.)
  test "a read that answers nothing leaves a trace for the operator" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, view, _html} = live(build_conn(), "/household-hud")
        render_async(view)
      end)

    assert log =~ "[HouseholdHUD]"
    assert log =~ "answered nothing"
  end

  # The screen used to print "r refresh" and "? this note" while binding neither.
  # A hint for a key that does nothing is the same kind of lie as a health check
  # that cannot fail, so the absence is pinned rather than trusted.
  test "advertises no key it cannot bind" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    refute html =~ "r:refresh"
    refute html =~ "<b>r</b>"
    refute html =~ "this note"
  end

  # The screen used to print the panel's address in an `href`, then it printed a
  # button that minted a ticket at the tap. It is a plain link again, and now it
  # is the *right* one: her panel, on the host this page was reached on, so that
  # a viewer is not sent to their own machine (see
  # `test/household_hud_exit_test.exs`, which pins both the address and the fact
  # that no press asks the broker for anything).
  test "the way to the panel is a link to her panel, and names the host it was reached on" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ ~s(<a href="http://www.example.com:30014">)
    assert html =~ "→ open the control panel"
    refute html =~ "localhost:30014"
    refute html =~ ":30013"
  end

  test "never fabricates the doc's example numbers" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    refute html =~ "65%"
    refute html =~ "MAID LEVEL 65"
  end

  test "the exit is on the screen even when nothing else is" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Exit — always available"
    assert html =~ "Stop everything"
  end

  test "carries the active state, its reason, and its energy" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Active state"
    assert html =~ "Neutral (normal operations)"
    assert html =~ "Energy: not set"
    assert html =~ "Nothing is shifting it today."
  end

  test "names the states it cannot derive yet instead of omitting them" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "Not derived yet"
    assert html =~ "Reward Pulse State"
    assert html =~ "diaper"

    # Restoration is derivable now that the energy feed exists, so it is no
    # longer announced as unreachable — it appears only when a reading climbs.
    refute html =~ "Restoration State —"
  end

  test "the energy line reports the band and how many readings there are" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "no reading yet"
    assert html =~ "Energy: not set"
    refute html =~ "reading from"
  end

  test "a recovery is announced in words, not only in colour" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    # With a silent panel there is nothing to recover from, and the screen says
    # nothing about recovery rather than showing a hopeful default.
    refute html =~ "Recovery is underway"
  end

  test "the background class follows the state and the pet layer" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "state-neutral"
    # Nothing answered, so the pet layer is not known to be on: the safe default
    # is the crisp, bloom-free rendering rather than an assumed warmth.
    assert html =~ ~s(class="hud state-neutral crisp")
    refute html =~ "state-neutral crisp bloom"
  end

  test "refreshing asks again and does not take the screen down" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    render_async(view)

    html = render_click(view, "refresh")

    assert html =~ "Household HUD"
    assert render_async(view) =~ "No answer from the wife care bot yet."
  end

  # All four lenses are drawn from one read, so switching must not ask again and
  # must not take anything away. With no broker the cards below the strip never
  # render (`household_hud_tabs_test.exs` covers them with an answer), so what is
  # asserted here is the part that must hold in every state: one lens marked, the
  # marker moving, and the exit still on the screen after every switch.
  test "the strip opens one lens at a time, and the exit survives every one" do
    {:ok, view, html} = live(build_conn(), "/household-hud")
    html = render_async(view)

    assert html =~ "hud-tabs"

    for key <- ~w(now goddess house ask) do
      assert has_element?(view, "button[phx-value-tab=#{key}]")
    end

    assert has_element?(view, "button[phx-value-tab=now].tab.on")
    refute has_element?(view, "button[phx-value-tab=goddess].tab.on")

    for key <- ~w(goddess house ask now) do
      render_click(view, "tab", %{"tab" => key})

      assert has_element?(view, "button[phx-value-tab=#{key}].tab.on")
      assert render(view) =~ "Exit — always available"
    end
  end

  # The event arrives from the browser, so it can carry anything. An unknown key
  # is ignored rather than guessed at or used as an assign.
  test "an unknown lens is left alone" do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    render_async(view)

    render_click(view, "tab", %{"tab" => "not-a-lens"})

    assert has_element?(view, "button[phx-value-tab=now].tab.on")
    assert render(view) =~ "Active state"
    refute render(view) =~ "not-a-lens"
  end
end
