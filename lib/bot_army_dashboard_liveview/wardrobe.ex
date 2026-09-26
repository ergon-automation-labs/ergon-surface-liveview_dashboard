defmodule BotArmyDashboardLiveview.Wardrobe do
  @moduledoc """
  What is in the wardrobe, and what is on her — with the difference between the two
  ways a set gets there written down where it cannot be lost.

  The bot has had the whole cupboard for a while: `wife_care.control_panel.wardrobe.list`
  answers with the sets, the wearing that is open now, and the catalogue the sets were
  built from, and `wife_care.control_panel.wear_outfit` puts one on. The authenticated
  control surface reads that cupboard as "the closet", and someone who has claimed an
  identity there can add and archive sets. The handheld — the screen she actually
  carries — had no way to put a set on at all, so in practice the wardrobe was
  something that only changed from a laptop.

  ## The two verbs, and why both are here

  A set can arrive on her two ways, and the bot already keeps them apart: its wearing
  row carries `chosen`, written as `by == "subject"`. So this screen offers both and
  never blurs them:

    * **Wear this** is hers. It sends `by: "subject"`, and the bot records
      `chosen: true`.
    * **Assign** is the house putting a set on her. It sends `by: "louiza"`, and the
      bot records `chosen: false`.

  That distinction is the whole point of the second button. An assignment that read
  like a choice would be a lie about what she put on herself, so the mark beside what
  is on her now says which one it was — and it says it out of the bot's own record,
  not out of this screen's opinion. A `chosen` that is not a boolean is not rounded to
  either answer: it reads "not recorded", because the one thing that must never happen
  here is an assignment shown as her choice.

  The house voice is offered on the open handheld deliberately. This is not a screen
  that decides what may happen to her — the bot does, and it can refuse (a stop in
  place refuses a wear outright). What this screen must never do is *mislabel* one:
  it sends the house's own word and shows the house's own mark.

  ## The rules a wear obeys

    * **A card is drawn from the bot's fields, never from a list rebuilt here.** The
      set's parts, its description and its level come off the row the bot sent, and a
      level is printed over the range the bot published for it, so "6" is not read as
      six of nothing in particular.
    * **A failed read is a refusal, never an empty wardrobe.** `BotRead` hands a
      `{"ok": false}` envelope straight through — it does not check `ok` — so a
      wardrobe that could not be read arrives looking exactly like a successful read of
      nothing. "The wardrobe is empty" and "the wardrobe could not be read" are
      different facts, and only one of them is this screen's to say.
    * **A row this screen cannot read refuses the whole wardrobe.** A list drawn from
      some of the rows is a list that quietly lost a set.
    * **A write is never retried**, and every write is followed by a full re-read. The
      sentence afterwards reports the *read*, never the write: "the bot took it" and
      "the wardrobe reads back as" are different claims, and only the second one is
      this screen's to make.
    * **A re-read has to be today's.** The same set with the same mark is not proof by
      itself: a wear that failed leaves the previous wearing of that set still open,
      and a stale reading would confirm a write that never landed.
    * **A dead broker is not a refusal.** Where the write never left the dashboard,
      nothing was recorded; where it may have left, the sentence says that is not known
      rather than rounding it to either answer.

  ## What this screen deliberately does not offer

  `select_outfit` builds an ad-hoc set and writes an audit entry under a hardcoded
  actor, and `wardrobe.save`/`wardrobe.archive` are the upkeep of whoever keeps the
  cupboard. Both belong to the authenticated surface, where an identity has to claim
  its own voice. This screen is open, so it claims nothing it does not have: it sends
  one of the two `by` values the bot accepts and lets the record say which is which.
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker

  @read_subject "wife_care.control_panel.wardrobe.list"
  @write_subject "wife_care.control_panel.wear_outfit"
  @request_timeout 5_000

  # The two voices the bot accepts for a wearing, and the whole difference between
  # "she chose this" and "this was put on her". Not this screen's vocabulary: the
  # bot's own (`Wardrobe.validate_worn_by/1` accepts exactly these, and the wear
  # handler writes `chosen: by == "subject"`).
  @her_voice "subject"
  @house_voice "louiza"

  # The parts of a set this card draws, with the bot's own word for each one. A part
  # that did not arrive is left out rather than drawn as blank.
  @parts [{"cage", "cage"}, {"plug", "plug"}, {"clothing", "clothing"}]

  @doc "The subject the wardrobe is read on."
  def read_subject, do: @read_subject

  @doc "The subject a set is put on her on."
  def write_subject, do: @write_subject

  @doc "The voice the bot records as a choice — she picked this one."
  def chosen_by, do: @her_voice

  @doc "The voice the bot records as an assignment — this one was put on her."
  def assigned_by, do: @house_voice

  # ── the seam a host page uses ───────────────────────────────────────────────

  @doc """
  Start the one read this screen needs, and open with nothing on record.

  The read is the wardrobe itself rather than the panel state: the closet, what is on
  her now and the catalogue all come off this one reply, and the panel state does not
  carry the sets.
  """
  @spec start(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def start(socket) do
    BotRead.async(self(), :wardrobe, @read_subject, %{}, timeout: @request_timeout)
    assign(socket, closet: nil, act: nil)
  end

  @doc """
  Take the read, and reconcile it with any act that is waiting on it.

  This runs for the opening read and for the re-read after a write; they are the same
  read, and settling twice is idempotent.
  """
  @spec info(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  def info(socket, answer) do
    closet = build(answer)
    assign(socket, closet: closet, act: settle(socket.assigns.act, closet))
  end

  @doc """
  One tap, from the event to the sentence under the card.

  `verb` is `:wear` (hers) or `:assign` (the house's), and `id` is the set the card
  drew. A refusal this screen owns never reaches the bot; a sent write is always
  followed by a re-read, so the sentence reports the reading, not the acknowledgement.
  """
  @spec click(Phoenix.LiveView.Socket.t(), :wear | :assign, term()) ::
          Phoenix.LiveView.Socket.t()
  def click(socket, verb, id) do
    case plan(verb, id, socket.assigns[:closet]) do
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
    BotRead.async(self(), :wardrobe, @read_subject, %{}, timeout: @request_timeout)
    socket
  end

  # ── deciding what a tap means ───────────────────────────────────────────────

  @doc """
  Turn a tap into either a write or a refusal this screen owns.

  Returns `{:send, payload, act}` when the set is one the wardrobe is drawing, and
  `{:refused, act}` when it is not — a set the card does not have is refused here
  rather than sent, because a write this screen knows is wrong is not something to
  delegate to the bot.
  """
  @spec plan(atom(), term(), map() | nil) :: {:send, map(), map()} | {:refused, map()}
  def plan(verb, id, closet) when verb in [:wear, :assign] do
    case find_set(id, closet) do
      {:ok, set} -> {:send, %{"outfit_id" => id, "by" => by(verb)}, act(verb, set)}
      :error -> {:refused, unroutable(verb, id, closet)}
    end
  end

  def plan(_verb, id, _closet) do
    {:refused,
     %{
       id: id,
       error: "that is not one of the two things this screen does — nothing was sent"
     }}
  end

  @doc """
  Send one wear. The body is the payload itself — there is nothing to check here that
  the bot does not check harder: the set either exists or the bot says it does not,
  and a second opinion about that is a second place for it to be wrong.

  Nothing is rescued here. `Broker` already turns an unreachable connection into an
  error, and a raised bug in this screen must stay a raised bug rather than becoming
  one more plausible "the bot did not answer".
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

  `confirmed?` is not "the write returned ok" — it is "the wardrobe read back the same
  set, with the same mark, today". Anything less says what the wardrobe actually
  holds, which is the only thing this screen knows.
  """
  @spec settle(map() | nil, map() | nil) :: map() | nil
  def settle(nil, _closet), do: nil

  # A write that never left has already been answered; a reading that lands after it
  # is news about the wardrobe, not about that write.
  def settle(%{error: _error} = act, _closet), do: act

  def settle(%{id: id, verb: verb} = act, closet) do
    reading = on_of(closet)

    if sent_and_read?(reading, id, mark_for(verb)) do
      Map.put(act, :confirmed?, true)
    else
      act |> Map.put(:confirmed?, false) |> Map.put(:reading, describe(closet, reading))
    end
  end

  def settle(act, _closet), do: act

  @doc "The sentence under the card that owns this act."
  def line(%{error: error}), do: error

  def line(%{confirmed?: true, verb: :wear} = act),
    do: "the wardrobe reads back #{act.name}, recorded as her choice."

  def line(%{confirmed?: true, verb: :assign} = act),
    do:
      "the wardrobe reads back #{act.name}, recorded as assigned — put on her, not chosen by her."

  def line(%{reading: reading}),
    do: "sent — the wardrobe reads back #{reading}; showing what the wardrobe says."

  def line(%{name: name}), do: "sent #{name} — reading the wardrobe back…"

  def line(_act), do: "sent — reading the wardrobe back…"

  @doc "An error line is not a reading; it must not be styled like one."
  def class(%{error: _}), do: "unreported"
  def class(_act), do: "dim"

  # ── the wardrobe, as this screen understands it ─────────────────────────────

  @doc """
  Build the card's view of one wardrobe reply.

  Returns `%{refused: nil, sets: [...], on: ... | nil, empty?: boolean}` or, when the
  reply cannot be read as a wardrobe at all, `%{refused: sentence, sets: [], on: nil,
  empty?: false}` — never a refusal that also claims to be an empty wardrobe.
  """
  @spec build(term()) :: map()
  def build(%{"ok" => false} = answer) do
    case Map.get(answer, "error") do
      error when is_binary(error) -> refused(error)
      _other -> refused("the bot refused the wardrobe without saying why")
    end
  end

  def build(%{"sets" => sets} = answer) when is_list(sets) do
    max = max_level(Map.get(answer, "catalogue"))

    with {:ok, rows} <- rows(sets, max),
         {:ok, on} <- on_view(Map.get(answer, "worn"), max) do
      %{refused: nil, sets: rows, on: on, empty?: rows == []}
    else
      :error -> refused("the bot answered, but not with a wardrobe")
    end
  end

  def build(_answer), do: refused("the bot answered, but not with a wardrobe")

  defp refused(sentence) do
    %{refused: sentence, sets: [], on: nil, empty?: false}
  end

  # Every row has to be drawable. One that is not refuses the lot: a list built from
  # the rows this screen happened to understand is a list that lost a set without
  # saying so, and a set missing from a wardrobe looks exactly like a set she does not
  # own.
  defp rows(sets, max) do
    if Enum.all?(sets, &set?/1) do
      {:ok, Enum.map(sets, &row_view(&1, max))}
    else
      :error
    end
  end

  defp set?(row) when is_map(row) do
    not is_nil(text(row["id"])) and not is_nil(text(row["name"])) and accessory_list?(row)
  end

  defp set?(_row), do: false

  # `accessories` is drawn on the card, so a value that is not a list of things would
  # read as a set with no accessories rather than as a row this screen cannot read.
  defp accessory_list?(row), do: is_nil(row["accessories"]) or is_list(row["accessories"])

  defp row_view(row, max) do
    %{
      id: row["id"],
      name: row["name"],
      detail: detail(parts_line(row), row["humiliation_level"], max),
      description: text(row["description"]) || ""
    }
  end

  # A wearing is either nothing (the bot's own answer for "no wearing is open") or a
  # row that names itself or its set. Anything else is a wardrobe this screen cannot
  # read, and is refused rather than drawn as "nothing is on her" — one is a read that
  # failed and the other is a fact about her body.
  defp on_view(nil, _max), do: {:ok, nil}

  defp on_view(%{"name" => name} = worn, max) when is_binary(name),
    do: {:ok, wearing_view(worn, max)}

  defp on_view(%{"outfit_id" => id} = worn, max) when is_binary(id),
    do: {:ok, wearing_view(worn, max)}

  defp on_view(_worn, _max), do: :error

  defp wearing_view(worn, max) do
    parts = if is_map(worn["parts"]), do: worn["parts"], else: %{}

    %{
      id: text(worn["outfit_id"]),
      name: text(worn["name"]) || "an unnamed set",
      detail: detail(parts_line(parts), Map.get(parts, "humiliation_level"), max),
      mark: mark_of(worn["chosen"]),
      at: text(worn["worn_at"])
    }
  end

  # A level is printed over the range the bot published for it, so "7" is not read as
  # seven of anything in particular. A number the catalogue does not describe prints
  # as the number alone, rather than being given a denominator this screen invented.
  defp detail(parts, level, max) do
    case {parts, level_text(level, max)} do
      {parts, nil} -> parts
      {"", level} -> level
      {parts, level} -> "#{parts}  ·  #{level}"
    end
  end

  defp level_text(level, max) when is_integer(level) and is_integer(max),
    do: "humiliation #{level} of #{max}"

  defp level_text(level, _max) when is_integer(level), do: "humiliation #{level}"
  defp level_text(_level, _max), do: nil

  defp parts_line(source) when is_map(source) do
    parts =
      for {key, label} <- @parts,
          value = text(source[key]),
          is_binary(value),
          do: "#{label} #{value}"

    case accessories(source["accessories"]) do
      [] -> Enum.join(parts, " · ")
      list -> Enum.join(parts ++ ["accessories #{Enum.join(list, ", ")}"], " · ")
    end
  end

  defp parts_line(_source), do: ""

  defp accessories(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp accessories(_value), do: []

  # A string the bot actually sent, or nothing. Empty is nothing: a set with no name
  # is not a set a card can draw, and an empty string is how a blank field travels.
  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp max_level(%{"humiliation_level" => %{"max" => max}}) when is_integer(max), do: max
  defp max_level(_catalogue), do: nil

  defp mark_of(true), do: :chosen
  defp mark_of(false), do: :assigned

  # Not a boolean is not an answer, and it is not rounded to one. It is not "chosen"
  # — that would show an assignment as her choice — and it is not "assigned" either,
  # because that would put a word in the record's mouth.
  defp mark_of(_other), do: :unstated

  defp mark_for(:wear), do: :chosen
  defp mark_for(:assign), do: :assigned

  # The re-read counts as the one that was sent only when it names the same set,
  # carries the same mark, and is today's. Same set and same mark is not enough: a
  # wear that failed leaves the previous wearing of that set still open, and a stale
  # reading would confirm a write that never landed.
  defp sent_and_read?(reading, id, mark) do
    reading != nil and Map.get(reading, :id) == id and Map.get(reading, :mark) == mark and
      today?(Map.get(reading, :at))
  end

  defp today?(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, at, _offset} -> DateTime.to_date(at) == DateTime.to_date(DateTime.utc_now())
      _other -> false
    end
  end

  defp today?(_timestamp), do: false

  defp describe(closet, nil) do
    if refused?(closet), do: "a wardrobe that could not be read", else: "nothing on her"
  end

  defp describe(_closet, %{name: name, mark: :chosen}), do: "#{name}, recorded as her choice"
  defp describe(_closet, %{name: name, mark: :assigned}), do: "#{name}, recorded as assigned"

  defp describe(_closet, %{name: name}),
    do: "#{name}, with nothing recorded about who chose it"

  defp describe(_closet, _reading), do: "something this screen cannot name"

  defp refused?(%{refused: refused}) when is_binary(refused), do: true
  defp refused?(_closet), do: false

  defp on_of(%{on: on}), do: on
  defp on_of(_closet), do: nil

  defp find_set(id, closet) when is_binary(id) do
    sets = Map.get(closet || %{}, :sets, [])

    case Enum.find(sets, &(Map.get(&1, :id) == id)) do
      nil -> :error
      set -> {:ok, set}
    end
  end

  defp find_set(_id, _closet), do: :error

  defp by(:wear), do: @her_voice
  defp by(:assign), do: @house_voice

  defp act(verb, set) do
    %{verb: verb, id: set.id, name: set.name}
  end

  # A refusal this screen owns says so in its own words: the bot was never asked, and
  # the one thing the sentence has to make unambiguous is that nothing was sent. The
  # four facts are different facts — a tap with no set on it, a wardrobe that was never
  # read, a wardrobe that could not be read, and a set that is no longer on the card —
  # and each gets its own sentence rather than one shared shrug.
  defp unroutable(verb, id, closet) do
    %{verb: verb, id: id, error: unroutable_sentence(id, closet)}
  end

  defp unroutable_sentence(id, _closet) when not is_binary(id) or id == "",
    do: "that tap had no set on it — nothing was sent"

  defp unroutable_sentence(_id, nil),
    do: "the wardrobe has not been read yet — nothing was sent"

  defp unroutable_sentence(_id, %{refused: refused}) when is_binary(refused) and refused != "",
    do: "the wardrobe could not be read, so nothing was sent"

  defp unroutable_sentence(_id, _closet),
    do: "that set is not on this card — reload the page and tap it again, nothing was sent"

  # A refusal keeps the bot's own sentence: it names the set, or the stop that is in
  # place, and none of that is improved by this screen paraphrasing it. A reply that is
  # not a result says so rather than being rounded up to success.
  defp decode_write(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => data}} when is_map(data) -> {:ok, data}
      {:ok, %{"ok" => true}} -> {:ok, %{}}
      {:ok, %{"ok" => false, "error" => error}} when is_binary(error) -> {:error, error}
      {:ok, %{"ok" => false}} -> {:error, "the bot refused it without saying why"}
      {:ok, _other} -> {:error, "the bot answered something that is not a result"}
      {:error, _reason} -> {:error, "the bot's answer could not be read"}
    end
  end

  # A dead broker is not a refusal and must not read like one. Where the write never
  # left the dashboard, nothing was recorded; where it may have left, this screen does
  # not know whether it was, and says that rather than rounding it to either answer.
  defp write_trouble({:error, :no_broker}) do
    Logger.debug("[Wardrobe] a write answered nothing: the broker is not reachable")
    "no answer from the wife care bot — nothing was recorded"
  end

  defp write_trouble(reason) do
    Logger.debug("[Wardrobe] a write answered nothing: #{inspect(reason)}")
    "no answer from the wife care bot — whether anything was recorded is not known"
  end

  # ── one card ────────────────────────────────────────────────────────────────

  @doc """
  The wardrobe card, with its own styles and its own result line.

  `closet` is the built view of the wardrobe reply; while it is `nil` the card says the
  read has not landed rather than drawing an empty wardrobe. `read_error` is the failed
  read the hooks put on the socket: with it, the card says the wardrobe was not read at
  all, because "nothing is on her" and "the wardrobe could not be read" are different
  facts.
  """
  attr(:closet, :map, default: nil)
  attr(:act, :map, default: nil)
  attr(:read_error, :string, default: nil)

  def card(assigns) do
    ~H"""
    <style>
      .closet-card { background: #131a3a; border: 1px solid #222c56; border-radius: 10px; padding: 14px 16px; margin: 0 auto 14px; max-width: 900px; }
      .closet-card .card-title { font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #6f7db2; margin-bottom: 10px; }
      .closet-card .row { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; }
      .closet-card .dim { color: #8b93b0; }
      .closet-card .unreported { color: #b98b3f; }
      .closet-card .chip { display: inline-block; padding: 2px 8px; border-radius: 999px; border: 1px solid #2c3766; color: #a9b4e0; font-size: 12px; white-space: nowrap; }
      .closet-card .chip.chosen { color: #0a0e27; background: #ffd166; border-color: #ffb545; font-weight: 600; }
      .closet-card .chip.assigned { color: #ffd9a0; background: #241f36; border-color: #6b4d7a; font-weight: 600; }
      .closet-card .chip.unstated { color: #b98b3f; border-color: #6b5a2f; }
      .on-now { border: 1px solid #222c56; border-radius: 8px; padding: 10px 12px; margin-bottom: 12px; background: #10162f; }
      .closet-set { border-top: 1px solid #1c2447; padding: 10px 0 4px; }
      .act-row { display: flex; gap: 8px; margin: 8px 0 4px; }
      .act-row button { flex: 1; min-height: 44px; font: inherit; font-size: 15px; color: #a9b4e0; background: #10162f; border: 1px solid #222c56; border-radius: 8px; cursor: pointer; }
      .act-row button.assign { color: #ffd9a0; border-color: #4a3a5c; }
      .closet-legend { color: #6f7db2; font-size: 12px; margin: 6px 0 4px; }
    </style>

    <%= if @read_error do %>
      <div class="closet-card">
        <div class="card-title">The wardrobe</div>
        <p class="unreported">The wardrobe was not read — anything listed here would be this screen guessing at what she owns and what is on her.</p>
      </div>
    <% else %>
      <%= cond do %>
        <% is_nil(@closet) -> %>
          <div class="closet-card">
            <div class="card-title">The wardrobe</div>
            <p class="unreported">nothing from the wardrobe yet — the card appears when the read lands</p>
          </div>
        <% @closet.refused -> %>
          <div class="closet-card">
            <div class="card-title">The wardrobe</div>
            <p class="unreported"><%= @closet.refused %></p>
            <p class="dim" style="font-size:12px;">No sets are drawn: a list put together from a wardrobe that could not be read would be this screen inventing what she owns.</p>
          </div>
        <% true -> %>
          <div class="closet-card">
            <div class="card-title">The wardrobe — what is in it, and what is on her  ·  tap to put one on</div>

            <%= if @closet.on do %>
              <div class="on-now">
                <div class="row">
                  <span><strong><%= @closet.on.name %></strong></span>
                  <span class={mark_class(@closet.on.mark)}><%= mark_word(@closet.on.mark) %></span>
                </div>
                <%= if @closet.on.detail != "" do %>
                  <p class="dim" style="margin:6px 0 0; font-size:12px;"><%= @closet.on.detail %></p>
                <% end %>
                <p class="dim" style="margin:6px 0 0; font-size:12px;"><%= mark_sentence(@closet.on.mark) %></p>
              </div>
            <% else %>
              <p class="dim">nothing is on her — the wardrobe has no wearing open.</p>
            <% end %>

            <p class="closet-legend">
              Wear this is hers, and the wardrobe records it as her choice. Assign is the house putting a set on her, and the wardrobe records it as assigned — the mark above says which one is on her now, from the wardrobe's own record.
            </p>

            <%= for set <- @closet.sets do %>
              <div class="closet-set">
                <div class="row">
                  <span><strong><%= set.name %></strong></span>
                  <%= if set.detail != "" do %>
                    <span class="dim" style="font-size:12px;"><%= set.detail %></span>
                  <% end %>
                </div>
                <%= if set.description != "" do %>
                  <p class="dim" style="margin:4px 0 0; font-size:12px;"><%= set.description %></p>
                <% end %>
                <div class="act-row">
                  <button
                    type="button"
                    phx-click="wear_set"
                    phx-value-id={set.id}
                    phx-disable-with="Wear this…"
                    title={"wear #{set.name} — recorded as her choice"}
                    aria-label={"wear #{set.name}, recorded as her choice"}
                  >Wear this</button>
                  <button
                    type="button"
                    class="assign"
                    phx-click="assign_set"
                    phx-value-id={set.id}
                    phx-disable-with="Assign…"
                    title={"assign #{set.name} to her — recorded as assigned, not her choice"}
                    aria-label={"assign #{set.name}, recorded as assigned and not as her choice"}
                  >Assign</button>
                </div>
              </div>
            <% end %>

            <%= if @closet.empty? do %>
              <p class="dim empty-state">the wardrobe has no sets in it — sets are added and archived on the control surface, not from here.</p>
            <% end %>

            <%= if @act do %>
              <p class={class(@act)} style="margin-top:8px; font-size:12px;"><%= line(@act) %></p>
            <% end %>
          </div>
      <% end %>
    <% end %>
    """
  end

  # The mark, said in one word and explained in one sentence. It is the wardrobe's
  # record, so the sentence says so: this screen is not the one that decided. These
  # three are public because they are the whole vocabulary of the mark, and a test that
  # kept its own copy of the words would be asserting against itself.
  @doc "The mark in one word, for the chip."
  def mark_word(:chosen), do: "chosen by her"
  def mark_word(:assigned), do: "assigned"
  def mark_word(:unstated), do: "not recorded"

  @doc "The chip's class, so the two marks cannot look alike."
  def mark_class(:chosen), do: "chip chosen"
  def mark_class(:assigned), do: "chip assigned"
  def mark_class(:unstated), do: "chip unstated"

  @doc "The mark as a sentence, in the wardrobe's voice rather than this screen's."
  def mark_sentence(:chosen), do: "the wardrobe has this down as her choice."

  def mark_sentence(:assigned),
    do: "the wardrobe has this down as assigned — put on her, not chosen by her."

  def mark_sentence(:unstated),
    do: "the wardrobe did not record whether this was chosen or assigned."
end
