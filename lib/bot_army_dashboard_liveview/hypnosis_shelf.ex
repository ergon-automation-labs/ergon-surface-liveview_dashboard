defmodule BotArmyDashboardLiveview.HypnosisShelf do
  @moduledoc """
  Her shelf on the handheld: the phrases she has asked to hear, and the two
  reductions this screen is allowed to make.

  `wife_care.control_panel.hypnosis` has answered with the whole shelf for a while —
  the phrases that are in the air, the ones she took away, the earlier wording of the
  ones she reworded, the catalogue of seeds, and the house's promises — and
  `wife_care.control_panel.hypnosis_phrase` writes one verb at a time. Nothing drew
  it: the shelf had a floor and no door.

  ## Only two of the five verbs, and why

  The shelf's rule is asymmetric on purpose: **anyone may take a phrase out of the
  air; only she may put one in.** So this screen offers the two reductions:

    * **Switch off** — `{"action": "switch", "id": id, "state": "off"}`, which takes a
      phrase out of the air without taking it off the shelf.
    * **Take away** — `{"action": "remove", "id": id}`, which retires the row and keeps
      it, so what she heard survives and putting it back is exact.

  `add`, `reword` and `restore` all require `"actor": "subject"` — her voice — and this
  dashboard is open, so it proves nothing about who is holding the phone. A screen that
  claimed her would be forging the one voice it must not: the write would land under her
  name and look like something she asked for. So the card says which verbs it is not
  offering and why, and the writes it does make claim `"actor": "operator"` — a voice
  that may take a phrase out of the air and put nothing in.

  A phrase that is already off is drawn without a switch, because switching off what is
  already off is not a reduction, it is a no-op — and the card says the only way back is
  hers.

  ## The rules a tap obeys

    * **A failed read is a refusal, never an empty shelf**, and here that needs say-so
      twice. `BotRead` does not check `ok`, so `{"ok": false}` arrives looking exactly
      like a successful read of nothing, and an empty shelf would say she has asked to
      hear nothing. The bot answers a store failure the same way, as an `unavailable`
      block. "Nothing is on the shelf" and "the shelf could not be read" are different
      facts, and only one of them is this screen's to say.
    * **A row this screen cannot read refuses the whole shelf.** A list drawn from some
      of the rows is a list that quietly lost a phrase, and a phrase missing from a
      shelf looks exactly like one she never asked for.
    * **A write is never retried**, and every write is followed by a full re-read. The
      sentence afterwards reports the *read*: "the bot took it" and "the shelf reads
      back as" are different claims, and only the second one is this screen's to make.
    * **A tap this screen can route nowhere is refused here**, in its own words, and the
      one thing that sentence has to make unambiguous is that nothing was sent.
    * **A dead broker is not a refusal.** Where the write never left the dashboard,
      nothing was recorded; where it may have left, the sentence says that is not known
      rather than rounding it to either answer.
    * **Nothing is rescued.** `Broker` already turns an unreachable connection into an
      error, and a raised bug in this screen must stay a raised bug rather than becoming
      one more plausible "the bot did not answer".

  ## What the sentence after a tap may claim

  A confirmation is not "the write returned ok". It is "the shelf read the same phrase
  back with the state the verb was for": for a switch off, that phrase is now off the
  air; for a take away, it is on the shelf's away list. Anything less says what the
  shelf actually holds, which is the only thing this screen knows.

  ## What this screen says about a saying

  The bot now says a phrase of its own accord when its cadence comes due, and publishes
  `events.wife_care.hypnosis.said` — **ids and times only, never her words**. The bridge
  hands that to this screen on `dashboard:hypnosis`, and the screen names the saying off
  the shelf it has already read, then re-reads: the count and the last time under a phrase
  are the *read that followed*, not the event.

  A saying it cannot match against the shelf says exactly that. Naming a phrase off an
  event is the one thing the event deliberately does not carry, so this screen does not
  guess at it — and it does not add the saying to any count of its own either, for the
  same reason.
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.BotHealth
  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker

  @read_subject "wife_care.control_panel.hypnosis"
  @write_subject "wife_care.control_panel.hypnosis_phrase"

  # The second question this screen asks, and the only reason it asks anything else: a
  # phrase in the air is a moment, so the shelf is offered while there is a moment to
  # offer it in — a call from her that is still unanswered. The subject is the panel
  # state, which is where the house already keeps that fact and where the house screen
  # reads it, so the two screens cannot disagree about whether a call is open.
  @call_subject "wife_care.control_panel.state"
  @request_timeout 5_000

  # The voice this screen writes as. Not hers — see the module doc — and not the
  # house's either: the house's own assignment of a phrase is not a thing this screen
  # does. `Hypnosis` accepts exactly `subject`, `louiza`, `operator` and `system`, and
  # this is the one of those that claims nothing about what she asked to hear.
  @actor "operator"

  @verbs [:switch_off, :take_away]

  @doc "The subject the shelf is read on."
  def read_subject, do: @read_subject

  @doc """
  The subject the open-call question is asked on.
  """
  def call_subject, do: @call_subject

  @doc """
  Is a call open — or is that something the bot did not say?

  Three answers, because the answer to this question is what decides whether the shelf is
  drawn, and two of them are not the third:

    * `:open` — the house has called and she has not answered yet, so the shelf has a
      window to be offered in
    * `:none` — the bot reported today's calls and nothing is waiting
    * `:unreported` — the answer did not carry the fact at all. An answer that never
      mentioned calls is not a report of nothing waiting, and reading it as one would
      take a screen away on the strength of a question nobody asked.
  """
  @spec open_call(term()) :: :open | :none | :unreported
  def open_call(answer) when is_map(answer) do
    case get_in(answer, ["louiza", "demands", "pending"]) do
      [] -> :none
      pending when is_list(pending) -> :open
      _other -> :unreported
    end
  end

  def open_call(_answer), do: :unreported

  @doc "The subject a shelf verb is written on."
  def write_subject, do: @write_subject

  @doc "The voice this screen writes as — it may take a phrase out of the air and put nothing in."
  def actor, do: @actor

  # ── the seam a host page uses ───────────────────────────────────────────────

  @doc """
  Start the one read this screen needs, and open with nothing on record.

  The read is the shelf itself rather than the panel state: the phrases, the ones taken
  away and the earlier wording all come off this one reply, and the panel state does not
  carry them.
  """
  @spec start(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def start(socket) do
    BotRead.async(self(), :hypnosis, @read_subject, %{}, timeout: @request_timeout)
    assign(socket, shelf: nil, act: nil, said: nil)
  end

  @doc """
  Take the read, and reconcile it with any act that is waiting on it.

  This runs for the opening read and for the re-read after a write; they are the same
  read, and settling twice is idempotent.
  """
  @spec info(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  def info(socket, answer) do
    shelf = build(answer)
    assign(socket, shelf: shelf, act: settle(socket.assigns.act, shelf))
  end

  @doc """
  A saying the bridge heard about, and the re-read that follows it.

  The event carries ids and times only, so the phrase is named from the shelf this screen
  has already read — her words are not on that wire and must not be looked for there. The
  read that follows is what the counts under the card report; this sentence is not a count
  and adds nothing to one.
  """
  @spec said(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def said(socket, event),
    do: socket |> assign(said: said_line(socket.assigns[:shelf], event)) |> reread()

  @doc """
  One saying, as this screen can honestly name it.

  Named off the shelf it has read, never off the event: the event has no words in it. A
  saying this screen cannot match against the shelf says so rather than naming the nearest
  phrase, and an event it cannot read at all is called that rather than rounded to one of
  the other two.
  """
  @spec said_line(map() | nil, term()) :: String.t()
  def said_line(shelf, event) when is_map(event) do
    case phrase_id(event) do
      id when is_binary(id) and id != "" ->
        case named(shelf, id) do
          {:ok, text} ->
            "the house just said #{text}#{voice(Map.get(event, "payload"))}."

          :error ->
            "the house said a phrase this screen cannot name off the shelf it has read — the read below is the shelf's own answer."
        end

      _other ->
        "the house said something, and the event does not say which phrase it was — the read below is the shelf's own answer."
    end
  end

  def said_line(_shelf, _event), do: "the bridge passed on a saying this screen cannot read."

  defp phrase_id(%{"payload" => %{"phrase_id" => id}}), do: id
  defp phrase_id(_event), do: nil

  # How it came to be said, in the bot's own two sources. `tick` is the house's own
  # cadence; `hand` is someone asking for it, and the voice is named as the role it is —
  # the maid, her, or the keep-the-lights-on role — rather than as a pronoun.
  defp voice(%{"source" => "tick"}), do: " of its own accord, on the tick"
  defp voice(%{"source" => "hand", "by" => by}) when is_binary(by), do: " by hand, as #{role(by)}"
  defp voice(_payload), do: ""

  defp role("subject"), do: "the maid"
  defp role("louiza"), do: "her voice"
  defp role("operator"), do: "the operator"
  defp role(other), do: "a voice it calls #{other}"

  # The shelf this screen holds is where a phrase can be named from, and the phrases it is
  # drawing are the only ones it can name. A screen that has not read the shelf, or that
  # read a shelf this phrase is not on, names nothing.
  defp named(shelf, id) do
    case find_live(id, shelf) do
      {:ok, %{text: text}} -> {:ok, text}
      :error -> :error
    end
  end

  @doc """
  One tap, from the event to the sentence under the card.

  `verb` is `:switch_off` or `:take_away`, and `id` is the phrase the card drew. A tap
  this screen can route nowhere never reaches the bot; a sent write is always followed
  by a re-read, so the sentence reports the reading, not the acknowledgement.
  """
  @spec click(Phoenix.LiveView.Socket.t(), atom(), term()) :: Phoenix.LiveView.Socket.t()
  def click(socket, verb, id) do
    case plan(verb, id, socket.assigns[:shelf]) do
      {:refused, act} ->
        assign(socket, act: act)

      {:send, payload, act} ->
        case write(payload) do
          {:ok, _data} -> socket |> assign(act: act) |> reread()
          {:error, sentence} -> assign(socket, act: Map.put(act, :error, sentence))
        end
    end
  end

  defp reread(socket) do
    BotRead.async(self(), :hypnosis, @read_subject, %{}, timeout: @request_timeout)
    socket
  end

  # ── deciding what a tap means ───────────────────────────────────────────────

  @doc """
  Turn a tap into either a write or a refusal this screen owns.

  Returns `{:send, payload, act}` when the phrase is one the card is drawing and the
  verb applies to it, and `{:refused, act}` otherwise — a write this screen knows is
  wrong is not something to delegate to the bot.
  """
  @spec plan(atom(), term(), map() | nil) :: {:send, map(), map()} | {:refused, map()}
  def plan(verb, id, shelf) when verb in @verbs do
    case route(verb, id, shelf) do
      {:ok, row} -> {:send, payload(verb, id), act(verb, row)}
      {:refused, sentence} -> {:refused, %{verb: verb, id: id, error: sentence}}
    end
  end

  def plan(_verb, id, _shelf) do
    {:refused,
     %{
       verb: nil,
       id: id,
       error: "that is not one of the two things this screen does — nothing was sent"
     }}
  end

  # Four different facts, each with its own sentence rather than one shared shrug: a tap
  # with no phrase on it, a shelf that was never read, a shelf that could not be read,
  # and a phrase the card is not drawing. The id is checked first — a malformed tap is
  # not the same fact as a stale page.
  defp route(_verb, id, _shelf) when not is_binary(id) or id == "",
    do: {:refused, "that tap had no phrase on it — nothing was sent"}

  defp route(_verb, _id, nil),
    do: {:refused, "the shelf has not been read yet — nothing was sent"}

  defp route(_verb, _id, %{refused: refused}) when is_binary(refused) and refused != "",
    do: {:refused, "the shelf could not be read, so nothing was sent"}

  defp route(verb, id, shelf) do
    case find_live(id, shelf) do
      {:ok, row} ->
        if applies?(verb, row) do
          {:ok, row}
        else
          {:refused, "that phrase is already off the air — nothing was sent"}
        end

      :error ->
        {:refused,
         "that phrase is not on this shelf — reload the page and tap it again, nothing was sent"}
    end
  end

  # Switching off something already off is not a reduction. Taking a phrase away always
  # applies: anyone may, and the row it retires may be on or off.
  defp applies?(:switch_off, row), do: Map.get(row, :on) == true
  defp applies?(:take_away, _row), do: true

  defp payload(:switch_off, id) do
    %{"action" => "switch", "id" => id, "state" => "off", "actor" => @actor}
  end

  defp payload(:take_away, id), do: %{"action" => "remove", "id" => id, "actor" => @actor}

  @doc """
  Send one shelf verb. The body is the payload itself, plus the sentence the write line
  and the audit entry carry: which phrase, and what was done to it.

  There is nothing to check here that the bot does not check harder — the phrase either
  is on the shelf or the bot says it is not — and a second opinion about that is a second
  place for it to be wrong.
  """
  @spec write(map()) :: {:ok, map()} | {:error, String.t()}
  def write(payload) do
    case Broker.request(@write_subject, Jason.encode!(payload), timeout: @request_timeout) do
      {:ok, %{body: body}} -> decode_write(body)
      other -> {:error, write_trouble(other)}
    end
  end

  @doc """
  Reconcile an act with a fresh read.

  The same read answers twice, and settling is idempotent: an act already confirmed
  stays confirmed, and an act that never left keeps its own sentence rather than
  borrowing the reading's.
  """
  @spec settle(map() | nil, map() | nil) :: map() | nil
  def settle(nil, _shelf), do: nil

  # A write that never left has already been answered; a reading that lands after it is
  # news about the shelf, not about that write.
  def settle(%{error: _error} = act, _shelf), do: act

  def settle(%{id: id, verb: verb} = act, shelf) do
    if read_back?(verb, id, shelf) do
      Map.put(act, :confirmed?, true)
    else
      act |> Map.put(:confirmed?, false) |> Map.put(:reading, describe(id, shelf))
    end
  end

  def settle(act, _shelf), do: act

  # The phrase came back with the state the verb was for. A phrase that is gone from the
  # shelf is not a switch off, and a phrase that is not on the away list was not taken
  # away, whatever this screen sent.
  defp read_back?(:switch_off, id, shelf) do
    case find_live(id, shelf) do
      {:ok, row} -> Map.get(row, :on) == false
      :error -> false
    end
  end

  defp read_back?(:take_away, id, shelf) do
    case find_away(id, shelf) do
      {:ok, _row} -> true
      :error -> false
    end
  end

  @doc "The sentence under the card that owns this act."
  def line(%{error: error}), do: error

  def line(%{confirmed?: true, verb: :switch_off} = act),
    do:
      "the shelf reads back #{act.text}, and it is out of the air — only she can put it back in."

  def line(%{confirmed?: true, verb: :take_away} = act),
    do:
      "the shelf reads back #{act.text}, taken away — the record of it survives, and only her voice can put it back."

  def line(%{reading: reading}),
    do: "sent — the shelf reads back #{reading}; showing what the shelf says."

  def line(%{text: text}), do: "sent #{text} — reading the shelf back…"

  def line(_act), do: "sent — reading the shelf back…"

  @doc "An error line is not a reading; it must not be styled like one."
  def class(%{error: _}), do: "unreported"
  def class(_act), do: "dim"

  # ── the shelf, as this screen understands it ────────────────────────────────

  @doc """
  Build the card's view of one shelf reply.

  Returns `%{refused: nil, narration: ..., phrases: [...], put_away: [...], rewritten:
  [...], counts: %{...}, empty?: boolean}`, or — when the reply cannot be read as a shelf
  at all — `%{refused: sentence, narration: :unstated, phrases: [], put_away: [],
  rewritten: [], counts: ..., empty?: false}`. Never a refusal that also claims to be an
  empty shelf, and never an unstated narration read as permission.

  `counts` is derived from the rows this screen is drawing, not from the numbers on the
  wire: a count printed beside a list has to travel with that list, and the drawn rows
  are the only ones this card can answer for.
  """
  @spec build(term()) :: map()
  def build(%{"ok" => false} = answer) do
    case Map.get(answer, "error") do
      error when is_binary(error) and error != "" -> refused(error)
      _other -> refused("the bot refused the read without saying why")
    end
  end

  def build(%{"hypnosis" => %{"unavailable" => message}}) when is_binary(message) do
    refused("the shelf could not be read: #{message}")
  end

  def build(%{"hypnosis" => %{"unavailable" => _other}}) do
    refused("the shelf could not be read")
  end

  def build(%{"hypnosis" => block} = answer) when is_map(block) do
    with {:ok, phrases} <- rows(Map.get(block, "phrases")),
         {:ok, put_away} <- rows(Map.get(block, "put_away")),
         {:ok, rewritten} <- rows(Map.get(block, "rewritten")) do
      %{
        refused: nil,
        narration: narration(Map.get(answer, "narration_allowed")),
        phrases: phrases,
        put_away: put_away,
        rewritten: rewritten,
        counts: counts(phrases, put_away, rewritten),
        delivery: delivery(Map.get(block, "delivery")),
        empty?: phrases == []
      }
    else
      :error -> refused("the shelf answered with something this screen cannot read")
    end
  end

  def build(%{"hypnosis" => _other}) do
    refused("the bot answered with a shelf this screen cannot read")
  end

  def build(_answer), do: refused("the bot answered, but not with a shelf")

  defp refused(sentence) do
    %{
      refused: sentence,
      narration: :unstated,
      phrases: [],
      put_away: [],
      rewritten: [],
      counts: counts([], [], []),
      delivery: nil,
      empty?: false
    }
  end

  # Every row of every list, or none of them. A row is readable when it carries the
  # three things this card draws from under its own name: the id a tap sends back, the
  # words, and whether it is in the air.
  defp rows(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn row, {:ok, acc} ->
      case row_view(row) do
        {:ok, view} -> {:cont, {:ok, [view | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, views} -> {:ok, Enum.reverse(views)}
      :error -> :error
    end
  end

  defp rows(_other), do: :error

  defp row_view(row) when is_map(row) do
    with id when is_binary(id) and id != "" <- Map.get(row, "id"),
         text when is_binary(text) <- Map.get(row, "text"),
         on when is_boolean(on) <- Map.get(row, "on?") do
      {:ok,
       %{
         id: id,
         text: text,
         on: on,
         state_label: label(row, "state_label"),
         person_label: label(row, "person_label"),
         intent_label: label(row, "intent_label"),
         detail: label(row, "detail"),
         repeat: label(row, "repeat"),
         repeat_label: label(row, "repeat_label"),
         said_count: count_of(row),
         last_said_at: label(row, "last_said_at"),
         due?: boolean_of(row, "due?")
       }}
    else
      _other -> :error
    end
  end

  defp row_view(_row), do: :error

  # An optional string is the same as an absent one: it is not drawn. Anything that is
  # not a string is absent, rather than inspected into the page.
  defp label(row, key) when is_binary(key) do
    case Map.get(row, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  # A count is a count only when the bot sent one as a whole number. Zero is a count — "it
  # has never been said" — and a key that is not there is not a zero, so a phrase the bot
  # said nothing about is drawn as unstated rather than as never said.
  defp count_of(row) do
    case Map.get(row, "said_count") do
      count when is_integer(count) and count >= 0 -> count
      _other -> nil
    end
  end

  # The same rule for the one boolean the delivery facts carry: anything that is not a
  # boolean is unstated, never rounded to either answer.
  defp boolean_of(row, key) do
    case Map.get(row, key) do
      value when is_boolean(value) -> value
      _other -> nil
    end
  end

  # Three states, and the third is the fail-closed one: a `narration_allowed` that is not
  # a boolean is not rounded to permission. The one thing this screen must never say is
  # that the house may speak about her when the bot did not say so.
  defp narration(true), do: :allowed
  defp narration(false), do: :stopped
  defp narration(_other), do: :unstated

  defp counts(phrases, put_away, rewritten) do
    %{
      on: Enum.count(phrases, &Map.get(&1, :on)),
      off: Enum.count(phrases, &(Map.get(&1, :on) == false)),
      away: length(put_away),
      reworded: length(rewritten),
      cadenced: Enum.count(phrases, &cadenced?/1)
    }
  end

  # A phrase the house will say of its own accord is one that is in the air *and* on a
  # cadence the bot named. An off-air phrase is not one the tick reads from, whatever
  # cadence it still carries, so it is not counted here.
  defp cadenced?(%{on: true, repeat: repeat}) when is_binary(repeat), do: repeat != "off"
  defp cadenced?(_row), do: false

  # The delivery half of the read, read the way the lists are: the parts this screen can
  # name, and nothing invented for the parts it cannot. An absent block is unstated, never
  # a default cadence — the words above a number are the bot's to send, not this screen's to
  # supply.
  defp delivery(block) when is_map(block) do
    %{
      cadence_minutes: minutes(Map.get(block, "cadence_minutes")),
      tick_minutes: positive(Map.get(block, "tick_minutes")),
      one_per_tick: boolean_of(block, "one_per_tick")
    }
  end

  defp delivery(_other), do: nil

  defp minutes(map) when is_map(map) do
    map
    |> Enum.filter(fn {key, value} -> is_binary(key) and positive(value) != nil end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 -> nil
      minutes -> minutes
    end
  end

  defp minutes(_other), do: nil

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_other), do: nil

  defp find_live(id, shelf) when is_binary(id) do
    case Enum.find(Map.get(shelf || %{}, :phrases, []), &(Map.get(&1, :id) == id)) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  defp find_live(_id, _shelf), do: :error

  defp find_away(id, shelf) when is_binary(id) do
    case Enum.find(Map.get(shelf || %{}, :put_away, []), &(Map.get(&1, :id) == id)) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  defp find_away(_id, _shelf), do: :error

  defp act(verb, row), do: %{verb: verb, id: row.id, text: row.text}

  # What the shelf actually says about the phrase this act named. The three cases are
  # different news, and none of them is "it worked".
  defp describe(id, shelf) do
    case find_live(id, shelf) do
      {:ok, %{text: text, on: true}} -> "#{text}, still in the air"
      {:ok, %{text: text}} -> "#{text}, off the air but still on the shelf"
      :error -> describe_away(id, shelf)
    end
  end

  defp describe_away(id, shelf) do
    case find_away(id, shelf) do
      {:ok, %{text: text}} -> "#{text}, taken off the shelf"
      :error -> "no phrase this screen can name"
    end
  end

  # A refusal keeps the bot's own sentence: it names the phrase, or the state it is
  # already in, and none of that is improved by this screen paraphrasing it. A reply that
  # is not a result says so rather than being rounded up to success.
  defp decode_write(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => data}} when is_map(data) ->
        {:ok, data}

      {:ok, %{"ok" => true, "data" => _other}} ->
        {:error, "the bot answered something that is not a result"}

      {:ok, %{"ok" => true}} ->
        {:ok, %{}}

      {:ok, %{"ok" => false, "error" => error}} when is_binary(error) ->
        {:error, error}

      {:ok, %{"ok" => false}} ->
        {:error, "the bot refused it without saying why"}

      {:ok, _other} ->
        {:error, "the bot answered something that is not a result"}

      {:error, _reason} ->
        {:error, "the bot's answer could not be read"}
    end
  end

  # A dead broker is not a refusal and must not read like one.
  defp write_trouble({:error, :no_broker}) do
    Logger.debug("[HypnosisShelf] a write answered nothing: the broker is not reachable")
    "no answer from the wife care bot — nothing was recorded"
  end

  defp write_trouble(reason) do
    Logger.debug("[HypnosisShelf] a write answered nothing: #{inspect(reason)}")
    "no answer from the wife care bot — whether anything was recorded is not known"
  end

  # ── the vocabulary of the shelf, said once ──────────────────────────────────

  @doc "The verb in the words the button carries."
  def verb_word(:switch_off), do: "Switch off"
  def verb_word(:take_away), do: "Take away"

  @doc "Whether the phrase is in the air, in one word."
  def phrase_word(%{on: true}), do: "in the air"
  def phrase_word(%{on: false}), do: "off the air"
  def phrase_word(_row), do: "not recorded"

  @doc "The chip's class, so a phrase that is off cannot look like one that is spoken."
  def phrase_class(%{on: true}), do: "chip live"
  def phrase_class(%{on: false}), do: "chip off"
  def phrase_class(_row), do: "chip unstated"

  @doc "The state of the house's narration, in one word."
  def narration_word(:allowed), do: "may speak"
  def narration_word(:stopped), do: "may not speak"
  def narration_word(_narration), do: "not stated"

  @doc "What the bot said about the house speaking about her, in its own terms."
  def narration_sentence(:allowed), do: "no stop is in place — the house may speak about her."

  def narration_sentence(:stopped),
    do: "her stop is in place — the house may not speak about her."

  def narration_sentence(_narration),
    do:
      "the bot did not say whether the house may speak about her, so this screen reads it as: it may not."

  @doc "An unstated narration is not permission, and is not styled like a reading."
  def narration_class(:allowed), do: "dim"
  def narration_class(:stopped), do: "stop-note"
  def narration_class(_narration), do: "unreported"

  @doc """
  The counts, over the lists this card is drawing.

  `on` and `off` are the phrases in the air and out of it; `away` and `reworded` are the
  two history lists. A list the screen refused leaves these at zero rather than at the
  numbers the wire claimed.
  """
  def counts_line(%{counts: counts}) do
    "#{counts.on} in the air · #{counts.off} off the air · " <>
      "#{counts.cadenced} the house says on its own · " <>
      "#{counts.away} taken away · #{counts.reworded} with earlier wording"
  end

  def counts_line(_shelf), do: ""

  # ── the cadence, and what has actually been said ────────────────────────────

  @doc """
  How often the house looks, and how long each cadence waits — in the bot's own numbers.

  The numbers are the read's, not this screen's. "Not before twenty hours" restated here
  while the tick waited a different number of hours would be the same rule said twice, and
  one of the two would be wrong. A read that did not carry them says nothing rather than
  assuming a cadence.
  """
  def tick_line(%{delivery: %{tick_minutes: tick} = delivery}) when is_integer(tick) do
    look =
      if Map.get(delivery, :one_per_tick) == true do
        "the house looks every #{span(tick)} and says at most one phrase per look"
      else
        "the house looks every #{span(tick)}"
      end

    case floors(Map.get(delivery, :cadence_minutes)) do
      [] -> look <> "."
      floors -> look <> "; " <> Enum.join(floors, ", ") <> "."
    end
  end

  def tick_line(_shelf), do: ""

  defp floors(minutes) when is_map(minutes) do
    [{"daily", "once a day"}, {"twice_daily", "twice a day"}]
    |> Enum.map(fn {key, label} -> floor_phrase(label, Map.get(minutes, key)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp floors(_minutes), do: []

  defp floor_phrase(label, minutes) when is_integer(minutes) and minutes > 0,
    do: "#{label} means not again for #{span(minutes)}"

  defp floor_phrase(_label, _other), do: nil

  # A number off the wire, in the unit a person reads it in — and not rounded into one:
  # a floor that is not a whole number of hours is said in minutes.
  defp span(minutes) when rem(minutes, 60) == 0, do: unit(div(minutes, 60), "hour")
  defp span(minutes), do: unit(minutes, "minute")

  defp unit(1, word), do: "1 #{word}"
  defp unit(count, word), do: "#{count} #{word}s"

  @doc """
  One phrase's cadence and what has actually been said of it, as one line under the row.

  Each part is read on its own: a count of zero is a count and a missing count is not one;
  an instant is rendered as a person reads it rather than as a timestamp; and a cadence
  that says a phrase is due is not drawn as due when the phrase is off the air, because
  the house is not reading from a phrase it is not saying.
  """
  def delivery_line(row) when is_map(row) do
    case heard_line(row) do
      "" -> cadence_line(row)
      heard -> "#{cadence_line(row)} · #{heard}"
    end
  end

  def delivery_line(_row), do: ""

  @doc """
  What the house has said of this phrase: how many times, when it last did, and whether
  the cadence is due.

  Every part is optional and none of them is invented. A row the bot sent no delivery
  facts for — a phrase taken away, an earlier wording — has no line at all, because the
  question "is it due" has no meaning for a row the house is not reading from.
  """
  def heard_line(row) when is_map(row) do
    [count_phrase(row), last_phrase(row), due_phrase(row)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def heard_line(_row), do: ""

  defp count_phrase(%{said_count: 0}), do: "never said yet"
  defp count_phrase(%{said_count: 1}), do: "said once"
  defp count_phrase(%{said_count: count}) when is_integer(count), do: "said #{count} times"
  defp count_phrase(_row), do: nil

  defp last_phrase(%{last_said_at: last}) when is_binary(last),
    do: "the last time was #{ago(last)}"

  defp last_phrase(_row), do: nil

  defp due_phrase(%{due?: true, on: true}), do: "due now"

  defp due_phrase(%{due?: true, on: false}),
    do: "its cadence says due, but it is off the air, so the house is not reading from it"

  defp due_phrase(%{due?: false}), do: "not due yet"
  defp due_phrase(_row), do: nil

  # The same question `BotHealth` already answers for a heartbeat — an instant as a person
  # reads it — so the windows live in one place instead of being restated here and
  # drifting. Its nil clause is never reached: the caller checked the instant is a string.
  defp ago(instant), do: BotHealth.format_heartbeat(instant)

  @doc """
  The cadence a phrase is on, in the bot's own words.

  A key with no words beside it is not decoded here into a cadence of this screen's
  invention: the key is shown as the key it is. The labels are the bot's own table, and a
  screen that restated them would drift from the table the tick obeys.
  """
  def cadence_line(%{repeat_label: label}) when is_binary(label) and label != "", do: label

  def cadence_line(%{repeat: repeat}) when is_binary(repeat) and repeat != "",
    do: "sent as #{repeat}, without the bot's words for it"

  def cadence_line(_row), do: "the bot did not say whether this one repeats"

  # ── one card ────────────────────────────────────────────────────────────────

  @doc """
  The shelf card, with its own styles and its own result line.

  `shelf` is the built view of the shelf reply; while it is `nil` the card says the read
  has not landed rather than drawing an empty shelf. `read_error` is the failed read the
  hooks put on the socket: with it, the card says the shelf was not read at all, because
  "nothing is in the air" and "the shelf could not be read" are different facts. `said` is
  the saying the bridge just heard about, already named as far as this screen can name it.
  """
  attr(:shelf, :map, default: nil)
  attr(:act, :map, default: nil)
  attr(:read_error, :string, default: nil)
  attr(:said, :string, default: nil)
  # `HypnosisShelf.open_call/1`: the card draws no shelf while the bot has said, plainly,
  # that nothing is waiting. Every other answer — a call open, an answer that never
  # mentioned calls, a read still in flight — draws the shelf the screen actually read,
  # because those are not reports of a closed window.
  attr(:open_call, :atom, default: nil)

  def card(assigns) do
    ~H"""
    <style>
      .shelf-card { background: #131a3a; border: 1px solid #222c56; border-radius: 10px; padding: 14px 16px; margin: 0 auto 14px; max-width: 900px; }
      .shelf-card .card-title { font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #6f7db2; margin-bottom: 10px; }
      .shelf-card .row { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; }
      .shelf-card .dim { color: #8b93b0; }
      .shelf-card .unreported { color: #b98b3f; }
      .shelf-card .stop-note { color: #b98b3f; }
      .shelf-card .chip { display: inline-block; padding: 2px 8px; border-radius: 999px; border: 1px solid #2c3766; color: #a9b4e0; font-size: 12px; white-space: nowrap; }
      .shelf-card .chip.live { color: #0a0e27; background: #ffd166; border-color: #ffb545; font-weight: 600; }
      .shelf-card .chip.off { color: #b98b3f; border-color: #6b5a2f; }
      .shelf-card .chip.unstated { color: #b98b3f; border-color: #6b5a2f; }
      .shelf-card .chip.away { color: #ffd9a0; background: #241f36; border-color: #6b4d7a; }
      .shelf-card .chip.past { color: #6f7db2; }
      .phrase { border-top: 1px solid #1c2447; padding: 10px 0 4px; }
      .phrase-text { color: #dfe4ff; font-size: 15px; line-height: 1.4; }
      .phrase-meta { color: #6f7db2; font-size: 12px; margin: 4px 0 0; }
      .act-row { display: flex; gap: 8px; margin: 8px 0 4px; }
      .act-row button { flex: 1; min-height: 44px; font: inherit; font-size: 15px; color: #a9b4e0; background: #10162f; border: 1px solid #222c56; border-radius: 8px; cursor: pointer; }
      .act-row button.take { color: #ffd9a0; border-color: #4a3a5c; }
      .shelf-legend { color: #6f7db2; font-size: 12px; margin: 6px 0 4px; }
      .shelf-counts { color: #6f7db2; font-size: 12px; margin: 4px 0 10px; }
      .shelf-said { color: #ffd166; font-size: 13px; margin: 0 0 8px; }
      .shelf-section { font-size: 12px; letter-spacing: 1.2px; text-transform: uppercase; color: #6f7db2; margin: 16px 0 2px; }
    </style>

    <%= cond do %>
      <% @open_call == :none -> %>
        <div class="shelf-card">
          <div class="card-title">Her shelf</div>
          <p class="unreported">Nothing is waiting right now, so the shelf is not offered here. What she asked to hear is a moment rather than a place: it appears while a call is open — the house has called her and she has not answered yet.</p>
          <p class="dim" style="font-size:12px;">It comes back with the next call, and the page keeps reading the shelf underneath either way.</p>
        </div>
      <% @read_error -> %>
        <div class="shelf-card">
          <div class="card-title">Her shelf</div>
          <p class="unreported">The shelf was not read — anything drawn here would be this screen guessing at what she asked to hear, and that is not a thing to guess at.</p>
        </div>
      <% is_nil(@shelf) -> %>
        <div class="shelf-card">
          <div class="card-title">Her shelf</div>
          <p class="unreported">nothing from the shelf yet — the card appears when the read lands</p>
        </div>
      <% @shelf.refused -> %>
        <div class="shelf-card">
          <div class="card-title">Her shelf</div>
          <p class="unreported"><%= @shelf.refused %></p>
          <p class="dim" style="font-size:12px;">No phrases are drawn: a shelf put together from a read that failed would be this screen inventing what she asked to hear.</p>
        </div>
      <% true -> %>
        <div class="shelf-card">
          <div class="card-title">Her shelf — what she has asked to hear  ·  tap to take something out of the air</div>

          <%= if @said do %>
            <p class="shelf-said"><%= @said %></p>
          <% end %>

          <p class={narration_class(@shelf.narration)} style="margin:0 0 6px; font-size:12px;"><%= narration_word(@shelf.narration) %>: <%= narration_sentence(@shelf.narration) %></p>

          <p class="shelf-legend">
            <%= verb_word(:switch_off) %> takes a phrase out of the air, and <%= verb_word(:take_away) %> takes it off the shelf while keeping the record of it. Putting a phrase on the shelf, rewording one, and putting one back are hers: this screen is open to whoever is holding the phone, so it claims no voice of hers and offers none of those.
          </p>

          <p class="shelf-counts"><%= counts_line(@shelf) %></p>
          <%= if tick_line(@shelf) != "" do %>
            <p class="shelf-counts"><%= tick_line(@shelf) %></p>
          <% end %>

          <%= for phrase <- @shelf.phrases do %>
            <.phrase_row phrase={phrase} />
          <% end %>

          <%= if @shelf.empty? do %>
            <p class="dim empty-state">nothing is in the air — the shelf is empty. A phrase gets onto it in her own voice, which is not a voice this screen has.</p>
          <% end %>

          <%= if @shelf.put_away != [] do %>
            <div class="shelf-section">Taken away</div>
            <p class="dim" style="font-size:12px; margin:0 0 6px;">These were taken off the shelf, and only her voice can put one back — so there is no button here. A cadence on one of them is not in effect: the house only reads from phrases that are on the shelf.</p>
            <%= for phrase <- @shelf.put_away do %>
              <.history_row phrase={phrase} note="taken away" chip_class="chip away" />
            <% end %>
          <% end %>

          <%= if @shelf.rewritten != [] do %>
            <div class="shelf-section">The wording these replaced</div>
            <p class="dim" style="font-size:12px; margin:0 0 6px;">An earlier wording is kept rather than overwritten, so what she first asked to hear is still readable. A cadence on one of these belongs to the wording the house no longer reads from.</p>
            <%= for phrase <- @shelf.rewritten do %>
              <.history_row phrase={phrase} note="earlier wording" chip_class="chip past" />
            <% end %>
          <% end %>

          <%= if @act do %>
            <p class={class(@act)} style="margin-top:10px; font-size:12px;"><%= line(@act) %></p>
          <% end %>
        </div>
    <% end %>
    """
  end

  attr(:phrase, :map, required: true)

  defp phrase_row(assigns) do
    ~H"""
    <div class="phrase">
      <div class="row">
        <span class="phrase-text"><%= @phrase.text %></span>
        <span class={phrase_class(@phrase)}><%= phrase_word(@phrase) %></span>
      </div>
      <p class="phrase-meta"><%= meta(@phrase) %></p>
      <p class="phrase-meta"><%= delivery_line(@phrase) %></p>
      <%= if @phrase.detail do %>
        <p class="dim" style="margin:4px 0 0; font-size:12px;"><%= @phrase.detail %></p>
      <% end %>
      <div class="act-row">
        <%= if @phrase.on do %>
          <button
            type="button"
            phx-click="act"
            phx-value-verb="switch_off"
            phx-value-id={@phrase.id}
            phx-disable-with="Switching off…"
            title={"switch this off — out of the air, still on the shelf"}
            aria-label={"Switch off: #{@phrase.text}"}
          ><%= verb_word(:switch_off) %></button>
        <% end %>
        <button
          type="button"
          class="take"
          phx-click="act"
          phx-value-verb="take_away"
          phx-value-id={@phrase.id}
          phx-disable-with="Taking away…"
          title={"take this off the shelf — only her voice can put it back"}
          aria-label={"Take away: #{@phrase.text}"}
        ><%= verb_word(:take_away) %></button>
      </div>
      <%= if not @phrase.on do %>
        <p class="dim" style="margin:6px 0 0; font-size:12px;">it is off the air — only she can put it back in, so there is no switch here.</p>
      <% end %>
    </div>
    """
  end

  attr(:phrase, :map, required: true)
  attr(:note, :string, required: true)
  attr(:chip_class, :string, required: true)

  defp history_row(assigns) do
    ~H"""
    <div class="phrase">
      <div class="row">
        <span class="phrase-text dim"><%= @phrase.text %></span>
        <span class={@chip_class}><%= @note %></span>
      </div>
      <p class="phrase-meta"><%= meta(@phrase) %></p>
      <p class="phrase-meta"><%= cadence_line(@phrase) %></p>
    </div>
    """
  end

  # The bot's own labels, and only the ones it sent. A label this screen invented would
  # be this screen's opinion of what a phrase is for.
  defp meta(row) do
    [row.person_label, row.intent_label, row.state_label]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
end
