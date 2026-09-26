defmodule BotArmyDashboardLiveview.PartyWindowTest do
  @moduledoc """
  The window reader: what the bot's answers mean, and what this screen may say about them.

  The live bot has no session open (`rpg.session.gather_context` answers
  `:no_active_session`), so the stub answers here are the only way to put a window in
  front of this module at all. They are shaped like the replies the bot actually
  sends — `{"ok" => true, "data" => %{…}}` already unwrapped by `BotRead`, and
  `{"ok" => false, "error" => ":no_active_session"}` for a refusal — because those
  are the shapes that matter.

  Three things this pins that only the answers can show. A missing field is not an
  empty list: a window whose turns were never reported does not read as "nothing has
  been said", and a party field that was never sent does not read as "nobody
  joined". A refusal other than `:no_active_session` is not a report that no window
  is open. And a reply is confirmed by the window reading back with it, never by the
  write's own ok.
  """

  use ExUnit.Case, async: false

  alias BotArmyDashboardLiveview.PartyWindow

  @app :bot_army_dashboard_liveview

  @session "e291bf79-1111-4000-8000-000000000001"
  @char1 "c1a0f2e0-2222-4000-8000-000000000001"
  @char2 "c1a0f2e0-2222-4000-8000-000000000002"

  defp answer(overrides \\ %{}) do
    Map.merge(
      %{
        "session_id" => @session,
        "session_status" => "active",
        "scene_description" => "Neon-drenched alleyway under a flickering ad.",
        "scene_facts" => ["the newest thing", "an earlier thing"],
        "theme" => %{"setting" => "cyberpunk", "tone" => "gritty", "mechanic" => "hacking"},
        "character" => %{
          "name" => "the maid",
          "bot_id" => "wife_care",
          "class" => "maid",
          "level" => 3
        }
      },
      overrides
    )
  end

  describe "window/1" do
    test "a window reads as the session, its scene, its theme and its character" do
      assert {:open_window, window} = PartyWindow.window(answer())

      assert window.id == @session
      assert window.status == "active"
      assert window.scene =~ "alleyway"
      assert window.theme == %{setting: "cyberpunk", tone: "gritty", mechanic: "hacking"}
      assert window.character == %{name: "the maid", bot_id: "wife_care", class: "maid", level: 3}
    end

    test "the turns come back oldest first, because the bot sends newest first" do
      assert {:open_window, window} = PartyWindow.window(answer())

      assert PartyWindow.turns(window) == ["an earlier thing", "the newest thing"]
    end

    test "a window whose turns were not reported does not read as nothing said" do
      assert {:open_window, window} = PartyWindow.window(answer(%{"scene_facts" => nil}))

      assert window.facts == nil
      assert PartyWindow.turns(window) == nil
    end

    test "a window the bot reported with no turns reads as nothing said, not as unreported" do
      assert {:open_window, window} = PartyWindow.window(answer(%{"scene_facts" => []}))

      assert PartyWindow.turns(window) == []
    end

    test "a scene the bot did not describe is not reported, and is not an empty sentence" do
      assert {:open_window, window} = PartyWindow.window(answer(%{"scene_description" => nil}))

      assert window.scene == nil
    end

    test "a theme and a character the bot did not send are not reported" do
      assert {:open_window, window} =
               PartyWindow.window(answer(%{"theme" => %{}, "character" => %{}}))

      assert window.theme == nil
      assert window.character == nil
    end

    test "the story so far is carried, oldest first, naming who spoke" do
      assert {:open_window, window} =
               PartyWindow.window(
                 answer(%{
                   "carry_history" => [
                     %{
                       "content" => "Hi!",
                       "source" => "operator",
                       "session_id" => "earlier-window",
                       "at" => "2026-09-26T21:32:40"
                     },
                     %{"content" => "the GM closed the door", "source" => "gm"}
                   ]
                 })
               )

      assert PartyWindow.history(window) == [
               %{text: "Hi!", who: "the operator"},
               %{text: "the GM closed the door", who: "the GM"}
             ]
    end

    test "a carry the bot looked at and found empty is a reading, not an unreported one" do
      assert {:open_window, window} = PartyWindow.window(answer(%{"carry_history" => []}))

      assert PartyWindow.history(window) == []
    end

    test "a carry that was not reported does not read as nothing came before" do
      # Three ways to get here: the bot could not read it (nil), the bot does not know
      # the field (key absent), or this is not a window at all. All three are "the bot
      # did not say", and none of them is "nothing came before".
      for carried <- [%{"carry_history" => nil}, %{}] do
        assert {:open_window, window} = PartyWindow.window(answer(carried))
        assert PartyWindow.history(window) == nil
      end

      assert PartyWindow.history(nil) == nil
      assert PartyWindow.history(%{facts: ["a turn"]}) == nil
    end

    test "a carried row without a line is not drawn as a turn, and an unnamed source is named" do
      assert {:open_window, window} =
               PartyWindow.window(
                 answer(%{
                   "carry_history" => [
                     %{"content" => "kept"},
                     %{"content" => "from someone unnamed", "source" => nil},
                     %{"source" => "operator"}
                   ]
                 })
               )

      assert PartyWindow.history(window) == [
               %{text: "kept", who: "someone the bot did not name"},
               %{text: "from someone unnamed", who: "someone the bot did not name"}
             ]
    end

    test "no active session is a definite nothing, said in this screen's words" do
      assert {:no_window, sentence} =
               PartyWindow.window(%{"ok" => false, "error" => ":no_active_session"})

      assert sentence =~ "No window is open"
      refute sentence =~ "no_active_session"
    end

    test "any other refusal is not a report that no window is open" do
      assert {:unreported, sentence} =
               PartyWindow.window(%{"ok" => false, "error" => ":database_error"})

      assert sentence =~ "database_error"
      assert sentence =~ "not reporting one"
    end

    test "an answer that never mentioned a window is not a report of none" do
      assert {:unreported, sentence} = PartyWindow.window(%{"hello" => "there"})

      assert sentence =~ "not with a window"
    end

    test "a session id that is not a string is not a window" do
      assert {:unreported, _sentence} = PartyWindow.window(answer(%{"session_id" => 42}))
    end
  end

  describe "party/1" do
    test "the party is the session's joined characters, named by the bot that joined" do
      assert {:party, rows} =
               PartyWindow.party(%{"character_ids" => %{@char1 => "gtd_bot", @char2 => "llm_bot"}})

      assert rows == [
               %{id: @char1, who: "gtd_bot"},
               %{id: @char2, who: "llm_bot"}
             ]
    end

    test "an empty party is a reading — nobody has joined" do
      assert PartyWindow.party(%{"character_ids" => %{}}) == {:party, []}
    end

    test "a party field the bot never sent is not an empty party" do
      assert {:unreported, sentence} = PartyWindow.party(%{"id" => @session})

      assert sentence =~ "not in the answer"
    end

    test "a party read that was refused says so, in the bot's own word" do
      assert {:unreported, sentence} =
               PartyWindow.party(%{"ok" => false, "error" => ":not_found"})

      assert sentence =~ "not_found"
    end
  end

  describe "a draft" do
    test "a reply is trimmed, and an empty one is refused" do
      assert PartyWindow.draft("  hello  ") == {:ok, "hello"}
      assert {:refused, sentence} = PartyWindow.draft("   ")
      assert sentence =~ "nothing to say"
      assert {:refused, _sentence} = PartyWindow.draft("")
      assert {:refused, _sentence} = PartyWindow.draft(nil)
    end

    test "a reply past the ceiling is refused with the ceiling in the reason" do
      long = String.duplicate("a", PartyWindow.max_reply() + 1)

      assert {:refused, sentence} = PartyWindow.draft(long)
      assert sentence =~ to_string(PartyWindow.max_reply())
      assert sentence =~ "longer"
    end
  end

  describe "the bodies this screen sends" do
    test "the window question names the tenant, and no user" do
      # The fleet's own `rpg.session.start` names no user, so its sessions carry
      # `user_id: nil`; naming a user here that no session carries would make this
      # screen say "no window is open" while one is open.
      # The window question also asks for the story so far — the identity is what this
      # test is about, and the carry rides along on every window read.
      assert PartyWindow.context_payload() == %{
               "tenant_id" => "00000000-0000-0000-0000-000000000001",
               "carry_history" => true
             }

      refute Map.has_key?(PartyWindow.context_payload(), "user_id")
      assert PartyWindow.user_id() == nil
    end

    test "a user is named once an operator pins one, and then it is on the wire" do
      Application.put_env(@app, :party_user_id, "11111111-1111-1111-1111-111111111111")

      on_exit(fn -> Application.delete_env(@app, :party_user_id) end)

      assert PartyWindow.context_payload() == %{
               "tenant_id" => "00000000-0000-0000-0000-000000000001",
               "user_id" => "11111111-1111-1111-1111-111111111111",
               "carry_history" => true
             }

      assert PartyWindow.write_payload(@session, "hello")["user_id"] ==
               "11111111-1111-1111-1111-111111111111"
    end

    test "an empty pinned user id names nobody rather than naming nothing" do
      Application.put_env(@app, :party_user_id, "")

      on_exit(fn -> Application.delete_env(@app, :party_user_id) end)

      refute Map.has_key?(PartyWindow.context_payload(), "user_id")
    end

    test "the identity is configurable, because the deployment is not this screen's to assume" do
      Application.put_env(@app, :party_user_id, "11111111-1111-1111-1111-111111111111")
      Application.put_env(@app, :party_tenant_id, "22222222-2222-2222-2222-222222222222")

      on_exit(fn ->
        Application.delete_env(@app, :party_user_id)
        Application.delete_env(@app, :party_tenant_id)
      end)

      assert PartyWindow.context_payload() == %{
               "tenant_id" => "22222222-2222-2222-2222-222222222222",
               "user_id" => "11111111-1111-1111-1111-111111111111",
               "carry_history" => true
             }
    end

    test "the party question names the session it is about" do
      assert PartyWindow.state_payload(@session)["session_id"] == @session
    end

    test "a reply is filed as the operator speaking, never as her" do
      body = PartyWindow.write_payload(@session, "hello")

      assert body["session_id"] == @session
      assert body["content"] == "hello"
      assert body["source"] == "operator"
      assert body["category"] == "dialogue"
      refute body["source"] == "louiza"
    end
  end

  describe "settle/2 — the confirmation is the re-read" do
    test "a reply the window reads back with is confirmed" do
      act = %{text: "hello", state: :sent}
      window = %{facts: ["an earlier thing", "hello"]}

      assert PartyWindow.settle(act, window).confirmed? == true
    end

    test "a reply the window does not read back says so, and is not confirmed" do
      act = %{text: "hello", state: :sent}
      window = %{facts: ["something else"]}

      settled = PartyWindow.settle(act, window)
      refute settled.confirmed?
      assert settled.reading =~ "without it"
      assert PartyWindow.line(settled) =~ "not calling it said"
    end

    test "a window whose turns were not reported cannot confirm anything" do
      act = %{text: "hello", state: :sent}

      refute Map.has_key?(PartyWindow.settle(act, %{facts: nil}), :confirmed?)
    end

    test "a refusal and a failed send are not overtaken by a later read" do
      refused = %{state: :refused, sentence: "nothing to say"}
      failed = %{state: :error, sentence: "the bot is not reachable right now"}

      assert PartyWindow.settle(refused, %{facts: ["hello"]}) == refused
      assert PartyWindow.settle(failed, %{facts: ["hello"]}) == failed
      assert PartyWindow.settle(nil, %{facts: []}) == nil
    end
  end

  describe "the sentence a reply act owns" do
    test "a refusal is not styled like a reading" do
      assert PartyWindow.class(%{state: :refused}) == "unreported"
      assert PartyWindow.class(%{state: :error}) == "unreported"
      assert PartyWindow.class(%{state: :sent}) == "dim"
      assert PartyWindow.class(%{state: :sent, confirmed?: true}) == "ok"
    end

    test "each state reads as itself" do
      assert PartyWindow.line(%{state: :refused, sentence: "no"}) == "no"
      assert PartyWindow.line(%{state: :error, sentence: "down"}) == "down"
      assert PartyWindow.line(%{state: :review}) =~ "check it"
      assert PartyWindow.line(%{state: :sent}) =~ "reading the window back"
      assert PartyWindow.line(%{state: :sent, confirmed?: true}) =~ "reads back with your reply"
      assert PartyWindow.line(nil) == ""
    end
  end
end
