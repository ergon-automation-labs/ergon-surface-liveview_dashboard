defmodule BotArmyDashboardLiveview.PartyPhoneTest do
  @moduledoc """
  The window screen: what it draws when a window is open, what it says when one is not,
  and what a reply is allowed to claim.

  The live bot has no session open, so the stub is the only thing that can put a window
  in front of this test at all — and the stub is shaped like the bot's own replies: the
  window question answers `{"ok" => true, "data" => %{…}}` (already unwrapped by
  `BotRead`) or `{"ok" => false, "error" => ":no_active_session"}`, the party question
  answers a session with `character_ids`, and a write answers the fact it stored.

  Three things this pins. A reply is confirmed by the window reading back with it, so
  the stub changes what it answers *during* the write — a confirmation that came from
  the write's own ok is exactly the claim that can be wrong. An empty draft is refused
  by this screen and sends **nothing**. And the shelf is drawn inside an open window and
  nowhere else: with no window there is nothing to offer it inside of.
  """

  # The reads swap the broker transport and set process-wide application env, so this
  # module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @window_subject "rpg.session.gather_context"
  @party_subject "rpg.session.state"
  @write_subject "rpg.scene.fact.add"
  @call_subject "wife_care.control_panel.state"
  @shelf_subject "wife_care.control_panel.hypnosis"

  @session "e291bf79-1111-4000-8000-000000000001"
  @char "c1a0f2e0-2222-4000-8000-000000000001"
  @scene "Neon-drenched alleyway under a flickering ad."
  @turn "the party came to a door"
  @turns_key {:party_phone_test, :turns}

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())
    :persistent_term.put(@turns_key, [@turn])

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end

      :persistent_term.erase(@turns_key)
    end)

    :ok
  end

  # The bot's window answer, in the shape `BotRead` hands the screen.
  defp window_answer do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "session_id" => @session,
        "session_status" => "active",
        "scene_description" => @scene,
        "scene_facts" => :persistent_term.get(@turns_key, []),
        "theme" => %{"setting" => "cyberpunk", "tone" => "gritty"},
        "character" => %{"name" => "the maid", "class" => "maid", "level" => 3}
      }
    })
  end

  defp party_answer do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{"id" => @session, "character_ids" => %{@char => "gtd_bot"}}
    })
  end

  # The shelf's two questions, answered so the card draws rather than refuses: no
  # phrases yet, and a call open — which is the fact that offers the shelf at all.
  defp shelf_answers do
    %{
      @call_subject =>
        Jason.encode!(%{
          "ok" => true,
          "data" => %{"louiza" => %{"demands" => %{"pending" => [%{"id" => "d1"}]}}}
        }),
      @shelf_subject =>
        Jason.encode!(%{
          "ok" => true,
          "data" => %{
            "hypnosis" => %{"phrases" => [], "put_away" => [], "rewritten" => [], "counts" => %{}}
          }
        })
    }
  end

  defp answers(overrides) do
    {:answers,
     fn subject -> Map.get(overrides, subject) || Map.get(shelf_answers(), subject, "{}") end}
  end

  # Every read this screen makes is recorded in this process's mailbox. Draining them
  # after mount is what makes a later `assert_receive` about the *re-read* rather than
  # about the mount read that happened to arrive late.
  defp drain_requests do
    receive do
      {:broker_stub_request, _conn, _subject, _payload, _opts} -> drain_requests()
    after
      100 -> :ok
    end
  end

  # The async read lands in the view's own mailbox; asking for state puts that call
  # behind whatever is already queued for it.
  defp settle(view) do
    :sys.get_state(view.pid)
    :ok
  end

  test "an open window draws the scene, the party, the turns, and the shelf inside it" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => window_answer(), @party_subject => party_answer()})
    )

    {:ok, view, html} = live(build_conn(), "/party-phone")
    settle(view)

    assert html =~ "The window"
    assert render(view) =~ @scene
    assert render(view) =~ "gtd_bot"
    assert render(view) =~ @turn
    assert render(view) =~ "Her shelf"
    assert render(view) =~ "offered inside this window"
    assert render(view) =~ "Review it"
  end

  test "the page asks whether a call is open, on the house screen's own subject" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => window_answer(), @party_subject => party_answer()})
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    settle(view)

    # The shelf's card is handed this answer, so the question has to be asked: a page
    # that draws the shelf without asking is claiming a gate it never checked.
    assert_receive {:broker_stub_request, _conn, @call_subject, _payload, _opts}
  end

  test "a call that is not open takes the shelf off the window page" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{
        @window_subject => window_answer(),
        @party_subject => party_answer(),
        @call_subject =>
          Jason.encode!(%{
            "ok" => true,
            "data" => %{"louiza" => %{"demands" => %{"pending" => []}}}
          })
      })
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    settle(view)
    html = render(view)

    # The window still stands — this is the shelf's condition, not the window's.
    assert html =~ @scene
    assert html =~ "gtd_bot"
    # And the page does not claim to offer a shelf the bot said is not offered.
    assert html =~ "Nothing is waiting right now"
    refute html =~ "offered inside this window"
    refute html =~ "Switch off"
    refute html =~ "Take away"
  end

  test "no window is open: the page says so and offers no shelf" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{
        @window_subject => Jason.encode!(%{"ok" => false, "error" => ":no_active_session"})
      })
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    settle(view)
    html = render(view)

    assert html =~ "No window is open"
    refute html =~ "Her shelf"
    # The sentence is wrapped in the template, so it is pinned by a fragment that a
    # line break cannot split.
    assert html =~ "to offer it inside of"
    # The party is never asked about a session that does not exist.
    refute_receive {:broker_stub_request, _, @party_subject, _, _}
    # And there is no box to type into without a window to say it into.
    refute html =~ "Review it"
  end

  test "the window question going unanswered is reported as a failure, not as no window" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => {:error, :timeout}})
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    settle(view)
    html = render(view)

    assert html =~ "the bot did not answer in time"
    refute html =~ "No window is open"
    # A failure is not a question still in flight.
    refute html =~ "Reading whether a window is open"
    refute html =~ "Her shelf"
  end

  test "the party question going unanswered leaves the window standing" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => window_answer(), @party_subject => {:error, :no_broker}})
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    settle(view)
    html = render(view)

    assert html =~ @scene
    assert html =~ "the bot is not reachable right now"
    refute html =~ "Reading who is in the window"
  end

  test "a reply is sent only after a confirmation, and confirmed by the re-read" do
    # The window carries the reply only once the write has happened, which is the point:
    # confirmation comes from the re-read and from nothing else.
    store_reply = fn _subject ->
      :persistent_term.put(@turns_key, [@turn, "hello"])
      Jason.encode!(%{"ok" => true, "data" => %{"id" => "fact-1"}})
    end

    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{
        # The window answer is read *at each read*, so the re-read sees the reply the
        # write stored. A value captured once could never confirm anything.
        @window_subject => {:answers, fn _subject -> window_answer() end},
        @party_subject => party_answer(),
        @write_subject => {:answers, store_reply}
      })
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    render_submit(view, "review", %{"text" => "a first pass"})
    drain_requests()

    # Typing sends nothing.
    render_change(view, "draft", %{"text" => "hello"})
    refute_receive {:broker_stub_request, _, @write_subject, _, _}

    # Reviewing sends nothing either — it draws the confirmation.
    html = render_submit(view, "review", %{"text" => "hello"})
    assert html =~ "Send this?"
    assert html =~ "hello"
    refute_receive {:broker_stub_request, _, @write_subject, _, _}

    # Sending writes once, as the operator, and re-reads the window.
    view |> element("button.reply-send") |> render_click()

    assert_receive {:broker_stub_request, _conn, @write_subject, payload, _opts}
    body = Jason.decode!(payload)
    assert body["source"] == "operator"
    assert body["category"] == "dialogue"
    assert body["session_id"] == @session
    assert body["content"] == "hello"
    refute Map.has_key?(body, "louiza")

    # The write landed and the window reads back with the reply in it, so now — and only
    # now — the screen calls it said.
    assert_receive {:broker_stub_request, _conn, @window_subject, _payload, _opts}
    settle(view)

    assert render(view) =~ "reads back with your reply in it"
  end

  test "a reply the window does not read back is not called said" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{
        @window_subject => window_answer(),
        @party_subject => party_answer(),
        # The write lands, but the window never carries it: the confirmation is the read,
        # and this read says no.
        @write_subject => Jason.encode!(%{"ok" => true, "data" => %{"id" => "fact-1"}})
      })
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    render_submit(view, "review", %{"text" => "hello"})
    view |> element("button.reply-send") |> render_click()

    settle(view)
    html = render(view)

    assert html =~ "not calling it said"
    refute html =~ "reads back with your reply in it"
  end

  test "an empty draft is refused here, and nothing is sent" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => window_answer(), @party_subject => party_answer()})
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    html = render_submit(view, "review", %{"text" => "   "})

    assert html =~ "empty reply is not a turn"
    refute html =~ "Send this?"
    refute_receive {:broker_stub_request, _, @write_subject, _, _}
  end

  test "backing out of the confirmation sends nothing" do
    Application.put_env(
      @app,
      :broker_stub_reply,
      answers(%{@window_subject => window_answer(), @party_subject => party_answer()})
    )

    {:ok, view, _html} = live(build_conn(), "/party-phone")
    render_submit(view, "review", %{"text" => "hello"})
    view |> element("button.reply-cancel") |> render_click()

    refute_receive {:broker_stub_request, _, @write_subject, _, _}
    refute render(view) =~ "Send this?"
  end
end
