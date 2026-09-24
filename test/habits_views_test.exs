defmodule BotArmyDashboardLiveview.HabitsViewsTest do
  # The NATS bridge is off in test, so the mount-time read takes the "nothing
  # answered" path. That is the state these screens must never lie in.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint BotArmyDashboardLiveview.Endpoint

  # HEEx escapes the apostrophe in a text node, so this is what the screen
  # actually says: `Can&#39;t reach the bot`.
  @cannot_reach "Can&#39;t reach the bot"

  for {path, tag} <- [{"habits-phone", "HabitsPhone"}, {"habit-anchors", "HabitAnchors"}] do
    test "#{tag} says it cannot reach the bot instead of claiming there are no habits" do
      {:ok, view, html} = live(build_conn(), "/" <> unquote(path))

      assert html =~ "Loading habits..."

      html = render_async(view)

      assert html =~ @cannot_reach
      assert html =~ "Try again"
      refute html =~ "No habits configured yet"
      refute html =~ "No items to check in yet"
    end

    test "#{tag} leaves a trace for the operator when the read answers nothing" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
          render_async(view)
        end)

      assert log =~ "[#{unquote(tag)}] hygiene answered nothing"
    end

    test "#{tag} tries again on demand instead of sitting on the error" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert render_async(view) =~ @cannot_reach

      assert render_click(view, "retry") =~ "Loading habits..."
      assert render_async(view) =~ @cannot_reach
    end

    test "#{tag} draws the item the bot sends, with when it was last logged" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      # Let the mount-time read land first, so the only thing in flight after
      # this is the message the test sends — otherwise the two race.
      assert render_async(view) =~ @cannot_reach

      send(
        view.pid,
        {:habits_loaded,
         [
           %{
             "id" => "teeth_brushed",
             "name" => "Teeth Brushed",
             "category" => "compliance",
             "logged" => "last logged 3 days ago"
           }
         ]}
      )

      html = render_async(view)

      assert html =~ "Teeth Brushed"
      assert html =~ "last logged 3 days ago"
      assert html =~ "compliance"
      refute html =~ @cannot_reach
    end

    test "#{tag} tells an empty reading apart from an unreachable bot" do
      {:ok, view, _html} = live(build_conn(), "/" <> unquote(path))
      assert render_async(view) =~ @cannot_reach

      send(view.pid, {:habits_loaded, []})
      html = render_async(view)

      assert html =~ "No items to check in yet"
      assert html =~ "The bot answered with an empty list."
      refute html =~ @cannot_reach
    end
  end
end
