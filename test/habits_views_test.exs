defmodule BotArmyDashboardLiveview.HabitsViewsTest do
  # The NATS bridge is off in test, so the mount-time read takes the "nothing
  # answered" path. That is the state these screens must never lie in.
  #
  # Not async: the read-path tests swap the app's broker transport for a stub, and
  # a concurrent test asserting "can't reach the bot" would be reading a stubbed
  # answer while it ran.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint

  # HEEx escapes the apostrophe in a text node, so this is what the screen
  # actually says: `Can&#39;t reach the bot`.
  @cannot_reach "Can&#39;t reach the bot"

  # What the bot answers a healthy read with, in its own wire shape.
  @hygiene_reply Jason.encode!(%{
                   "ok" => true,
                   "data" => %{
                     "hygiene" => %{
                       "items" => [
                         %{
                           "event" => "teeth_brushed",
                           "kind" => "compliance",
                           "recorded" => true,
                           "days_since" => 3.0
                         },
                         %{
                           "event" => "cage_cleaned",
                           "kind" => "wellness",
                           "recorded" => false,
                           "days_since" => nil
                         }
                       ]
                     }
                   }
                 })

  # Swaps the broker for a stub. Without this the suite can only ever test what a
  # screen does when nothing answers — which is how a `Broker` that asked nobody
  # passed for a broker that was down (see `BrokerTest`).
  defp install_broker(reply) do
    Application.put_env(:bot_army_dashboard_liveview, :broker_transport, BrokerStub)
    Application.put_env(:bot_army_dashboard_liveview, :broker_stub_reply, reply)
    Application.put_env(:bot_army_dashboard_liveview, :broker_stub_listener, self())

    on_exit(fn ->
      Application.delete_env(:bot_army_dashboard_liveview, :broker_transport)
      Application.delete_env(:bot_army_dashboard_liveview, :broker_stub_reply)
      Application.delete_env(:bot_army_dashboard_liveview, :broker_stub_listener)
    end)
  end

  defp habits_fixture do
    [
      %{
        "id" => "teeth_brushed",
        "name" => "Teeth Brushed",
        "category" => "compliance",
        "logged" => "last logged 3 days ago"
      },
      %{
        "id" => "cage_cleaned",
        "name" => "Cage Cleaned",
        "category" => "wellness",
        "logged" => "never logged"
      }
    ]
  end

  # `render_async` only waits for `start_async` work. A check-in reply arrives
  # from `Task.start_link` + send, which it does not track, so wait for the render
  # to actually show the answer instead of assuming the message already landed.
  defp await(view, text, tries \\ 50) do
    html = render(view)

    cond do
      html =~ text ->
        html

      tries == 0 ->
        html

      true ->
        Process.sleep(10)
        await(view, text, tries - 1)
    end
  end

  for {path, tag} <- [{"habits-phone", "HabitsPhone"}, {"habit-anchors", "HabitAnchors"}] do
    test "#{tag} draws the reading the bot answers with, not a message the test sends" do
      install_broker(@hygiene_reply)

      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))

      html = await(view, "Teeth Brushed")

      assert html =~ "Teeth Brushed"
      assert html =~ "last logged 3 days ago"
      assert html =~ "1 of 2"
      refute html =~ @cannot_reach

      # The carousel shows one item at a time, so the second reading is only on
      # screen once it is asked for.
      assert render_click(element(view, ~s(button[phx-click="gamepad-down"]))) =~ "not logged yet"
      assert render(view) =~ "2 of 2"

      assert_received {:broker_stub_request, :nats_connection, "wife_care.control_panel.hygiene",
                       _payload, _opts}
    end

    # The end of the write path, with an answer instead of a refusal: button →
    # broker → reply → card. The stub answers in the bot's own shape, so the only
    # thing missing here is the bot.
    test "#{tag} believes the bot's answer to a check-in, not the click" do
      install_broker(@hygiene_reply)

      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, "Check this one in") =~ "Check this one in"

      Application.put_env(:bot_army_dashboard_liveview, :broker_stub_reply, ~s({"ok":true}))

      assert render_click(element(view, ~s(button[phx-click="gamepad-a"]))) =~ "Checking in..."
      assert await(view, "checked in") =~ "checked in"

      assert_received {:broker_stub_request, :nats_connection,
                       "wife_care.control_panel.record_hygiene_event", payload, _opts}

      assert Jason.decode!(payload) == %{
               "event" => "teeth_brushed",
               "reason" =>
                 unquote(
                   if(path == "habits-phone", do: "phone check-in", else: "dashboard check-in")
                 )
             }
    end

    test "#{tag} says it cannot reach the bot instead of claiming there are no habits" do
      {:ok, view, html} = live(build_conn(), "/" <> unquote(path))

      assert html =~ "Loading habits..."

      html = await(view, @cannot_reach)

      assert html =~ @cannot_reach
      assert html =~ "Try again"
      refute html =~ "No habits configured yet"
      refute html =~ "No items to check in yet"
    end

    test "#{tag} leaves a trace for the operator when the read answers nothing" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
          await(view, @cannot_reach)
        end)

      assert log =~ "[#{unquote(tag)}] hygiene answered nothing"
    end

    test "#{tag} tries again on demand instead of sitting on the error" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, @cannot_reach) =~ @cannot_reach

      assert render_click(view, "retry") =~ "Loading habits..."
      assert await(view, @cannot_reach) =~ @cannot_reach
    end

    test "#{tag} draws the item the bot sends, with when it was last logged" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      # Let the mount-time read land first, so the only thing in flight after
      # this is the message the test sends — otherwise the two race.
      assert await(view, @cannot_reach) =~ @cannot_reach

      send(view.pid, {:habits_loaded, habits_fixture()})

      html = await(view, "Teeth Brushed")

      assert html =~ "last logged 3 days ago"
      assert html =~ "compliance"
      refute html =~ @cannot_reach
    end

    test "#{tag} tells an empty reading apart from an unreachable bot" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, @cannot_reach) =~ @cannot_reach

      send(view.pid, {:habits_loaded, []})
      html = await(view, "No items to check in yet")

      assert html =~ "No items to check in yet"
      assert html =~ "The bot answered with an empty list."
      refute html =~ @cannot_reach
    end

    # The card has always printed "Y  Check In · B  Skip" while binding neither
    # key, so on a laptop with a mouse the check-in could not be triggered at all.
    # The buttons are the fix; this pins them as real bindings, and pins that the
    # answer shown is the bot's, never an assumed success.
    test "#{tag} checks in from a real button, and reports the refusal" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, @cannot_reach) =~ @cannot_reach

      send(view.pid, {:habits_loaded, habits_fixture()})
      assert await(view, "Check this one in") =~ "Check this one in"

      assert render_click(element(view, ~s(button[phx-click="gamepad-a"]))) =~ "Checking in..."

      # The bot is not reachable in test, so a refusal is the only honest answer:
      # the write is attempted and its failure is reported as a failure.
      html = await(view, "Check-in failed")
      assert html =~ "Check-in failed"
      refute html =~ "checked in"
    end

    test "#{tag} binds the keys the card prints" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, @cannot_reach) =~ @cannot_reach

      send(view.pid, {:habits_loaded, habits_fixture()})
      assert await(view, "Check this one in") =~ "Check this one in"

      assert render_keydown(view, "window-key", %{"key" => "y"}) =~ "Checking in..."
      assert await(view, "Check-in failed") =~ "Check-in failed"

      # B clears the message, as the card says, and a key the card does not
      # print must do nothing at all.
      assert render_keydown(view, "window-key", %{"key" => "b"}) =~ "Check this one in"
      assert render_keydown(view, "window-key", %{"key" => "q"}) =~ "Check this one in"
    end

    test "#{tag} moves through the list with the arrow keys and the buttons" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert await(view, @cannot_reach) =~ @cannot_reach

      send(view.pid, {:habits_loaded, habits_fixture()})
      html = await(view, "Teeth Brushed")

      assert html =~ "Teeth Brushed"
      assert html =~ "1 of 2"

      assert render_click(element(view, ~s(button[phx-click="gamepad-down"]))) =~ "Cage Cleaned"
      assert render_click(element(view, ~s(button[phx-click="gamepad-up"]))) =~ "Teeth Brushed"
      assert render_keydown(view, "window-key", %{"key" => "ArrowDown"}) =~ "Cage Cleaned"
      assert render_keydown(view, "window-key", %{"key" => "ArrowUp"}) =~ "Teeth Brushed"
    end
  end
end
