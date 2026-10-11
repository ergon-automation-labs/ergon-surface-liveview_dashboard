defmodule BotArmyDashboardLiveview.HouseholdHUDExitTest do
  # The exit is the one control on this screen, and this file is where its two
  # rules are pinned: it names the host the page was reached on, and it asks the
  # broker for nothing. The transport is swapped for a stub here, so the module
  # also sets process-wide application env and is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  # The shape to search for, not the bare prefix: the page carries random base64
  # (a CSRF token, a session blob) and `k_` turns up in one of those by chance in
  # roughly one run in ten, so `refute html =~ "k_"` was a gate that failed for
  # reasons having nothing to do with leaking a credential.
  @ticket_pattern ~r/k_[0-9a-f]{32}/
  # Her panel. The authority's is 30013; this handheld is hers, so its exit opens
  # the instance whose verbs the exit names.
  @her_panel "http://www.example.com:30014"

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end

      System.delete_env("WIFE_CARE_CONTROL_PANEL_URL")
    end)

    :ok
  end

  # Settled, so the read task has been and gone: the mailbox afterwards holds
  # every request this screen ever made, which is what the third test reads.
  defp settled do
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    {view, render_async(view)}
  end

  test "the exit is a link to her panel, naming the host the page was reached on" do
    {_view, html} = settled()

    assert html =~ ~s(<a href="#{@her_panel}">→ open the control panel</a>)
    refute html =~ "localhost:30014"
    refute html =~ ":30013"
  end

  # The exit used to be a button that asked the bot to mint an entry ticket. The
  # bot can only mint `louiza`'s — its store refuses `slave` and `operator` by
  # design — so a tap meaning "her panel" opened the authority's, and an ungated
  # screen handed out an identity on the way. What is pinned here is the absence:
  # the two reads are the whole conversation, and no press on this page can add
  # to it.
  test "the exit asks the broker for nothing, on the way in or on a press" do
    {_view, html} = settled()

    assert_received {:broker_stub_request, :nats_connection, "wife_care.control_panel.state", "",
                     _opts}

    assert_received {:broker_stub_request, :nats_connection, "wife_care.chorus.categories", "",
                     _opts}

    # The press itself: a link is followed by the browser, so the LiveView is not
    # even asked. The old event name is refuted with the rest — a handler left
    # behind would be one more door, even with no button pointing at it.
    refute html =~ "phx-click=\"open_panel\""
    refute_received {:broker_stub_request, _, "wife_care.control_panel.entry_ticket", _, _}
  end

  test "nothing on the page is shaped like a ticket" do
    {_view, html} = settled()

    refute html =~ @ticket_pattern
    refute html =~ "/enter?t="
  end

  # The address is overridable because the host this page was reached on is not
  # always the host the panel answers on — a tunnel, a name that only resolves
  # inside the house.
  test "an explicit panel address wins over the host it was reached on" do
    System.put_env("WIFE_CARE_CONTROL_PANEL_URL", "http://panel.example:9999")
    {_view, html} = settled()

    assert html =~ ~s(<a href="http://panel.example:9999">→ open the control panel</a>)
    refute html =~ @her_panel
  end

  # A page with no host on it, which is what a bare socket gives: the fallback has
  # to be a name, never a crash and never an empty href.
  test "a request with no host still produces a usable link" do
    conn = build_conn() |> Map.put(:host, "")

    {:ok, view, _html} = live(conn, "/household-hud")
    html = render_async(view)

    assert html =~ ~s(<a href="http://localhost:30014">→ open the control panel</a>)
  end
end
