defmodule BotArmyDashboardLiveview.ReflectionWindow do
  @moduledoc """
  The reflection lane, read from the bot that already keeps it.

  `bot_army_companion` has held reflections since before this screen: a row of
  her words (`text`), the prompt she answered, and the companion's answer to it
  (`answer.state` / `answer.text`). Every one of the three questions below is a
  question the bot already answers:

    * `companion.reflections.capture` — one reflection, written
    * `companion.reflections.list` — the most recent reflections, newest first
    * `companion.reflections.read` — one reflection by id

  The reflect screens used to *publish* a capture event and print
  "✓ Reflection captured" on the broker's `:ok`. That `:ok` only means the bytes
  reached the broker: it is not news about the store. This module is the reading
  the screens should have asked for, so a screen can stop claiming success it
  cannot know about — the same reason the bot's own `Reflections` module exposes
  the request path.

  ## Three answers, not two

  A list read has two outcomes and the screens have paid for the difference
  (N+25): the bot answered with the store's rows (`{:recent, rows}` — an empty
  list is a reading: the store looked and nothing is there), or the bot refused
  the question (`{:refused, sentence}`). A refusal is not an empty store, and the
  screen must not draw "nothing written yet" for it. A read that never came back
  at all is a third outcome, and it is `BotRead`'s: the `{:read_failed, …}`
  message that `ReadHooks` turns into the "can't reach the bot" panel.

  ## The answer is owed, and the screen may say so

  An answer is a job: the companion submits to the local uncensored model and the
  row goes `pending` → `answered`. `pending` is a *fourth* state, not a
  synonym for "no answer": she was read and the answer has not arrived. The
  screens say that in words, and they wait for it (see the cadence below) rather
  than rendering silence as a blank card. `unasked` is the bot's own word that
  the answer side is switched off — a fact, not a failure.

  ## Waiting: the bell is an accelerator, the poll is the guarantee

  The llm bot rings `events.llm.job.completed` when a job ends, and this screen
  re-reads on it (the bridge routes it to `dashboard:reflections`). A bell can be
  lost, and the companion itself treats it that way — its own fallback is a
  ten-second cadence, chosen so a lost bell is cheap. The phone does the same, and
  stops as soon as nothing is owed. The bell carries the job, never the words:
  the answer is always read by id from the bot that holds it.

  ## The words are hers

  Nothing here invents a reflection, retries a write, or rewrites one. A write
  either returned the stored row or it refused; a refusal is rendered as a
  refusal, and the screen never says "saved" for it.
  """

  # The three questions the bot answers. Named once, here.
  @capture_subject "companion.reflections.capture"
  @list_subject "companion.reflections.list"
  @read_subject "companion.reflections.read"

  # The store's own ceiling on a reflection, read from `Reflection.@max_text`.
  # The screen refuses a longer draft itself, with the ceiling in the refusal,
  # rather than sending it to be rejected.
  @max_text 4_000

  # How many rows the "earlier" list asks for. Small on purpose: this is a phone
  # in a foggy moment, not an archive.
  @recent_limit 5

  # How often a screen re-reads while an answer is owed. The companion's own
  # fallback is the same ten seconds (see `ReflectionAnswer.@defaults`): a lost
  # bell costs a tenth of a second of load and nothing else.
  @poll_ms 10_000

  # How long a screen keeps waiting for an owed answer before it stops re-reading.
  # The llm bot holds a finished job for an hour and the companion's own budget is
  # the same hour, so a screen that gave up sooner would be the screen's deadline,
  # not the lane's.
  @pending_budget_ms 3_600_000

  # The states the store puts on an answer.
  @answered "answered"
  @pending "pending"
  @unasked "unasked"
  @failed "failed"

  @doc "The subject a reflection is written on."
  def capture_subject, do: @capture_subject

  @doc "The subject the recent reflections are read on."
  def list_subject, do: @list_subject

  @doc "The subject one reflection is read on."
  def read_subject, do: @read_subject

  @doc "The longest reflection this screen will send."
  def max_text, do: @max_text

  @doc "How many rows the recent list asks for by default."
  def recent_limit, do: @recent_limit

  @doc "How often to re-read while an answer is owed."
  def poll_ms, do: @poll_ms

  @doc "How long an owed answer is worth waiting for."
  def pending_budget_ms, do: @pending_budget_ms

  @doc """
  A fresh key for one draft.

  Minted here, by the screen, because the screen is what knows when a draft
  begins — the store only knows what arrives. The rule the key encodes: the words
  on the card are one reflection, so every send from that card carries the same
  key, and a second send (a double tap, a touchscreen repeating itself, a press
  after a reply that never came back) is the *same* draft rather than a second
  one.

  A new key is minted only once the store says it has the words — never on a
  refusal, and never on a send. That is what makes a press-while-in-flight
  harmless: the second send cannot look like a new reflection, so it cannot
  become a second row or ask for a second answer.
  """
  @spec new_dedupe_key() :: String.t()
  def new_dedupe_key do
    "draft-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  @doc """
  The body of a capture: her words, the prompt she answered, and this draft's key.

  `captured_at` is deliberately not sent. It is the publisher's claim about the
  clock it saw, and the store already keeps its own `stored_at`; a screen that
  invents one is a screen telling the store what time it is.

  `dedupe_key` **is** sent, and it is the one field here that is about the
  sending rather than about her. The companion stores it as metadata: a missing or
  malformed key costs the caller its key and never her words. So a key that is
  blank or not text is left out of the body entirely rather than sent as a null —
  the body says what it means.
  """
  def capture_payload(text, prompt, dedupe_key) when is_binary(text) do
    %{"text" => text}
    |> put_prompt(prompt)
    |> put_key(dedupe_key)
  end

  defp put_prompt(payload, prompt) when is_binary(prompt) and prompt != "",
    do: Map.put(payload, "prompt", prompt)

  defp put_prompt(payload, _prompt), do: payload

  defp put_key(payload, key) when is_binary(key) and key != "",
    do: Map.put(payload, "dedupe_key", key)

  defp put_key(payload, _key), do: payload

  @doc "The body of the recent list."
  def list_payload(limit \\ @recent_limit), do: %{"limit" => limit}

  @doc "The body of a read by id."
  def read_payload(id) when is_binary(id), do: %{"id" => id}

  @doc """
  Whether a draft may be sent, and the refusal when it may not.

  An empty box is refused here rather than sent to hear the store say the same
  thing — the store's refusal is right, and a phone that can say it without a
  round trip should.
  """
  @spec draft(String.t()) :: {:ok, String.t()} | {:refused, String.t()}
  def draft(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:refused, "There is nothing to save — an empty page is not a reflection."}

      String.length(trimmed) > @max_text ->
        {:refused, "A reflection may hold at most #{@max_text} characters."}

      true ->
        {:ok, trimmed}
    end
  end

  def draft(_text), do: {:refused, "There is nothing to save."}

  # ── the capture ─────────────────────────────────────────────────────────────

  @doc """
  What a capture came back as.

  `{:stored, row}` carries the row the store wrote — the reply's own view, not
  the words this screen sent. The difference matters: the screen draws the stored
  row back, so what it shows is what the store holds.

  A send the store recognised as a duplicate reads as `{:stored, row}` too, and
  that is deliberate. The store does hold her words, which is the only thing this
  outcome is asked to mean, and a screen that reported "you pressed that twice"
  would be charging her for her own phone's mistake. Nothing was lost either way,
  and the duplicate is written down where the lane can count it.
  """
  @spec capture(term()) :: {:stored, map()} | {:refused, String.t()}
  def capture(%{"reflection" => row}) when is_map(row), do: {:stored, view(row)}

  def capture(%{"ok" => false} = answer), do: {:refused, refusal(answer)}

  def capture(_answer),
    do:
      {:refused,
       "The bot answered, but not with the reflection it was asked to keep — nothing here is a reading of it."}

  # ── the recent list ─────────────────────────────────────────────────────────

  @doc """
  What the recent list came back as.

  `{:recent, rows}` is the store's answer; `[]` is a reading (nothing written
  yet). Anything else — a refusal, or a shape this screen cannot read — is a
  refusal, never an empty list.
  """
  @spec recent(term()) :: {:recent, [map()]} | {:refused, String.t()}
  def recent(%{"ok" => false} = answer), do: {:refused, refusal(answer)}

  def recent(answer) do
    case rows(answer) do
      {:ok, rows} ->
        {:recent, Enum.map(rows, &view/1)}

      :error ->
        {:refused,
         "The bot answered, but not with a list of reflections — nothing here is a reading of the store."}
    end
  end

  @doc """
  What a read by id came back as.

  `{:reflection, row}` is the row; a refusal names the store's own word (a row
  that does not exist is `:not_found`, which is a reading and not an error).
  """
  @spec one(term()) :: {:reflection, map()} | {:refused, String.t()}
  def one(%{"reflection" => row}) when is_map(row), do: {:reflection, view(row)}

  def one(%{"ok" => false} = answer), do: {:refused, refusal(answer)}

  def one(_answer),
    do:
      {:refused,
       "The bot answered, but not with the reflection — nothing here is a reading of it."}

  # The store's rows, in either shape it can arrive in: `BotRead` unwraps a
  # `{"data": …}` envelope when `data` is the only non-envelope key, and the list
  # reply carries `count` inside that payload, so both shapes are reachable.
  defp rows(%{"reflections" => rows}) when is_list(rows), do: {:ok, rows}
  defp rows(%{"data" => %{"reflections" => rows}}) when is_list(rows), do: {:ok, rows}
  defp rows(_answer), do: :error

  # ── what a screen may say ───────────────────────────────────────────────────

  @doc """
  One reflection, as a screen may say it.

  A field the bot did not send is `nil` — never an empty string, and never a
  zero. `chars` is the store's count of the words it holds.
  """
  @spec view(map()) :: map()
  def view(row) when is_map(row) do
    %{
      id: row["id"],
      text: binary_or_nil(row["text"]),
      prompt: binary_or_nil(row["prompt"]),
      chars: row["chars"],
      stored_at: binary_or_nil(row["stored_at"]),
      answer: answer(row["answer"])
    }
  end

  @doc """
  What the store says about the answer to a reflection.

  The store sends an answer object whether or not an answer exists, so this is a
  reading of one field, not a second question:

    * `{:answered, text}` — the store holds the words
    * `{:pending, nil}` — she was read and the answer has not arrived. The screen
      says so; it does not fill the silence
    * `{:unasked, nil}` — the bot's own word that the answer side is switched off
    * `{:failed, sentence}` — the lane tried and could not; the store's own error
      where it has one
    * `{:unreported, sentence}` — the field is absent or shaped like none of
      these. A store that never sent the field is not a store that says "no
      answer is owed": `nil` is a question that did not come back.
  """
  @spec answer(term()) ::
          {:answered, String.t()}
          | {:pending, nil}
          | {:unasked, nil}
          | {:failed, String.t()}
          | {:unreported, String.t()}
  # A blank string is not words: the answered and failed states both read the value
  # through `text_or_nil/1` so neither can draw a blank line.
  def answer(%{"state" => @answered} = answer) do
    case text_or_nil(answer["text"]) do
      text when is_binary(text) -> {:answered, text}
      _ -> {:failed, "The store says this one was answered, but it did not send the words."}
    end
  end

  def answer(%{"state" => @pending}), do: {:pending, nil}
  def answer(%{"state" => @unasked}), do: {:unasked, nil}

  def answer(%{"state" => @failed} = answer) do
    case text_or_nil(answer["error"]) do
      error when is_binary(error) -> {:failed, error}
      _ -> {:failed, "The answer lane tried and did not come back with anything."}
    end
  end

  def answer(%{"state" => _other}),
    do:
      {:unreported,
       "The store named an answer state this screen does not know — it is not a reading."}

  def answer(nil),
    do:
      {:unreported,
       "The store did not say whether an answer exists, so this screen is not saying either."}

  def answer(_answer),
    do: {:unreported, "The store answered, but not with a reading of the answer."}

  @doc """
  The line under a reflection for whatever the store said about its answer.

  Never a blank: a blank card under "answered" would be a claim that the words
  are nothing.
  """
  @spec answer_line(term()) :: String.t()
  def answer_line({:answered, text}), do: text
  def answer_line({:pending, nil}), do: "Eir is reading it — the answer is not here yet."
  def answer_line({:unasked, nil}), do: "Eir is not answering right now. Your words are kept."

  def answer_line({:failed, sentence}),
    do: "Eir could not answer this one. Your words are kept — " <> sentence

  def answer_line({:unreported, sentence}), do: sentence
  def answer_line(_answer), do: "The store did not say whether an answer exists."

  @doc """
  Is an answer still owed on this reflection?

  The one thing a screen waits for. `:unasked` and `:failed` are terminal — no
  amount of waiting changes them.
  """
  @spec awaits_answer?(term()) :: boolean()
  def awaits_answer?(%{answer: {:pending, nil}}), do: true
  def awaits_answer?({:pending, nil}), do: true
  def awaits_answer?(_other), do: false

  @doc """
  Does any of these reflections still owe an answer?
  """
  @spec awaiting_any?([map()]) :: boolean()
  def awaiting_any?(rows) when is_list(rows), do: Enum.any?(rows, &awaits_answer?/1)
  def awaiting_any?(_rows), do: false

  @doc """
  The one reading of a refusal, for a screen's own failure line.

  The store's refusals arrive as sentences already (`Reflections.explain/1`), so
  they are carried, not translated.
  """
  @spec refusal(term()) :: String.t()
  def refusal(%{"error" => error}) when is_binary(error) and error != "",
    do: "Nothing came of it — the store said: #{error}"

  def refusal(_answer), do: "Nothing came of it — the store refused without saying why."

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_value), do: nil

  # An answer's words are either words or they are not there. `""` is not words: a
  # blank line drawn under "answered" is a claim that the answer is nothing.
  defp text_or_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp text_or_nil(_value), do: nil
end
