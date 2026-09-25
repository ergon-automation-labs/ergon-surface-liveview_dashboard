defmodule BotArmyDashboardLiveview.HouseholdHUDEntryTest do
  # The entry path swaps the broker transport for a stub and sets process-wide
  # application env, so this module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  # A ticket is 128 bits of lower-case hex behind `k_`, and this one is never
  # real: the stub hands it back, and nothing outside this file ever sees it.
  @ticket "k_" <> String.duplicate("ab12", 8)
  # The shape to search for, not the bare prefix. The page and the log both carry
  # random base64 — a CSRF token, a session blob — and `k_` turns up in one of
  # those by chance in roughly one run in ten, so `refute html =~ "k_"` was a
  # gate that failed for reasons having nothing to do with leaking a ticket.
  @ticket_pattern ~r/k_[0-9a-f]{32}/
  @plain_url "http://www.example.com:30013"

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  defp stub_reply(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  defp minted(ticket \\ @ticket) do
    Jason.encode!(%{"ok" => true, "data" => %{"ticket" => ticket}, "schema_version" => "1.0"})
  end

  # The reads on mount answer `{}` (the default), so the screen is in its honest
  # "nothing answered" state; the mint reply is set only once the tap is about to
  # happen, which is also the order the real thing happens in.
  defp hud do
    {:ok, view, html} = live(build_conn(), "/household-hud")
    {view, html}
  end

  test "a tap mints a ticket and follows it into the panel" do
    {view, html} = hud()

    # Nothing on the page before the tap: the ticket is minted at the moment of
    # the press and lives only in the redirect.
    refute html =~ @ticket
    refute html =~ @ticket_pattern

    stub_reply(minted())

    assert {:error, {:redirect, %{to: to}}} = render_click(view, "open_panel")
    assert to == "#{@plain_url}/enter?t=#{@ticket}"

    # One request, to the mint subject, with no identity named: the screen does
    # not know who is holding it, and the bot decides what a ticket may open.
    assert_received {:broker_stub_request, :nats_connection,
                     "wife_care.control_panel.entry_ticket", "{}", _opts}
  end

  # The fallback is the whole safety story of the fast path: the dashboard is
  # ungated, so a tap may only ever be a convenience. A bot that is stopped, a
  # build older than this subject, or a malformed answer must all leave the panel
  # reachable — on its own front door, where the code from another device works.
  test "a bot that does not answer costs a tap, not the way in" do
    {view, _html} = hud()
    stub_reply({:error, :no_broker})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:redirect, %{to: to}}} = render_click(view, "open_panel")
        assert to == @plain_url
      end)

    # And it is not silent: "the button just did nothing" is not a diagnosis.
    assert log =~ "no entry ticket"
    assert log =~ ":no_broker"
  end

  test "a refused mint is the same fallback" do
    {view, _html} = hud()
    stub_reply(Jason.encode!(%{"ok" => false, "error" => "refused", "code" => "unavailable"}))

    assert {:error, {:redirect, %{to: to}}} = render_click(view, "open_panel")
    assert to == @plain_url
  end

  test "an answer that is not a ticket is the same fallback" do
    for body <- [
          Jason.encode!(%{"ok" => true, "data" => %{"identity" => "louiza"}}),
          Jason.encode!(%{"ok" => true, "data" => %{"ticket" => 12}}),
          "{not json",
          ""
        ] do
      # A fresh screen per answer: the first redirect ends that LiveView, and a
      # fallback that only works once is not a fallback.
      stub_reply("{}")
      {view, _html} = hud()
      stub_reply(body)

      assert {:error, {:redirect, %{to: to}}} = render_click(view, "open_panel")
      assert to == @plain_url
    end
  end

  # The mint reply carries a live ticket, and this surface's log is world-readable
  # and read by log triage. A reason class is enough to tell a dead broker from a
  # refusal; the value is never needed.
  test "the ticket never reaches the log, not even on the way in" do
    {view, _html} = hud()
    stub_reply(minted())

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:redirect, %{to: _to}}} = render_click(view, "open_panel")
      end)

    refute log =~ @ticket
    refute log =~ @ticket_pattern
  end
end
