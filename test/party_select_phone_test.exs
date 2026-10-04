defmodule BotArmyDashboardLiveview.PartySelectPhoneTest do
  @moduledoc """
  Building the party from her phone: who is with her, who could be, and who writes the turns.

  `/party-phone` draws the window, and with no party there is no window — so the screen that
  needed to make a party was the screen that said "no window is open. Nothing has gathered,
  so there is nothing to say into yet." and offered nothing to do about it. This is the
  other half: the three routes that build the party (`rpg.party.add`, `rpg.party.remove`,
  `rpg.party.set_narrator`) have been on the bot all along and nothing in the dashboard could
  reach them.

  What this file pins, and why each one is a claim that could be wrong:

    * the party question names a user and the roster question does not — the party routes
      refuse a call with no `user_id`, and a user on the roster would filter the tenant's
      characters down to the ones that user owns, which is none of them
    * an empty party draws the bot's own sentence for how to fill it, not a second one
      invented here for the same fact
    * a companion already with her is not offered again, and one the bot sent no character id
      for is kept and said to be un-actable rather than dropped
    * a failed read is a refusal, on each card separately: the party unanswered may not report
      the characters as unread, and the other way round
    * the killer: a recruit is confirmed by the **party reading back** with them in it, never
      by the write's own `ok` — so the stub flips a flag during the write and the screen has
      to notice which reading it is holding
    * a write the bot acknowledges that does not change the party is not called done
    * a refusal is drawn as a refusal
    * naming a narrator is drawn from the re-read with the role on them, and clearing it sends
      an explicit `null` — to the bot, an absent `character_id` is a different request
    * an empty bot id is refused here and sends **nothing**

  `async: false` because the stub and the reads are installed through application env.

  Nothing here counts reads: `live/2` does a dead render and a connected render, so `mount/3`
  runs twice per page load and every mount read fires twice. A test that counted them would
  be measuring the harness. Where a test needs to know which reading it is looking at, it
  flips a flag instead.
  """

  use ExUnit.Case, async: false

  @moduletag :core

  @endpoint BotArmyDashboardLiveview.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.PartySelect

  @app :bot_army_dashboard_liveview

  @get_subject "rpg.party.get"
  @roster_subject "rpg.character.list"
  @add_subject "rpg.party.add"
  @remove_subject "rpg.party.remove"
  @narrator_subject "rpg.party.set_narrator"
  @join_subject "rpg.session.join"
  @context_subject "rpg.session.gather_context"
  @state_subject "rpg.session.state"

  @session "20572659-53c2-417e-b67b-fc315d7ee38b"

  @tenant "00000000-0000-0000-0000-000000000001"
  @char_gtd "91bae810-82b6-4380-acf4-4f44a5284539"
  @char_llm "bad12683-eec8-4361-9a05-ba018469a9cd"
  @char_syn "e19ff81f-2004-48fa-bd70-40ae1194cb24"

  # The switch the recruit test flips: a write is the only thing that may set it, and the
  # party the stub answers with afterwards is what the screen has to read the write back from.
  @recruited_key {:party_select_phone_test, :recruited}

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())
    :persistent_term.put(@recruited_key, false)

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end

      :persistent_term.erase(@recruited_key)
    end)

    :ok
  end

  # ── the stub's answers, in the shapes the bot sends ───────────────────────────

  defp ok(data), do: Jason.encode!(%{"ok" => true, "data" => data})
  defp refusal(reason), do: Jason.encode!(%{"ok" => false, "error" => reason})

  defp blank_party do
    %{
      "name" => "The Adventuring Party",
      "members" => [],
      "created_at" => "2026-10-04T02:13:31.258524Z",
      "message" => "No party yet. Use rpg.party.add to recruit a bot companion."
    }
  end

  defp party(members),
    do: %{
      "name" => "The Adventuring Party",
      "members" => members,
      "created_at" => "2026-10-04T02:13:31.258524Z"
    }

  defp member(overrides \\ %{}) do
    Map.merge(
      %{
        "character_id" => @char_gtd,
        "bot_id" => "gtd_bot",
        "name" => "The Lorekeeper",
        "class" => "Scheduler",
        "level" => 3,
        "role" => "companion",
        "joined_at" => "2026-10-04T02:13:31.258524Z"
      },
      overrides
    )
  end

  defp character(overrides) do
    Map.merge(
      %{
        "id" => @char_gtd,
        "name" => "The Lorekeeper",
        "class" => "Scheduler",
        "level" => 3,
        "bot_id" => "gtd_bot"
      },
      overrides
    )
  end

  # The three characters the live bot has, all owned by nobody — which is why the roster
  # names no user and still finds them.
  defp roster_rows do
    [
      character(%{}),
      character(%{
        "id" => @char_llm,
        "bot_id" => "llm_bot",
        "name" => "The Bard",
        "class" => "Bard"
      }),
      character(%{
        "id" => @char_syn,
        "bot_id" => "synapse",
        "name" => "The Innkeeper",
        "class" => "Oracle"
      })
    ]
  end

  defp install(fun), do: Application.put_env(@app, :broker_stub_reply, {:answers, fun})

  # A window that named itself, and the characters the window has joined. The window question
  # is `rpg.session.gather_context` and its party is `rpg.session.state`.
  defp window_body(session_id \\ @session) do
    %{
      "session_id" => session_id,
      "session_status" => "active",
      "scene_description" => "The tavern, after dark.",
      "scene_facts" => ["a line she said"],
      "character_ids" => %{},
      "party" => %{"members" => []},
      "narration" => nil
    }
  end

  defp window_with(session_id, ids), do: Map.put(window_body(session_id), "character_ids", ids)

  # A stub that answers each subject once, with a body already encoded.
  defp answering(overrides), do: install(fn subject -> Map.get(overrides, subject, "{}") end)

  defp a_party_and_a_roster(party_body, roster_body),
    do: answering(%{@get_subject => party_body, @roster_subject => roster_body})

  # ── harness ───────────────────────────────────────────────────────────────────

  defp drain_requests do
    receive do
      {:broker_stub_request, _conn, _subject, _payload, _opts} -> drain_requests()
    after
      100 -> :ok
    end
  end

  # The async reads land in the view's own mailbox; asking for state puts this call behind
  # whatever is already queued for it.
  defp settle(view) do
    :sys.get_state(view.pid)
    :ok
  end

  defp await(view, text, tries \\ 80) do
    html = render(view)

    cond do
      String.contains?(html, text) ->
        html

      tries == 0 ->
        flunk(
          "waited for #{inspect(text)} and did not find it.\n" <> String.slice(html, 0, 3_000)
        )

      true ->
        Process.sleep(10)
        await(view, text, tries - 1)
    end
  end

  defp open(party_body, roster_body) do
    a_party_and_a_roster(party_body, roster_body)
    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()
    view
  end

  # ── the identity the party routes need ────────────────────────────────────────

  test "the party question names a user, because the party routes refuse a call without one" do
    a_party_and_a_roster(ok(blank_party()), ok(roster_rows()))
    {:ok, _view, _html} = live(build_conn(), "/party-select-phone")

    assert_receive {:broker_stub_request, _conn, @get_subject, payload, _opts}, 500
    body = Jason.decode!(payload)

    assert body["tenant_id"] == @tenant
    assert body["user_id"] == "abby"
    assert map_size(body) == 2
  end

  test "the roster question names no user, so the tenant's characters are who could join" do
    a_party_and_a_roster(ok(blank_party()), ok(roster_rows()))
    {:ok, _view, _html} = live(build_conn(), "/party-select-phone")

    assert_receive {:broker_stub_request, _conn, @roster_subject, payload, _opts}, 500
    body = Jason.decode!(payload)

    assert body == %{"tenant_id" => @tenant}
    refute Map.has_key?(body, "user_id")
  end

  # ── reading the party ──────────────────────────────────────────────────────────

  test "an empty party draws the bot's own sentence for how to fill it" do
    view = open(ok(blank_party()), ok(roster_rows()))
    html = render(view)

    assert html =~ "No party yet. Use rpg.party.add to recruit a bot companion."
    assert html =~ "The Lorekeeper"
    assert html =~ "The Bard"
  end

  test "a companion already with her is not offered again" do
    view = open(ok(party([member()])), ok(roster_rows()))
    html = render(view)

    assert html =~ "The Lorekeeper"
    assert html =~ "The Bard"
    assert html =~ "The Innkeeper"
    refute html =~ ~s(phx-value-bot_id="gtd_bot")
  end

  test "a member the bot sent no character id for is kept and said to be un-actable" do
    view = open(ok(party([member(%{"character_id" => nil})])), ok(roster_rows()))
    html = render(view)

    assert html =~ "The Lorekeeper"
    assert html =~ "the bot sent this member with no character id"
    refute html =~ "Take out of the party"
  end

  test "a party nobody could read is a refusal, and the characters still read" do
    install(fn
      @get_subject -> {:error, :timeout}
      @roster_subject -> ok(roster_rows())
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    html = await(view, "reach the bot")

    assert html =~ "the bot did not answer in time"
    refute html =~ "No party yet"
    # The other question was answered — but with the party unread this screen will not offer
    # a companion she may already have, so the card says which reading is missing instead of
    # drawing a party of nobody or a roster of strangers.
    assert html =~
             "The party has not been read, so this screen is not offering anyone she may already have."

    refute html =~ "Everyone the bot has a character for is already with her."
  end

  test "a roster nobody could read is a refusal, and it does not claim everyone is already in" do
    install(fn
      @get_subject -> ok(blank_party())
      @roster_subject -> {:error, :timeout}
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")

    html = await(view, "reach the bot")

    refute html =~ "Everyone the bot has a character for is already with her."
    assert html =~ "No party yet. Use rpg.party.add to recruit a bot companion."
  end

  test "a roster the bot refuses carries the bot's own word for why" do
    view = open(ok(blank_party()), refusal(":database_unavailable"))

    html = render(view)
    assert html =~ "The bot refused to list the characters it has"
    assert html =~ "database_unavailable"
  end

  # ── one act, two presses, and the reading that confirms it ─────────────────────

  test "a recruit is confirmed by the party reading back with them, not by the write" do
    # The flag is set by the write and read by the party question, so whether the screen
    # says "is with her" depends on the re-read and on nothing else.
    install(fn
      @add_subject ->
        :persistent_term.put(@recruited_key, true)
        ok(%{"name" => "The Adventuring Party", "members" => [member()]})

      @get_subject ->
        if :persistent_term.get(@recruited_key, false),
          do: ok(party([member()])),
          else: ok(blank_party())

      @roster_subject ->
        ok(roster_rows())

      _subject ->
        "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    # One press draws the confirmation and sends nothing.
    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    assert render(view) =~
             "Add The Lorekeeper to the party, and put them in the window if one is open?"

    refute_received {:broker_stub_request, _conn, @add_subject, _payload, _opts}

    # The second press sends it, and the confirmation comes from the party reading back.
    render_click(view, "send")
    html = await(view, "The Lorekeeper is with her — the party reads back with them in it.")

    assert html =~ "The Lorekeeper is with her — the party reads back with them in it."
  end

  test "a write the bot acknowledges that does not change the party is not called done" do
    # The write is acknowledged; the party is not changed. The screen may not read the
    # acknowledgement as the change.
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(blank_party())
      @roster_subject -> ok(roster_rows())
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")
    html = await(view, "not calling it done")

    assert html =~
             "sent, but the party reads back without it, so this screen is not calling it done."

    refute html =~ "The Lorekeeper is with her"
  end

  test "a write the bot refuses is drawn as a refusal, with the bot's own reason" do
    install(fn
      @add_subject -> refusal(":bot_character_failed")
      @get_subject -> ok(blank_party())
      @roster_subject -> ok(roster_rows())
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")
    html = await(view, "The bot refused to recruit gtd_bot")

    assert html =~ "bot_character_failed"
    refute html =~ "The Lorekeeper is with her"
  end

  test "a recruit sends the bot id and the user the party is keyed on" do
    view = open(ok(blank_party()), ok(roster_rows()))

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    assert_receive {:broker_stub_request, _conn, @add_subject, payload, _opts}, 500
    body = Jason.decode!(payload)

    assert body["bot_id"] == "gtd_bot"
    assert body["user_id"] == "abby"
    assert body["tenant_id"] == @tenant
  end

  test "naming the narrator is drawn from the party reading back with the role on them" do
    install(fn
      @narrator_subject ->
        ok(%{"character_id" => @char_gtd, "role" => "narrator"})

      @get_subject ->
        member = member(%{"role" => "narrator"})
        ok(party([member]))

      @roster_subject ->
        ok(roster_rows())
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "narrate",
      "character_id" => @char_gtd,
      "who" => "The Lorekeeper"
    })

    assert render(view) =~ "Let The Lorekeeper write the turns from now on?"

    render_click(view, "send")
    html = await(view, "writes the turns now")

    assert html =~
             "The Lorekeeper writes the turns now — the party reads back with the role on them."

    assert html =~ "narrating"
    assert html =~ "The turns are written by The Lorekeeper."
  end

  test "clearing the narrator sends an explicit null, which is not the same as a missing key" do
    install(fn
      @narrator_subject ->
        ok(%{"character_id" => nil, "role" => nil})

      @get_subject ->
        ok(party([member(%{"role" => "narrator"})]))

      @roster_subject ->
        ok(roster_rows())
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{"verb" => "unname", "who" => "that narrator"})
    render_click(view, "send")

    assert_receive {:broker_stub_request, _conn, @narrator_subject, payload, _opts}, 500
    body = Jason.decode!(payload)

    assert Map.has_key?(body, "character_id")
    assert body["character_id"] == nil
  end

  # ── what is refused here rather than sent ──────────────────────────────────────

  test "an empty bot id is refused here, and nothing is sent" do
    view = open(ok(blank_party()), ok(roster_rows()))

    render_click(view, "act", %{"verb" => "recruit", "bot_id" => ""})

    assert render(view) =~ "There is no bot to recruit"
    refute_received {:broker_stub_request, _conn, @add_subject, _payload, _opts}
  end

  test "a bot the roster has never heard of is recruited by the id she types" do
    # The escape hatch: `rpg.party.add` makes a character for a bot that has none, so the
    # roster is a convenience and not the list of what is possible.
    view = open(ok(blank_party()), ok(roster_rows()))

    render_change(view, "bot_id", %{"bot_id" => "brand_new_bot"})
    render_click(view, "act", %{"verb" => "recruit", "bot_id" => "brand_new_bot"})
    render_click(view, "send")

    assert_receive {:broker_stub_request, _conn, @add_subject, payload, _opts}, 500
    assert Jason.decode!(payload)["bot_id"] == "brand_new_bot"
  end

  test "backing out of the confirmation sends nothing" do
    view = open(ok(blank_party()), ok(roster_rows()))

    render_click(view, "act", %{"verb" => "recruit", "bot_id" => "gtd_bot"})

    assert render(view) =~
             "Add gtd_bot to the party, and put them in the window if one is open?"

    render_click(view, "cancel")

    refute render(view) =~ "Add gtd_bot to the party,"
    refute_received {:broker_stub_request, _conn, @add_subject, _payload, _opts}
  end

  # ── the second step: putting the recruit in the window ───────────────────────

  test "a recruit is put in the window that is open, and the window's party confirms it" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> ok(window_body())
      @state_subject -> ok(window_with(@session, %{@char_gtd => "gtd_bot"}))
      @join_subject -> ok(%{"session_id" => @session})
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    html = await(view, "They are in the window now.")

    assert html =~ "The Lorekeeper is with her — the party reads back with them in it."
    assert html =~ "They are in the window now."

    # The join is asked for by name, with the window and the bot — and no character id,
    # because the bot makes the character it has no character for.
    assert_receive {:broker_stub_request, _conn, @join_subject, payload, _opts}, 500
    body = Jason.decode!(payload)

    assert body["session_id"] == @session
    assert body["bot_id"] == "gtd_bot"
    assert body["tenant_id"] == @tenant
    assert body["user_id"] == "abby"
    refute Map.has_key?(body, "character_id")
  end

  test "the window's party is read with the session and no user, like every other read" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> ok(window_body())
      @state_subject -> ok(window_with(@session, %{@char_gtd => "gtd_bot"}))
      @join_subject -> ok(%{"session_id" => @session})
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")
    await(view, "They are in the window now.")

    assert_receive {:broker_stub_request, _conn, @state_subject, payload, _opts}, 500

    # Naming a user on this read is what makes a window that is open answer "no window": the
    # write names the user the party is keyed on, the read names only the session.
    assert Jason.decode!(payload) == %{"tenant_id" => @tenant, "session_id" => @session}
  end

  test "a recruit with no window open is in the party and in no window, and nothing is joined" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> refusal(":no_active_session")
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    # "There is no window" is a reading, not a failure, and the party half still landed.
    html = await(view, "No window is open.")

    assert html =~ "The Lorekeeper is with her — the party reads back with them in it."
    assert html =~ "No window is open. Nothing has gathered, so there is nothing to say into yet."
    refute_received {:broker_stub_request, _conn, @join_subject, _payload, _opts}
    refute_received {:broker_stub_request, _conn, @state_subject, _payload, _opts}
  end

  test "a recruit the bot refused asks about no window at all" do
    install(fn
      @add_subject -> refusal(":bot_character_failed")
      @get_subject -> ok(blank_party())
      @roster_subject -> ok(roster_rows())
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")
    await(view, "The bot refused to recruit gtd_bot")

    # A window question here would be this screen looking for somewhere to put a companion
    # who is not in the party.
    refute_received {:broker_stub_request, _conn, @context_subject, _payload, _opts}
  end

  test "a window question that did not come back is said on the act, not on the page" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> {:error, :timeout}
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    html = await(view, "not saying whether they are in one")

    assert html =~
             "The bot was not asked about a window — the bot did not answer in time — so this " <>
               "screen is not saying whether they are in one."

    refute html =~ "They are in the window now."
    refute html =~ "The window still reads back without them."
  end

  test "a join the bot refused is a refusal, and the window's party is not read" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> ok(window_body())
      @join_subject -> refusal(":session_not_active")
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    html = await(view, "The bot refused to put gtd_bot in the window")

    assert html =~ "session_not_active"
    refute_received {:broker_stub_request, _conn, @state_subject, _payload, _opts}
  end

  test "a join the bot accepted that the window does not read back is not called done" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> ok(window_body())
      @join_subject -> ok(%{"session_id" => @session})
      @state_subject -> ok(window_with(@session, %{}))
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    html = await(view, "The window still reads back without them.")

    refute html =~ "They are in the window now."
  end

  test "a window party nobody could read is not a no — it is not saying" do
    install(fn
      @add_subject -> ok(%{"members" => [member()]})
      @get_subject -> ok(party([member()]))
      @roster_subject -> ok(roster_rows())
      @context_subject -> ok(window_body())
      @join_subject -> ok(%{"session_id" => @session})
      @state_subject -> {:error, :timeout}
      _subject -> "{}"
    end)

    {:ok, view, _html} = live(build_conn(), "/party-select-phone")
    settle(view)
    drain_requests()

    render_click(view, "act", %{
      "verb" => "recruit",
      "bot_id" => "gtd_bot",
      "who" => "The Lorekeeper"
    })

    render_click(view, "send")

    html = await(view, "party in the window did not read back")

    assert html =~
             "The party in the window did not read back — the bot did not answer in time."

    refute html =~ "The window still reads back without them."
  end

  test "a recruit is only sent into the window that the bot named, not one this screen made up" do
    assert PartySelect.window_for({:open_window, %{id: @session}}) == {:join, @session}

    # A window that does not name itself is not a window to join.
    assert {:unreported, _sentence} = PartySelect.window_for({:open_window, %{id: ""}})

    assert {:no_window, sentence} = PartySelect.window_for({:no_window, "No window is open."})
    assert sentence == "No window is open."

    assert {:unreported, sentence} = PartySelect.window_for({:unreported, "not a window"})
    assert sentence == "not a window"
  end

  test "the window's party is read for the bot, and an unread party is not a no" do
    party = {:party, [%{id: @char_gtd, who: "gtd_bot"}, %{id: @char_llm, who: "llm_bot"}]}

    assert PartySelect.in_window?(party, "gtd_bot") == true
    assert PartySelect.in_window?(party, "synapse") == false
    assert PartySelect.in_window?({:party, []}, "gtd_bot") == false

    assert PartySelect.in_window?({:unreported, "the party was not in the answer"}, "gtd_bot") ==
             nil
  end

  test "the join names the window and the bot, and never a character" do
    body = PartySelect.join_payload(@session, "gtd_bot")

    assert PartySelect.join_subject() == @join_subject
    assert body["session_id"] == @session
    assert body["bot_id"] == "gtd_bot"
    assert body["tenant_id"] == @tenant
    assert body["user_id"] == "abby"
    refute Map.has_key?(body, "character_id")
  end

  test "the confirmation card asks both halves of a recruit" do
    assert PartySelect.ask(%{verb: :recruit, label: "The Lorekeeper"}) ==
             "Add The Lorekeeper to the party, and put them in the window if one is open?"

    assert PartySelect.ask(%{verb: :dismiss, label: "The Lorekeeper"}) ==
             "Take The Lorekeeper out of the party?"
  end

  test "the line says where a recruit got to in the window, and says nothing when it is not known" do
    act = %{confirmed?: true, verb: :recruit, label: "The Lorekeeper", target: "gtd_bot"}

    assert PartySelect.line(act) ==
             "The Lorekeeper is with her — the party reads back with them in it."

    assert PartySelect.line(Map.put(act, :step, {:in_window, true})) ==
             "The Lorekeeper is with her — the party reads back with them in it. " <>
               "They are in the window now."

    assert PartySelect.line(Map.put(act, :step, {:in_window, false})) =~
             "The window still reads back without them."

    assert PartySelect.line(Map.put(act, :step, {:in_window, nil})) =~
             "did not read back, so this screen is not saying they are in it."

    assert PartySelect.line(Map.put(act, :step, {:no_window, "No window is open."})) =~
             " No window is open."

    assert PartySelect.line(Map.put(act, :step, {:unreadable, "the bot did not answer in time."})) =~
             " the bot did not answer in time."

    # A step is not a confirmation: an act that has not been read back yet says so and may
    # still carry where the window half got to.
    unconfirmed = %{state: :sent, verb: :recruit, label: "The Lorekeeper", target: "gtd_bot"}

    assert PartySelect.line(unconfirmed) == "The Lorekeeper — sent, reading the party back…"

    assert PartySelect.line(Map.put(unconfirmed, :step, {:in_window, true})) ==
             "The Lorekeeper — sent, reading the party back… They are in the window now."
  end

  # ── the rules the screen is built on, asked directly ────────────────────────

  # A roster that is still being read is not a roster of nobody. The screen shows "reading";
  # it does not say the characters were not reported, and it does not say everyone is
  # already in.
  test "an unread roster is nothing to say yet, not an empty list" do
    party = {:party, %{members: [], name: "The Adventuring Party", message: nil, raw: %{}}}

    assert PartySelect.candidates(nil, party) == nil

    assert {:unreported, sentence} = PartySelect.candidates({:roster, []}, nil)
    assert sentence =~ "The party has not been read"
  end

  # A refusal is the bot's own word, carried — never a reading.
  test "a refused party is a sentence in the bot's own words" do
    assert {:unreported, sentence} =
             PartySelect.party(%{"ok" => false, "error" => ":database_unavailable"})

    assert sentence =~ "refused the question about the party"
    assert sentence =~ "database_unavailable"
  end
end
