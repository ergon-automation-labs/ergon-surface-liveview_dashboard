defmodule BotArmyDashboardLiveview.ReflectionWindowTest do
  @moduledoc """
  The reflection reader: what the companion's answers mean, and what this screen may
  say about them.

  The stub replies here are shaped like the replies the bot actually sends —
  `reply.ok/1` wraps the payload under `"data"`, which `BotRead` unwraps, so a list
  arrives as `%{"reflections" => [...], "count" => n}` and a write/read as
  `%{"reflection" => row}` — and like its refusals, `%{"ok" => false, "error" => …}`.

  Three things only the answers can show, and the first two are the ones this
  dashboard has already paid for once. A refusal is not an empty store: the store
  failing to answer must not render as "nothing written yet". A missing answer field
  is not "no answer is owed": an absent field is a question that did not come back.
  And a write is only a write if the reply carried the row — anything else is a
  refusal, never a success the screen cannot know about.
  """

  use ExUnit.Case, async: false

  @moduletag :core

  alias BotArmyDashboardLiveview.ReflectionWindow, as: W

  @row %{
    "id" => "8f1a0f2e-1111-4000-8000-000000000001",
    "text" => "the moon was loud tonight",
    "prompt" => "What did the night say?",
    "chars" => 24,
    "stored_at" => "2026-10-03T21:00:00Z"
  }

  defp answered_row(overrides \\ %{}) do
    @row
    |> Map.merge(%{"answer" => %{"state" => "answered", "text" => "It said: keep going."}})
    |> Map.merge(overrides)
  end

  defp pending_row(overrides \\ %{}) do
    @row
    |> Map.merge(%{"answer" => %{"state" => "pending"}})
    |> Map.merge(overrides)
  end

  # ── the subjects ────────────────────────────────────────────────────────────

  # A subject name is not a specification, so the three are pinned here against the
  # ones the companion's consumer actually serves.
  test "the three questions this screen asks are the three the bot serves" do
    assert W.capture_subject() == "companion.reflections.capture"
    assert W.list_subject() == "companion.reflections.list"
    assert W.read_subject() == "companion.reflections.read"
  end

  test "the payloads are the shapes the bot reads" do
    assert W.capture_payload("her line", "the prompt") == %{
             "text" => "her line",
             "prompt" => "the prompt"
           }

    assert W.capture_payload("her line", nil) == %{"text" => "her line"}
    assert W.capture_payload("her line", "") == %{"text" => "her line"}
    assert W.list_payload() == %{"limit" => W.recent_limit()}
    assert W.list_payload(2) == %{"limit" => 2}
    assert W.read_payload("abc") == %{"id" => "abc"}
  end

  # `captured_at` is the publisher's claim about the clock, and the store keeps its
  # own `stored_at`. A screen that invents one is telling the store what time it is.
  test "the capture carries no clock claim of its own" do
    refute Map.has_key?(W.capture_payload("her line", "the prompt"), "captured_at")
  end

  test "the waiting cadence is the companion's own ten seconds, inside its own hour" do
    assert W.poll_ms() == 10_000
    assert W.pending_budget_ms() == 3_600_000
  end

  # ── what a draft may be ─────────────────────────────────────────────────────

  test "an empty page is refused here rather than sent to hear the store say it" do
    assert {:refused, sentence} = W.draft("")
    assert sentence =~ "nothing to save"

    assert {:refused, _} = W.draft("   \n  ")
    assert {:refused, _} = W.draft(nil)
  end

  test "a draft past the store's ceiling is refused with the ceiling in the words" do
    assert {:refused, sentence} = W.draft(String.duplicate("a", W.max_text() + 1))
    assert sentence =~ "#{W.max_text()}"
  end

  test "a draft at the ceiling is fine, and comes back trimmed" do
    assert {:ok, text} = W.draft("  a line at the edge  ")
    assert text == "a line at the edge"

    assert {:ok, _} = W.draft(String.duplicate("a", W.max_text()))
  end

  # ── the write ───────────────────────────────────────────────────────────────

  test "a write is what the store wrote, read back off the reply" do
    assert {:stored, row} = W.capture(%{"reflection" => pending_row()})
    assert row.id == @row["id"]
    assert row.text == "the moon was loud tonight"
    assert row.chars == 24
    assert row.answer == {:pending, nil}
  end

  test "a write the store refused is a refusal, not a write" do
    assert {:refused, sentence} =
             W.capture(%{
               "ok" => false,
               "code" => "unavailable",
               "error" => "the reflection store could not be reached"
             })

    assert sentence =~ "the reflection store could not be reached"
  end

  # The shape that would otherwise pass for success: an ok with no row in it. A
  # screen that drew "saved" here would be claiming a store it never heard from.
  test "an answer with no row in it is a refusal, never a stored reflection" do
    assert {:refused, sentence} = W.capture(%{"ok" => true, "data" => %{}})
    assert sentence =~ "not with the reflection"

    assert {:refused, _} = W.capture("{}")
    assert {:refused, _} = W.capture(nil)
    assert {:refused, _} = W.capture(%{"reflection" => "not a row"})
  end

  test "a refusal with no sentence still refuses" do
    assert {:refused, sentence} = W.capture(%{"ok" => false})
    assert sentence =~ "refused without saying why"
  end

  # ── the list ────────────────────────────────────────────────────────────────

  test "the list is the store's rows, newest first, as the store sent them" do
    assert {:recent, [first, second]} =
             W.recent(%{
               "reflections" => [answered_row(), pending_row(%{"id" => "second"})],
               "count" => 2
             })

    assert first.text == "the moon was loud tonight"
    assert first.answer == {:answered, "It said: keep going."}
    assert second.id == "second"
    assert second.answer == {:pending, nil}
  end

  # An empty list is a reading: the store looked, and nothing is there. This is the
  # one case where "nothing written yet" is true rather than a guess.
  test "an empty store is a reading, not a refusal" do
    assert W.recent(%{"reflections" => [], "count" => 0}) == {:recent, []}
  end

  test "a refusal to list is a refusal, never an empty store" do
    assert {:refused, sentence} =
             W.recent(%{
               "ok" => false,
               "code" => "unavailable",
               "error" => "the reflection store could not be reached"
             })

    assert sentence =~ "could not be reached"
    refute sentence =~ "nothing"
  end

  test "a list in a shape this screen cannot read is a refusal, never an empty store" do
    assert {:refused, sentence} = W.recent(%{"reflections" => "not a list"})
    assert sentence =~ "not with a list"
    refute W.recent(%{"reflections" => "not a list"}) == {:recent, []}

    assert {:refused, _} = W.recent(%{"ok" => true, "data" => %{}})
    assert {:refused, _} = W.recent(nil)
  end

  # `BotRead` unwraps a `{"data": …}` envelope when it is the only non-envelope key,
  # and the list reply carries `count` inside its payload, so a wrapped list is
  # reachable. Both shapes are read.
  test "the list reads whether or not the envelope was unwrapped" do
    assert {:recent, [row]} =
             W.recent(%{"data" => %{"reflections" => [pending_row()], "count" => 1}})

    assert row.text == "the moon was loud tonight"
  end

  # ── one by id ───────────────────────────────────────────────────────────────

  test "one reflection by id is the row the store holds" do
    assert {:reflection, row} = W.one(%{"reflection" => answered_row()})
    assert row.answer == {:answered, "It said: keep going."}
  end

  test "a read that does not come back with a reflection is a refusal" do
    assert {:refused, _} = W.one(%{"ok" => false, "error" => ":not_found"})
    assert {:refused, _} = W.one(%{"ok" => true, "data" => %{}})
    assert {:refused, _} = W.one(nil)
  end

  # ── the answer's own four states ────────────────────────────────────────────

  test "an answered reflection carries the store's words" do
    assert W.answer(%{"state" => "answered", "text" => "keep going"}) == {:answered, "keep going"}
  end

  test "a pending reflection is owed, and says so" do
    assert W.answer(%{"state" => "pending"}) == {:pending, nil}
    assert W.answer_line({:pending, nil}) == "Eir is reading it — the answer is not here yet."
    assert W.awaits_answer?(%{answer: {:pending, nil}})
  end

  test "unasked is the bot's own word that the answer side is off — and it is terminal" do
    assert W.answer(%{"state" => "unasked"}) == {:unasked, nil}
    assert W.answer_line({:unasked, nil}) =~ "not answering right now"
    refute W.awaits_answer?(%{answer: {:unasked, nil}})
  end

  test "a failed answer carries the lane's own error where there is one" do
    assert W.answer(%{"state" => "failed", "error" => "the model did not answer"}) ==
             {:failed, "the model did not answer"}

    assert {:failed, sentence} = W.answer(%{"state" => "failed"})
    assert sentence =~ "did not come back"
    refute W.awaits_answer?(%{answer: {:failed, sentence}})
  end

  # The one that matters most: an absent answer field is a question that did not
  # come back, not a store saying "no answer is owed". Silence is not a reading.
  test "an absent answer field is unreported, and never a blank answer" do
    assert {:unreported, sentence} = W.answer(nil)
    assert sentence =~ "did not say whether an answer exists"
    assert W.answer_line(W.answer(nil)) == sentence
    refute W.awaits_answer?(%{answer: W.answer(nil)})
  end

  test "an answer state this screen does not know is unreported, not answered" do
    assert {:unreported, _} = W.answer(%{"state" => "escalated"})
    assert {:unreported, _} = W.answer(%{"state" => %{}})
    assert {:unreported, _} = W.answer("answered")
  end

  # A blank line under "answered" is a claim that the words are nothing.
  test "an answered row with no words is a failure, and never a blank line" do
    assert {:failed, sentence} = W.answer(%{"state" => "answered"})
    assert sentence =~ "did not send the words"

    assert {:failed, _} = W.answer(%{"state" => "answered", "text" => ""})
  end

  test "no state draws a blank line" do
    for answer <- [
          {:answered, "words"},
          {:pending, nil},
          {:unasked, nil},
          {:failed, "sentence"},
          {:unreported, "sentence"},
          nil
        ] do
      line = W.answer_line(answer)
      assert is_binary(line)
      assert String.trim(line) != ""
    end
  end

  test "a reflection whose answer is not reported still renders its own row" do
    assert {:recent, [row]} = W.recent(%{"reflections" => [@row]})
    assert row.text == "the moon was loud tonight"
    assert row.answer == {:unreported, W.answer_line(row.answer)}
    assert W.answer_line(row.answer) != ""
  end

  # ── what a screen waits for ─────────────────────────────────────────────────

  test "a screen waits on a pending row and nothing else" do
    assert W.awaiting_any?([%{answer: {:pending, nil}}, %{answer: {:answered, "x"}}])
    refute W.awaiting_any?([%{answer: {:answered, "x"}}, %{answer: {:unasked, nil}}])
    refute W.awaiting_any?([])
    refute W.awaiting_any?(nil)
  end

  test "a field the bot never sent is nil, never an empty string and never a zero" do
    assert {:recent, [row]} = W.recent(%{"reflections" => [%{"id" => "r1"}]})
    assert row.text == nil
    assert row.prompt == nil
    assert row.chars == nil
    assert row.stored_at == nil
  end

  test "a view of a non-column field is nil rather than a shape the screen may draw" do
    assert {:recent, [row]} = W.recent(%{"reflections" => [%{"text" => %{"nested" => true}}]})
    assert row.text == nil
  end
end
