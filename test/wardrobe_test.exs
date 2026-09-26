defmodule BotArmyDashboardLiveview.WardrobeTest do
  @moduledoc """
  The wardrobe card's own rules, without a broker in the way.

  Three of these are the reason the module exists at all, and each one is a lie that
  used to be possible:

    * a read that failed arriving as an empty wardrobe. `BotRead` hands a
      `{"ok": false}` envelope straight through — it does not check `ok` — so a
      wardrobe that could not be read looks exactly like a successful read of nothing,
      and "the closet has no sets" is a claim about her rather than about the read;
    * an assignment drawn as her choice. The mark comes off the bot's own `chosen`
      field, and a `chosen` that is neither true nor false is not rounded to either
      answer;
    * a write confirmed by its own acknowledgement. What confirms a wear is the
      re-read — the same set, the same mark, and today's — because a wear that failed
      leaves the *previous* wearing of that set still open.
  """

  use ExUnit.Case, async: true

  alias BotArmyDashboardLiveview.Wardrobe

  @maid "2a5f4b40-1111-4000-8000-000000000001"
  @secretary "2a5f4b40-1111-4000-8000-000000000002"

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp set(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @maid,
        "name" => "Maid",
        "cage" => "standard",
        "plug" => "standard",
        "clothing" => "maid dress",
        "accessories" => ["collar"],
        "humiliation_level" => 6,
        "description" => "the one with the apron",
        "archived_at" => nil
      },
      overrides
    )
  end

  defp secretary do
    set(%{
      "id" => @secretary,
      "name" => "Secretary",
      "clothing" => "pencil skirt",
      "accessories" => [],
      "humiliation_level" => 7
    })
  end

  defp worn(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Maid",
        "outfit_id" => @maid,
        "chosen" => true,
        "worn_at" => now(),
        "parts" => %{"cage" => "standard", "humiliation_level" => 6, "accessories" => []}
      },
      overrides
    )
  end

  defp reply(opts \\ []) do
    sets = Keyword.get(opts, :sets, [set()])
    on = Keyword.get(opts, :worn, worn())

    %{
      "sets" => sets,
      "worn" => on,
      "catalogue" => %{"humiliation_level" => %{"min" => 1, "max" => 10}}
    }
  end

  defp mark(closet), do: closet.on && closet.on.mark

  # ── what is drawn is the bot's ──────────────────────────────────────────────

  test "a set is drawn from the bot's own row, over the range the bot published" do
    closet = Wardrobe.build(reply())

    assert [drawn] = closet.sets
    assert drawn.id == @maid
    assert drawn.name == "Maid"
    assert drawn.description == "the one with the apron"
    assert drawn.detail =~ "cage standard"
    assert drawn.detail =~ "clothing maid dress"
    assert drawn.detail =~ "accessories collar"
    assert drawn.detail =~ "humiliation 6 of 10"
    refute closet.refused
    refute closet.empty?
  end

  test "a level the catalogue does not describe gets no denominator this screen invented" do
    answer = Map.put(reply(), "catalogue", %{})
    detail = hd(Wardrobe.build(answer).sets).detail

    assert detail =~ "humiliation 6"
    refute detail =~ "of 10"
  end

  test "a part that did not arrive is left out rather than drawn blank" do
    detail = hd(Wardrobe.build(reply(sets: [set(%{"plug" => nil, "cage" => ""})])).sets).detail

    assert detail =~ "clothing maid dress"
    refute detail =~ "plug"
    refute detail =~ "cage"
  end

  test "the wearing is drawn from the bot's own snapshot of what went on" do
    closet = Wardrobe.build(reply())

    assert closet.on.name == "Maid"
    assert closet.on.id == @maid
    assert closet.on.detail =~ "humiliation 6 of 10"
  end

  # ── chosen or assigned, and never rounded ───────────────────────────────────

  test "the mark is the bot's own record of who put it on" do
    assert mark(Wardrobe.build(reply(worn: worn(%{"chosen" => true})))) == :chosen
    assert mark(Wardrobe.build(reply(worn: worn(%{"chosen" => false})))) == :assigned
  end

  test "a mark that is not an answer is not rounded to one" do
    for chosen <- [nil, "true", 0, %{}] do
      assert mark(Wardrobe.build(reply(worn: worn(%{"chosen" => chosen})))) == :unstated,
             "expected #{inspect(chosen)} to read as unrecorded"
    end
  end

  test "the assigned mark says who put it on, and never reads as a choice" do
    closet = Wardrobe.build(reply(worn: worn(%{"chosen" => false, "worn_by" => "louiza"})))

    assert closet.on.mark == :assigned
    assert Wardrobe.mark_word(:assigned) == "assigned"
    assert Wardrobe.mark_word(:assigned) != Wardrobe.mark_word(:chosen)
    assert Wardrobe.mark_class(:assigned) != Wardrobe.mark_class(:chosen)
    assert Wardrobe.mark_sentence(:assigned) =~ "put on her, not chosen by her"
  end

  test "nothing on her is nothing, not a set with no name" do
    closet = Wardrobe.build(reply(worn: nil))

    assert closet.on == nil
    refute closet.empty?
    refute closet.refused
  end

  # ── a failed read is not an empty wardrobe ─────────────────────────────────

  test "a refused read is a refusal, never an empty wardrobe" do
    closet =
      Wardrobe.build(%{
        "ok" => false,
        "error" => "the wardrobe could not be read",
        "code" => "unavailable"
      })

    assert closet.refused == "the wardrobe could not be read"
    assert closet.sets == []
    assert closet.on == nil
    refute closet.empty?
  end

  test "a refusal with nothing to say still refuses" do
    closet = Wardrobe.build(%{"ok" => false})

    assert closet.refused
    refute closet.empty?
  end

  test "an answer that is not a wardrobe is a refusal" do
    answers = [
      %{"sets" => "nope"},
      %{"sets" => [%{"name" => "Maid"}]},
      %{"sets" => [set(), "nope"]},
      %{"sets" => [set()], "worn" => "nope"},
      %{"sets" => [set()], "worn" => 13},
      %{"sets" => [set()], "worn" => %{}},
      %{},
      [],
      "nope",
      nil
    ]

    for answer <- answers do
      closet = Wardrobe.build(answer)

      assert closet.refused, "expected a refusal for #{inspect(answer)}"
      assert closet.sets == []
      refute closet.empty?
    end
  end

  test "one unreadable row refuses the wardrobe, so no set can quietly go missing" do
    closet = Wardrobe.build(reply(sets: [set(), secretary() |> Map.put("id", nil)]))

    assert closet.refused
    assert closet.sets == []
  end

  test "a wardrobe with no sets in it is empty, and that is not a refusal" do
    closet = Wardrobe.build(reply(sets: []))

    assert closet.sets == []
    assert closet.empty?
    refute closet.refused
  end

  # ── one tap ────────────────────────────────────────────────────────────────

  describe "plan/3" do
    test "wearing is sent in her voice and assigning in the house's" do
      closet = Wardrobe.build(reply())

      assert {:send, %{"outfit_id" => @maid, "by" => "subject"}, act} =
               Wardrobe.plan(:wear, @maid, closet)

      assert act.verb == :wear
      assert act.name == "Maid"

      assert {:send, %{"outfit_id" => @maid, "by" => "louiza"}, act} =
               Wardrobe.plan(:assign, @maid, closet)

      assert act.verb == :assign
    end

    test "the two voices and the two subjects are the bot's own" do
      assert Wardrobe.chosen_by() == "subject"
      assert Wardrobe.assigned_by() == "louiza"
      assert Wardrobe.read_subject() == "wife_care.control_panel.wardrobe.list"
      assert Wardrobe.write_subject() == "wife_care.control_panel.wear_outfit"
    end

    test "a set the card is not drawing is refused here, so nothing is sent" do
      loaded = Wardrobe.build(reply())

      # A tap with no set on it is not a stale page: the two facts get two sentences,
      # and the other two (never read, could not be read) are in the test below.
      assert {:refused, %{error: no_set}} = Wardrobe.plan(:wear, nil, loaded)
      assert no_set =~ "no set on it"

      assert {:refused, %{error: not_drawn}} = Wardrobe.plan(:wear, @secretary, loaded)
      assert not_drawn =~ "not on this card"

      for id <- ["", 7, %{}] do
        assert {:refused, %{error: sentence}} = Wardrobe.plan(:assign, id, loaded)
        assert sentence =~ "no set on it"
      end
    end

    test "a wardrobe that was not read cannot be worn from" do
      assert {:refused, %{error: unread}} = Wardrobe.plan(:wear, @maid, nil)
      assert unread =~ "the wardrobe has not been read yet"
      assert unread =~ "nothing was sent"

      refused = Wardrobe.build(%{"ok" => false, "error" => "the wardrobe could not be read"})
      assert {:refused, %{error: sentence}} = Wardrobe.plan(:assign, @maid, refused)
      assert sentence =~ "the wardrobe could not be read, so nothing was sent"
    end

    test "a verb this screen does not have is refused" do
      assert {:refused, %{error: error}} = Wardrobe.plan(:burn, @maid, Wardrobe.build(reply()))
      assert error =~ "nothing was sent"
    end
  end

  # ── the read afterwards is the sentence ────────────────────────────────────

  describe "settle/2" do
    test "a wear is confirmed by a re-read that names the set, marked the same way, today" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))
      settled = Wardrobe.settle(act, Wardrobe.build(reply(worn: worn(%{"chosen" => true}))))

      assert settled.confirmed?
      assert Wardrobe.line(settled) =~ "recorded as her choice"
    end

    test "an assignment is confirmed as an assignment" do
      {:send, _payload, act} = Wardrobe.plan(:assign, @maid, Wardrobe.build(reply()))
      settled = Wardrobe.settle(act, Wardrobe.build(reply(worn: worn(%{"chosen" => false}))))

      assert settled.confirmed?
      assert Wardrobe.line(settled) =~ "recorded as assigned"
      assert Wardrobe.line(settled) =~ "not chosen by her"
    end

    test "a set that reads back as hers does not confirm an assignment" do
      {:send, _payload, act} = Wardrobe.plan(:assign, @maid, Wardrobe.build(reply()))
      settled = Wardrobe.settle(act, Wardrobe.build(reply(worn: worn(%{"chosen" => true}))))

      refute Map.get(settled, :confirmed?, false)
      assert Wardrobe.line(settled) =~ "recorded as her choice"
      assert Wardrobe.line(settled) =~ "showing what the wardrobe says"
      refute Wardrobe.line(settled) =~ "recorded as assigned —"
    end

    test "a stale wearing of the same set does not confirm a write that never landed" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))

      yesterday =
        DateTime.utc_now()
        |> DateTime.add(-86_400, :second)
        |> DateTime.to_iso8601()

      stale = Wardrobe.build(reply(worn: worn(%{"chosen" => true, "worn_at" => yesterday})))
      settled = Wardrobe.settle(act, stale)

      refute Map.get(settled, :confirmed?, false)
      assert Wardrobe.line(settled) =~ "showing what the wardrobe says"
    end

    test "a wearing with no date at all confirms nothing" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))
      settled = Wardrobe.settle(act, Wardrobe.build(reply(worn: worn(%{"worn_at" => nil}))))

      refute Map.get(settled, :confirmed?, false)
    end

    test "another set on her, or nothing on her, does not confirm" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))

      other =
        Wardrobe.settle(
          act,
          Wardrobe.build(reply(worn: worn(%{"name" => "Secretary", "outfit_id" => @secretary})))
        )

      refute Map.get(other, :confirmed?, false)
      assert Wardrobe.line(other) =~ "Secretary, recorded as her choice"

      none = Wardrobe.settle(act, Wardrobe.build(reply(worn: nil)))
      refute Map.get(none, :confirmed?, false)
      assert none.reading == "nothing on her"
    end

    test "a wardrobe that could not be re-read says so instead of claiming nothing is on her" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))
      settled = Wardrobe.settle(act, Wardrobe.build(%{"ok" => false, "error" => "no"}))

      refute Map.get(settled, :confirmed?, false)
      assert settled.reading == "a wardrobe that could not be read"
      refute Wardrobe.line(settled) =~ "nothing on her"
    end

    test "a write that never left keeps its own sentence through a later read" do
      {:send, _payload, act} = Wardrobe.plan(:wear, @maid, Wardrobe.build(reply()))
      failed = Map.put(act, :error, "no answer from the wife care bot — nothing was recorded")
      settled = Wardrobe.settle(failed, Wardrobe.build(reply(worn: worn(%{"chosen" => true}))))

      refute Map.get(settled, :confirmed?, false)
      assert Wardrobe.line(settled) == "no answer from the wife care bot — nothing was recorded"
      assert Wardrobe.class(settled) == "unreported"
    end

    test "a line before the read lands claims nothing" do
      {:send, _payload, act} = Wardrobe.plan(:assign, @maid, Wardrobe.build(reply()))

      assert Wardrobe.line(act) =~ "reading the wardrobe back"
      refute Wardrobe.line(act) =~ "recorded as"
      assert Wardrobe.class(act) == "dim"
    end
  end
end
