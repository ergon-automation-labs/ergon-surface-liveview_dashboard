defmodule BotArmyDashboardLiveview.HypnosisShelfTest do
  @moduledoc """
  The shelf's own module: what a reply becomes, what a tap may send, and what the
  sentence after a tap is allowed to claim.

  The three things this pins hardest are the three ways a shelf can lie. A reply that is
  not a shelf must refuse rather than draw an empty shelf, because an empty shelf says
  she has asked to hear nothing. A row this screen cannot read must refuse the whole
  shelf, because a phrase quietly missing looks exactly like one she never asked for.
  And `ok: false` must be matched, because `BotRead` does not check it — the bot's own
  refusal arrives looking like a successful read of nothing.
  """

  # The stub swaps the process-wide broker transport, so this module is not async.
  use ExUnit.Case, async: false

  alias BotArmyDashboardLiveview.BrokerStub
  alias BotArmyDashboardLiveview.HypnosisShelf

  @app :bot_army_dashboard_liveview
  @read "wife_care.control_panel.hypnosis"
  @write "wife_care.control_panel.hypnosis_phrase"

  @p1 "5f1a0f2e-1111-4000-8000-000000000001"
  @p2 "5f1a0f2e-1111-4000-8000-000000000002"
  @p3 "5f1a0f2e-1111-4000-8000-000000000003"

  setup do
    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  defp stub(reply) do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_reply, reply)
  end

  # A phrase in the shape the bot sends it: `Hypnosis.view/1`'s own fields, with the
  # `on?` boolean the card draws from.
  defp phrase(opts) do
    on = Keyword.get(opts, :on, true)

    phrase = %{
      "id" => Keyword.get(opts, :id, @p1),
      "key" => "worth",
      "text" => Keyword.get(opts, :text, "you are worth the trouble"),
      "person" => "i",
      "person_label" => "I",
      "intent" => "worth",
      "intent_label" => "Her worth",
      "detail" => Keyword.get(opts, :detail, "said when she is low"),
      "state" => if(on, do: "on", else: "off"),
      "state_label" => if(on, do: "in the air", else: "off the air"),
      "on?" => on,
      "removed?" => false,
      "authored_by" => "subject",
      "supersedes_id" => nil,
      "added_at" => "2026-09-25T10:00:00Z"
    }

    Map.merge(phrase, delivery_keys(opts))
  end

  # The delivery facts are merged in only where a test names them, so that "the bot sent
  # no `said_count`" stays a phrase without one — absent is not a zero, and a helper that
  # filled the key in with `nil` would be testing a shape the bot never sends.
  @delivery_keys %{
    repeat: "repeat",
    repeat_label: "repeat_label",
    said_count: "said_count",
    last_said_at: "last_said_at",
    due?: "due?"
  }

  defp delivery_keys(opts) do
    for {opt, key} <- @delivery_keys, Keyword.has_key?(opts, opt), into: %{}, do: {key, opts[opt]}
  end

  defp shelf_reply(opts) do
    block =
      %{
        "phrases" => Keyword.get(opts, :phrases, []),
        "put_away" => Keyword.get(opts, :put_away, []),
        "rewritten" => Keyword.get(opts, :rewritten, []),
        "catalogue" => [],
        "counts" => %{"on" => 0, "off" => 0, "put_away" => 0, "rewritten" => 0},
        "max_text" => 240
      }
      |> Map.merge(Keyword.get(opts, :block, %{}))

    %{"hypnosis" => block, "narration_allowed" => Keyword.get(opts, :narration, true)}
  end

  defp built(opts \\ []), do: shelf_reply(opts) |> HypnosisShelf.build()

  # One phrase, as the screen holds it: the raw reply row goes through `build/1` and comes
  # back the way `row_view/1` made it. The readers below take that row, not the bot's raw
  # map — a test that handed them the raw map would be testing a shape the screen never
  # passes them.
  defp row(opts) do
    built(phrases: [phrase(opts)]).phrases |> hd()
  end

  # ── the seam ────────────────────────────────────────────────────────────────

  test "the screen reads and writes the subjects the bot serves, as the operator" do
    assert HypnosisShelf.read_subject() == @read
    assert HypnosisShelf.write_subject() == @write
    # Not `subject`: this dashboard proves nothing about who is holding the phone, and
    # her voice is the one it must not forge.
    assert HypnosisShelf.actor() == "operator"
  end

  # ── the read ────────────────────────────────────────────────────────────────

  test "a shelf arrives with its three lists and its two states" do
    shelf =
      built(
        phrases: [
          phrase(id: @p1, text: "you are worth the trouble"),
          phrase(id: @p2, text: "the house notices", on: false)
        ],
        put_away: [phrase(id: @p3, text: "you are a good girl", on: false)],
        rewritten: [phrase(id: @p1, text: "you are worth it", on: true)]
      )

    assert shelf.refused == nil
    assert shelf.narration == :allowed

    assert Enum.map(shelf.phrases, & &1.text) == [
             "you are worth the trouble",
             "the house notices"
           ]

    assert Enum.map(shelf.put_away, & &1.text) == ["you are a good girl"]
    assert Enum.map(shelf.rewritten, & &1.text) == ["you are worth it"]
    # The counts are the screen's own count of the rows it is drawing, so a list and its
    # number can never disagree.
    assert shelf.counts == %{on: 1, off: 1, away: 1, reworded: 1, cadenced: 0}
    refute shelf.empty?
  end

  test "a shelf with nothing in the air is the empty shelf, and says so with its counts" do
    shelf = built(put_away: [phrase(id: @p3, on: false)])

    assert shelf.empty?
    assert shelf.counts == %{on: 0, off: 0, away: 1, reworded: 0, cadenced: 0}
    assert HypnosisShelf.counts_line(shelf) =~ "0 in the air"
    assert HypnosisShelf.counts_line(shelf) =~ "1 taken away"
  end

  # The bot's refusal arrives as a successful read with `ok: false`, because `BotRead`
  # does not check it. Read as a shelf, that is an empty shelf — she asked to hear
  # nothing — which is the exact opposite of the truth.
  test "a refusal is refused, not read as an empty shelf" do
    shelf = HypnosisShelf.build(%{"ok" => false, "error" => "the store is not reachable"})

    assert shelf.refused == "the store is not reachable"
    assert shelf.narration == :unstated
    refute shelf.empty?
    assert shelf.phrases == []
  end

  test "a refusal with no words says so, rather than saying nothing happened" do
    shelf = HypnosisShelf.build(%{"ok" => false})

    assert shelf.refused == "the bot refused the read without saying why"
  end

  test "a shelf the store could not read is a refusal with the bot's own words" do
    shelf =
      HypnosisShelf.build(%{"hypnosis" => %{"unavailable" => "the shelf is not readable"}})

    assert shelf.refused == "the shelf could not be read: the shelf is not readable"
    refute shelf.empty?
  end

  test "an answer that is not a shelf refuses the card rather than drawing an empty one" do
    assert HypnosisShelf.build(%{"hypnosis" => "nope"}).refused ==
             "the bot answered with a shelf this screen cannot read"

    assert HypnosisShelf.build(%{"something" => "else"}).refused ==
             "the bot answered, but not with a shelf"

    assert HypnosisShelf.build(nil).refused == "the bot answered, but not with a shelf"
  end

  test "a shelf missing one of its lists refuses the whole shelf" do
    shelf = HypnosisShelf.build(%{"hypnosis" => %{"phrases" => [], "put_away" => []}})

    assert shelf.refused == "the shelf answered with something this screen cannot read"
    refute shelf.empty?
  end

  # A phrase quietly dropped is the one failure that looks exactly like success: the card
  # would draw a shorter shelf and say nothing about the one it lost.
  test "a row this screen cannot read refuses the whole shelf" do
    for bad <- [
          %{"text" => "no id", "on?" => true},
          %{"id" => @p1, "on?" => true},
          %{"id" => @p1, "text" => "an unstated state"},
          %{"id" => "", "text" => "an empty id", "on?" => true},
          "not a row"
        ] do
      shelf = built(phrases: [phrase(id: @p2), bad])

      assert shelf.refused == "the shelf answered with something this screen cannot read"
      refute shelf.empty?
      # And nothing of the good row leaks onto the page: the whole list is refused, not
      # the row.
      assert shelf.phrases == []
    end
  end

  # ── narration, three states ─────────────────────────────────────────────────

  test "the narration is three states and the third is fail-closed" do
    assert built(narration: true).narration == :allowed
    assert built(narration: false).narration == :stopped
    assert built(narration: nil).narration == :unstated
    assert built(narration: "yes").narration == :unstated
  end

  test "an unstated narration never reads as permission" do
    assert HypnosisShelf.narration_word(:unstated) == "not stated"
    assert HypnosisShelf.narration_sentence(:unstated) =~ "reads it as: it may not"
    assert HypnosisShelf.narration_class(:unstated) == "unreported"

    assert HypnosisShelf.narration_class(:stopped) == "stop-note"
    assert HypnosisShelf.narration_sentence(:stopped) =~ "her stop is in place"
  end

  test "the two verbs and the two phrase states are said once, here" do
    assert HypnosisShelf.verb_word(:switch_off) == "Switch off"
    assert HypnosisShelf.verb_word(:take_away) == "Take away"
    assert HypnosisShelf.phrase_word(%{on: true}) == "in the air"
    assert HypnosisShelf.phrase_word(%{on: false}) == "off the air"
    assert HypnosisShelf.phrase_class(%{on: true}) == "chip live"
    assert HypnosisShelf.phrase_class(%{on: false}) == "chip off"
  end

  # ── a tap ───────────────────────────────────────────────────────────────────

  test "switching off sends the switch verb, as the operator, and claims nothing else" do
    shelf = built(phrases: [phrase(id: @p1, on: true)])

    assert {:send, payload, act} = HypnosisShelf.plan(:switch_off, @p1, shelf)

    assert payload == %{
             "action" => "switch",
             "id" => @p1,
             "state" => "off",
             "actor" => "operator"
           }

    assert act == %{verb: :switch_off, id: @p1, text: "you are worth the trouble"}
  end

  test "taking away sends the remove verb, and it is the only verb that applies to any phrase" do
    on = built(phrases: [phrase(id: @p1, on: true)])
    off = built(phrases: [phrase(id: @p2, on: false)])

    assert {:send, payload, _act} = HypnosisShelf.plan(:take_away, @p1, on)
    assert payload == %{"action" => "remove", "id" => @p1, "actor" => "operator"}

    assert {:send, _payload, _act} = HypnosisShelf.plan(:take_away, @p2, off)
  end

  test "switching off a phrase that is already off is refused here, not sent to the bot" do
    shelf = built(phrases: [phrase(id: @p2, on: false)])

    assert {:refused, act} = HypnosisShelf.plan(:switch_off, @p2, shelf)
    assert act.error =~ "already off the air"
    assert act.error =~ "nothing was sent"
  end

  test "a phrase the card is not drawing is refused with the page reload in the answer" do
    shelf = built(phrases: [phrase(id: @p1)], put_away: [phrase(id: @p3, on: false)])

    # An id that is on the away list is not on the live list, so it cannot be switched.
    assert {:refused, act} = HypnosisShelf.plan(:switch_off, @p3, shelf)
    assert act.error =~ "not on this shelf"
    assert act.error =~ "nothing was sent"

    assert {:refused, _act} = HypnosisShelf.plan(:switch_off, "made-up-id", shelf)
  end

  test "a tap is refused in its own words: no phrase, no read, a failed read, a foreign verb" do
    shelf = built(phrases: [phrase(id: @p1)])

    assert {:refused, %{error: no_phrase}} = HypnosisShelf.plan(:switch_off, nil, shelf)
    assert no_phrase =~ "no phrase on it"

    assert {:refused, %{error: empty_phrase}} = HypnosisShelf.plan(:take_away, "", shelf)
    assert empty_phrase =~ "no phrase on it"

    assert {:refused, %{error: unread}} = HypnosisShelf.plan(:take_away, @p1, nil)
    assert unread =~ "has not been read yet"

    refused_shelf = HypnosisShelf.build(%{"ok" => false, "error" => "down"})

    assert {:refused, %{error: failed}} = HypnosisShelf.plan(:take_away, @p1, refused_shelf)
    assert failed =~ "could not be read"

    assert {:refused, %{error: foreign}} = HypnosisShelf.plan(:reword, @p1, shelf)
    assert foreign == "that is not one of the two things this screen does — nothing was sent"
  end

  # ── the write ───────────────────────────────────────────────────────────────

  test "a write that the bot refuses keeps the bot's own sentence" do
    stub(
      Jason.encode!(%{
        "ok" => false,
        "error" => "that phrase is not on her shelf",
        "code" => "not_found"
      })
    )

    assert {:error, "that phrase is not on her shelf"} =
             HypnosisShelf.write(%{"action" => "remove"})
  end

  test "a write that the bot refuses with no words is still a refusal" do
    stub(Jason.encode!(%{"ok" => false}))

    assert {:error, "the bot refused it without saying why"} = HypnosisShelf.write(%{})
  end

  test "an answer that is not a result is not rounded up to success" do
    stub(Jason.encode!(%{"ok" => true, "data" => "not a map"}))

    assert {:error, "the bot answered something that is not a result"} = HypnosisShelf.write(%{})
  end

  # A dead broker is not a refusal. Where the write never left the dashboard, nothing was
  # recorded, and the sentence says exactly that rather than borrowing the bot's voice.
  test "a broker that never carried the write says nothing was recorded" do
    stub({:error, :no_broker})

    assert {:error, sentence} = HypnosisShelf.write(%{})
    assert sentence == "no answer from the wife care bot — nothing was recorded"
  end

  test "a write that may have left and may not have says which of the two it does not know" do
    stub({:error, :timeout})

    assert {:error, sentence} = HypnosisShelf.write(%{})
    assert sentence =~ "whether anything was recorded is not known"
  end

  # `Broker` catches exits and does not rescue raises, and this screen adds no rescue:
  # a bug in here must stay a raised bug rather than becoming one more plausible "the bot
  # did not answer".
  test "an exit is a dead broker, and a raise is a raise" do
    stub({:exit, :noproc})
    assert {:error, sentence} = HypnosisShelf.write(%{})
    assert sentence =~ "whether anything was recorded is not known"

    stub({:raise, "the shelf write is buggy"})
    assert_raise RuntimeError, "the shelf write is buggy", fn -> HypnosisShelf.write(%{}) end
  end

  # ── the sentence after a tap ────────────────────────────────────────────────

  test "a switch off is confirmed by the phrase reading back off the air" do
    act = %{verb: :switch_off, id: @p1, text: "you are worth the trouble"}
    read = built(phrases: [phrase(id: @p1, on: false)])

    settled = HypnosisShelf.settle(act, read)

    assert settled.confirmed? == true

    assert HypnosisShelf.line(settled) =~
             "the shelf reads back you are worth the trouble, and it is out of the air"

    # And it never claims she asked for it.
    refute HypnosisShelf.line(settled) =~ "she asked"
  end

  # The write returned ok, and the shelf did not change: the confirmation is the read,
  # not the acknowledgement.
  test "a switch off the shelf did not take says what the shelf still holds" do
    act = %{verb: :switch_off, id: @p1, text: "you are worth the trouble"}
    read = built(phrases: [phrase(id: @p1, on: true)])

    settled = HypnosisShelf.settle(act, read)

    assert settled.confirmed? == false
    assert settled.reading == "you are worth the trouble, still in the air"
    assert HypnosisShelf.line(settled) =~ "sent — the shelf reads back"
    refute HypnosisShelf.line(settled) =~ "out of the air"
  end

  test "a take away is confirmed by the phrase answering on the away list" do
    act = %{verb: :take_away, id: @p3, text: "you are a good girl"}
    read = built(put_away: [phrase(id: @p3, on: false)])

    settled = HypnosisShelf.settle(act, read)

    assert settled.confirmed? == true
    assert HypnosisShelf.line(settled) =~ "taken away — the record of it survives"
  end

  test "a phrase that vanished was not taken away, and the sentence says so" do
    act = %{verb: :take_away, id: @p3, text: "you are a good girl"}

    settled = HypnosisShelf.settle(act, built())

    assert settled.confirmed? == false
    assert settled.reading == "no phrase this screen can name"
  end

  test "a refused tap keeps its own sentence through the read" do
    act = %{
      verb: :switch_off,
      id: @p1,
      error: "that phrase is not on this shelf — nothing was sent"
    }

    settled = HypnosisShelf.settle(act, built(phrases: [phrase(id: @p1, on: false)]))

    assert settled == act
    assert HypnosisShelf.class(settled) == "unreported"
  end

  test "settling before a read, or with no act at all, changes nothing" do
    assert HypnosisShelf.settle(nil, built()) == nil

    act = %{verb: :switch_off, id: @p1, text: "you are worth the trouble"}
    assert HypnosisShelf.settle(act, nil).confirmed? == false
  end

  test "the sentence before the reading lands is the sent sentence, and it claims no state" do
    act = %{verb: :switch_off, id: @p1, text: "you are worth the trouble"}

    line = HypnosisShelf.line(act)

    assert line == "sent you are worth the trouble — reading the shelf back…"
    refute line =~ "off"
    assert HypnosisShelf.class(act) == "dim"
  end

  test "an error line is not styled like a reading" do
    assert HypnosisShelf.class(%{error: "nothing was sent"}) == "unreported"
    assert HypnosisShelf.class(%{confirmed?: true}) == "dim"
  end

  # ── the cadence, and what has been said ─────────────────────────────────────

  test "a phrase on a cadence is counted, and a phrase off the air is not" do
    shelf =
      built(
        phrases: [
          phrase(id: @p1, repeat: "daily"),
          phrase(id: @p2, repeat: "twice_daily"),
          # A cadence on a phrase that is off the air is not one the house reads from, so
          # it is not counted as one the house says of its own accord.
          phrase(id: @p3, on: false, repeat: "daily")
        ]
      )

    assert shelf.counts == %{on: 2, off: 1, away: 0, reworded: 0, cadenced: 2}
    assert HypnosisShelf.counts_line(shelf) =~ "2 the house says on its own"
  end

  test "the cadence is spoken in the bot's own label, and never restated" do
    assert HypnosisShelf.cadence_line(row(repeat: "daily", repeat_label: "Once a day")) ==
             "Once a day"

    # A key with no label beside it is shown as the key it is: decoding it here would put
    # this screen's words where the bot sent none.
    assert HypnosisShelf.cadence_line(row(repeat: "daily")) ==
             "sent as daily, without the bot's words for it"

    assert HypnosisShelf.cadence_line(row([])) ==
             "the bot did not say whether this one repeats"
  end

  test "a missing count is unstated, and a zero count is a count" do
    assert HypnosisShelf.heard_line(row(said_count: 0)) == "never said yet"
    assert HypnosisShelf.heard_line(row(said_count: 1)) == "said once"
    assert HypnosisShelf.heard_line(row(said_count: 7)) == "said 7 times"

    # This helper sends no `said_count` at all: absent is not a zero, and is not drawn as
    # one either.
    refute HypnosisShelf.heard_line(row([])) =~ "said"
    refute HypnosisShelf.heard_line(row([])) =~ "never"
  end

  test "a due phrase that is off the air is not drawn as due" do
    assert HypnosisShelf.heard_line(row(due?: true)) =~ "due now"

    line = HypnosisShelf.heard_line(row(due?: true, on: false))

    assert line =~ "off the air"
    refute line =~ "due now"
  end

  test "the last time is rendered as felt time, never as a timestamp" do
    line =
      HypnosisShelf.heard_line(row(last_said_at: DateTime.utc_now() |> DateTime.to_iso8601()))

    assert line =~ "the last time was now"
    refute line =~ "T"
  end

  test "a phrase's line is its cadence and its history, and an unread one says neither" do
    line =
      HypnosisShelf.delivery_line(
        row(
          said_count: 3,
          last_said_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          repeat_label: "Once a day",
          due?: false
        )
      )

    assert line =~ "Once a day"
    assert line =~ "said 3 times"
    assert line =~ "not due yet"

    # A row the bot sent no delivery facts for — an earlier wording, a taken-away phrase —
    # still has its cadence said, because that much is about the row rather than the house.
    away = row(repeat_label: "Once a day", on: false)
    assert HypnosisShelf.delivery_line(away) == "Once a day"
  end

  test "how the house reads is the read's numbers, never this screen's" do
    shelf =
      built(
        block: %{
          "delivery" => %{
            "cadence_minutes" => %{"daily" => 1200, "twice_daily" => 600},
            "tick_minutes" => 10,
            "one_per_tick" => true
          }
        }
      )

    line = HypnosisShelf.tick_line(shelf)

    assert line =~ "the house looks every 10 minutes"
    assert line =~ "at most one phrase per look"
    assert line =~ "once a day means not again for 20 hours"
    assert line =~ "twice a day means not again for 10 hours"
    # The one place the interval numbers live is `HypnosisDelivery.floor_minutes/1`; a
    # restatement here would be a second copy of the rule, and one of the two would drift.
    refute line =~ "24"
  end

  test "a read that carried no delivery numbers claims none" do
    shelf = built(phrases: [phrase([])])

    assert shelf.delivery == nil
    assert HypnosisShelf.tick_line(shelf) == ""
  end

  test "a delivery block with nothing usable in it is unstated, not a default cadence" do
    shelf =
      built(
        block: %{"delivery" => %{"tick_minutes" => "ten", "cadence_minutes" => %{"daily" => 0}}}
      )

    assert shelf.delivery == %{cadence_minutes: nil, tick_minutes: nil, one_per_tick: nil}
    assert HypnosisShelf.tick_line(shelf) == ""
  end

  test "a cadence that is not a whole number of hours is said in minutes" do
    shelf =
      built(
        block: %{
          "delivery" => %{
            "cadence_minutes" => %{"daily" => 90},
            "tick_minutes" => 5,
            "one_per_tick" => false
          }
        }
      )

    line = HypnosisShelf.tick_line(shelf)

    assert line =~ "once a day means not again for 90 minutes"
    # `one_per_tick: false` is not rendered as "at most one per look": that sentence would
    # be a claim the read did not make.
    refute line =~ "at most one"
  end

  # ── the saying ──────────────────────────────────────────────────────────────

  test "a saying is named off the shelf, because the event has no words in it" do
    shelf = built(phrases: [phrase(id: @p1, text: "you are worth the trouble")])

    event = %{
      "event" => "wife_care.hypnosis.said",
      "payload" => %{"phrase_id" => @p1, "source" => "tick", "said_at" => "2026-09-26T12:00:00Z"}
    }

    assert HypnosisShelf.said_line(shelf, event) ==
             "the house just said you are worth the trouble of its own accord, on the tick."
  end

  test "a saying by hand names the role the voice was, never a pronoun" do
    shelf = built(phrases: [phrase(id: @p1, text: "the house notices")])

    for {by, role} <- [
          {"subject", "the maid"},
          {"louiza", "her voice"},
          {"operator", "the operator"}
        ] do
      event = %{"payload" => %{"phrase_id" => @p1, "source" => "hand", "by" => by}}

      assert HypnosisShelf.said_line(shelf, event) =~ " by hand, as #{role}"
    end
  end

  test "a saying this screen cannot name is said to be exactly that" do
    shelf = built(phrases: [phrase(id: @p1)])

    unmatched = %{"payload" => %{"phrase_id" => @p2, "source" => "tick"}}
    assert HypnosisShelf.said_line(shelf, unmatched) =~ "cannot name off the shelf"

    # No shelf read yet: nothing can be named from a shelf this screen has not read.
    assert HypnosisShelf.said_line(nil, unmatched) =~ "cannot name off the shelf"

    unnamed = %{"payload" => %{"source" => "tick"}}
    assert HypnosisShelf.said_line(shelf, unnamed) =~ "does not say which phrase"

    assert HypnosisShelf.said_line(shelf, "not an event") =~ "cannot read"
  end

  test "a saying is not a count: the read that follows it is what the shelf reports" do
    stub(Jason.encode!(shelf_reply(phrases: [phrase(id: @p1, said_count: 4)])))

    shelf = built(phrases: [phrase(id: @p1, text: "you are worth the trouble")])
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, shelf: shelf, act: nil}}
    event = %{"payload" => %{"phrase_id" => @p1, "source" => "tick"}}

    after_saying = HypnosisShelf.said(socket, event)

    assert after_saying.assigns.said =~ "the house just said you are worth the trouble"

    # `said/2` asks for the read; the answer arrives later as a message, exactly as it does
    # on the screen, and the count under the phrase is that read's 4 — not the saying plus
    # three, which is the arithmetic this screen has no business doing.
    assert_receive {:read_started, :hypnosis}
    assert_receive {:hypnosis, answer}

    assert Enum.map(
             HypnosisShelf.info(after_saying, answer).assigns.shelf.phrases,
             & &1.said_count
           ) ==
             [4]
  end
end
