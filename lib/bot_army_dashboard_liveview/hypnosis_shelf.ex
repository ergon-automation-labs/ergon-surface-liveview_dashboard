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
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker

  @read_subject "wife_care.control_panel.hypnosis"
  @write_subject "wife_care.control_panel.hypnosis_phrase"
  @request_timeout 5_000

  # The voice this screen writes as. Not hers — see the module doc — and not the
  # house's either: the house's own assignment of a phrase is not a thing this screen
  # does. `Hypnosis` accepts exactly `subject`, `louiza`, `operator` and `system`, and
  # this is the one of those that claims nothing about what she asked to hear.
  @actor "operator"

  @verbs [:switch_off, :take_away]

  @doc "The subject the shelf is read on."
  def read_subject, do: @read_subject

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
    assign(socket, shelf: nil, act: nil)
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
         detail: label(row, "detail")
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
      reworded: length(rewritten)
    }
  end

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
    "#{counts.on} in the air · #{counts.off} off the air · #{counts.away} taken away · #{counts.reworded} with earlier wording"
  end

  def counts_line(_shelf), do: ""

  # ── one card ────────────────────────────────────────────────────────────────

  @doc """
  The shelf card, with its own styles and its own result line.

  `shelf` is the built view of the shelf reply; while it is `nil` the card says the read
  has not landed rather than drawing an empty shelf. `read_error` is the failed read the
  hooks put on the socket: with it, the card says the shelf was not read at all, because
  "nothing is in the air" and "the shelf could not be read" are different facts.
  """
  attr(:shelf, :map, default: nil)
  attr(:act, :map, default: nil)
  attr(:read_error, :string, default: nil)

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
      .shelf-section { font-size: 12px; letter-spacing: 1.2px; text-transform: uppercase; color: #6f7db2; margin: 16px 0 2px; }
    </style>

    <%= if @read_error do %>
      <div class="shelf-card">
        <div class="card-title">Her shelf</div>
        <p class="unreported">The shelf was not read — anything drawn here would be this screen guessing at what she asked to hear, and that is not a thing to guess at.</p>
      </div>
    <% else %>
      <%= cond do %>
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

            <p class={narration_class(@shelf.narration)} style="margin:0 0 6px; font-size:12px;"><%= narration_word(@shelf.narration) %>: <%= narration_sentence(@shelf.narration) %></p>

            <p class="shelf-legend">
              <%= verb_word(:switch_off) %> takes a phrase out of the air, and <%= verb_word(:take_away) %> takes it off the shelf while keeping the record of it. Putting a phrase on the shelf, rewording one, and putting one back are hers: this screen is open to whoever is holding the phone, so it claims no voice of hers and offers none of those.
            </p>

            <p class="shelf-counts"><%= counts_line(@shelf) %></p>

            <%= for phrase <- @shelf.phrases do %>
              <.phrase_row phrase={phrase} />
            <% end %>

            <%= if @shelf.empty? do %>
              <p class="dim empty-state">nothing is in the air — the shelf is empty. A phrase gets onto it in her own voice, which is not a voice this screen has.</p>
            <% end %>

            <%= if @shelf.put_away != [] do %>
              <div class="shelf-section">Taken away</div>
              <p class="dim" style="font-size:12px; margin:0 0 6px;">These were taken off the shelf, and only her voice can put one back — so there is no button here.</p>
              <%= for phrase <- @shelf.put_away do %>
                <.history_row phrase={phrase} note="taken away" chip_class="chip away" />
              <% end %>
            <% end %>

            <%= if @shelf.rewritten != [] do %>
              <div class="shelf-section">The wording these replaced</div>
              <p class="dim" style="font-size:12px; margin:0 0 6px;">An earlier wording is kept rather than overwritten, so what she first asked to hear is still readable.</p>
              <%= for phrase <- @shelf.rewritten do %>
                <.history_row phrase={phrase} note="earlier wording" chip_class="chip past" />
              <% end %>
            <% end %>

            <%= if @act do %>
              <p class={class(@act)} style="margin-top:10px; font-size:12px;"><%= line(@act) %></p>
            <% end %>
          </div>
      <% end %>
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
