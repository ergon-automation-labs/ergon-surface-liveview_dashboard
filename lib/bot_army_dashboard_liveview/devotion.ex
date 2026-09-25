defmodule BotArmyDashboardLiveview.Devotion do
  @moduledoc """
  Writing a devotion back to the goddess — and the seeds that give her something
  to write about.

  A devotion lives in the **window** (`BotArmyWifeCare.Services.ControlPanel.Window`),
  as a reply of kind `note`: the pane that holds what came back from her, surfaced
  to Louiza in the subject's own voice. That pane already carries the rules this
  screen inherits rather than restates:

    * nothing in the window is compliance data. A note never enters a score, a
      streak, or a quota, and writing *about* a devotion is not performing one —
      so this screen cannot be the thing that makes the ladder move;
    * the note is hers. The screen does not draft it, does not suggest a sentence,
      and does not rewrite what she wrote;
    * her text goes to the goddess and nowhere else: not into a prompt, not into
      the audit payload (the bot audits *that* a reply was recorded, never its
      text), and not onto the household HUD — the panel state publishes a
      `reply_count` and deliberately not the replies.

  ## Why the seeds are the point

  A blank page is not an invitation, it is a chore. So the screen arrives with the
  facts the bot already reports about her own week — the count against the quota,
  the run, and the house's own present-tense `notice` — and two openers in the
  house's voice. **A seed is a fact, never a draft.** It gives her something true
  to write *about*; it never puts a sentence in her mouth. When the bot has not
  answered, every seed is absent and the screen says the record has not landed
  rather than drawing zeros.

  ## Only notes are shown back

  The window also holds `too_much`, `that_hurt`, and `stop`. This screen filters to
  `note` on purpose: a stop is consent information and it belongs where it is read
  as one. A list that mixed a stop in with the devotions would quietly teach her
  that a stop is just another note.

  ## Two reads, one write

    * `wife_care.control_panel.subject_replies` — what she has said back, newest first
    * `wife_care.control_panel.state` — the facts the seeds are drawn from (the same
      reply the household HUD reads)
    * `wife_care.control_panel.subject_reply` — `{"kind": "note", "text": ...}`

  A write is followed by a re-read, and what the screen says was recorded is what
  the bot's own record shows — never the fact that the call returned ok.
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @notes_subject "wife_care.control_panel.subject_replies"
  @write_subject "wife_care.control_panel.subject_reply"
  @panel_subject "wife_care.control_panel.state"
  @request_timeout 3_000
  @shown 10
  @openers [
    "what is worth telling her about today?",
    "what would you want her to know that the record cannot show?"
  ]

  @doc "The subject her own notes are read from."
  def notes_subject, do: @notes_subject

  @doc "The subject a note is written to."
  def write_subject, do: @write_subject

  @doc "The openers the house offers, which are questions and never drafts."
  def openers, do: @openers

  # ── the seam a host page uses ───────────────────────────────────────────────

  @doc """
  Start the two reads, and open with nothing on record.

  The notes read and the facts read are separate questions and they fail
  separately. Both are wanted at once, so both are asked at once.
  """
  @spec start(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def start(socket) do
    BotRead.async(self(), :devotion_notes, @notes_subject, %{}, timeout: @request_timeout)
    BotRead.async(self(), :devotion_facts, @panel_subject, %{}, timeout: @request_timeout)

    assign(socket, notes: nil, facts: nil, outcome: nil, draft: "")
  end

  @doc """
  Take one of the two answers.

  A notes answer shaped like neither a list nor a keyed list is a failure, not an
  empty list: the screen says the read failed instead of saying she has never
  written anything.
  """
  @spec info(Phoenix.LiveView.Socket.t(), atom(), term()) :: Phoenix.LiveView.Socket.t()
  def info(socket, :devotion_notes, answer) do
    case BotRead.list(answer, "replies") do
      {:ok, replies} -> socket |> assign(notes: notes_only(replies)) |> settle_pending()
      :error -> BotRead.failed(socket, :devotion_notes, :unexpected_reply)
    end
  end

  def info(socket, :devotion_facts, answer) do
    assign(socket, facts: HUD.build(answer, nil).devotion)
  end

  def info(socket, _tag, _answer), do: socket

  @doc "Keep the box in step with what she is typing, so a send can clear it."
  @spec draft(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def draft(socket, raw), do: assign(socket, draft: to_text(raw))

  @doc """
  One send, from the form to the sentence under it.

  A refusal this screen owns never reaches the bot. A sent write is always
  followed by a re-read of the notes, so the screen reports the bot's record
  rather than the bot's acknowledgement.
  """
  @spec click(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def click(socket, raw) do
    case plan(raw) do
      {:refused, outcome} ->
        assign(socket, outcome: outcome, draft: to_text(raw))

      {:send, payload, outcome} ->
        send_note(socket, payload, outcome)
    end
  end

  defp send_note(socket, payload, outcome) do
    case write(payload) do
      {:ok, _data} ->
        socket |> assign(outcome: outcome, draft: "") |> reread_notes()

      {:error, sentence} ->
        assign(socket, outcome: Map.put(outcome, :error, sentence), draft: outcome.sent)
    end
  end

  defp reread_notes(socket) do
    BotRead.async(self(), :devotion_notes, @notes_subject, %{}, timeout: @request_timeout)
    socket
  end

  # The confirmation is about the notes read, so it is settled when the notes
  # arrive — including the re-read that follows a send. Settling it on the facts
  # read instead looked right and was not: the facts answer at mount, before
  # there is anything to confirm.
  defp settle_pending(socket) do
    assign(socket, outcome: settle(socket.assigns[:outcome], socket.assigns[:notes]))
  end

  defp note?(reply), do: kind_of(reply) == "note"

  defp kind_of(reply), do: text_of(field(reply, "kind"))

  defp text_of(value) when is_binary(value), do: value
  defp text_of(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp text_of(_value), do: ""

  # ── deciding what a send means ──────────────────────────────────────────────

  @doc """
  Turn a submission into either a write or a refusal this screen owns.

  An empty note is refused here rather than sent: the bot will record a blank
  text, and a blank row in the record of what she said to the goddess is a row
  that claims she said something. There is no length cap — a ceiling this screen
  invented would be a second place for a rule to be wrong.
  """
  @spec plan(term()) :: {:send, map(), map()} | {:refused, map()}
  def plan(raw) do
    case to_text(raw) do
      "" ->
        {:refused,
         %{
           what: "your note",
           error: "a note with nothing in it is not a note — write something, or leave the page."
         }}

      text ->
        {:send, %{"kind" => "note", "text" => text}, %{what: "your note", sent: text}}
    end
  end

  @doc """
  Send one note. The body is the payload itself — there is nothing to check here
  that the bot does not check harder.
  """
  @spec write(map()) :: {:ok, map()} | {:error, String.t()}
  def write(payload) do
    case Broker.request(@write_subject, Jason.encode!(payload), timeout: @request_timeout) do
      {:ok, %{body: body}} -> decode_write(body)
      other -> {:error, write_trouble(other)}
    end
  rescue
    error -> {:error, write_trouble({:raised, error})}
  catch
    kind, reason -> {:error, write_trouble({kind, reason})}
  end

  @doc """
  Reconcile a note with a fresh read.

  `confirmed?` is not "the write returned ok" — it is "the bot's record now holds
  the text that was sent". Anything less says what the bot actually reports.
  """
  @spec settle(map() | nil, [map()] | nil) :: map() | nil
  def settle(nil, _notes), do: nil
  def settle(outcome, nil), do: outcome

  def settle(%{sent: text} = outcome, notes) when is_list(notes) do
    if Enum.any?(notes, &(field(&1, "text") == text)) do
      Map.put(outcome, :confirmed?, true)
    else
      outcome
    end
  end

  def settle(outcome, _notes), do: outcome

  @doc "The sentence under the box that owns this send."
  def line(%{error: error}), do: error
  def line(%{confirmed?: true}), do: "logged — the record now holds it."
  def line(_outcome), do: "sent — reading it back…"

  @doc "An error line is not a reading; it must not be styled like one."
  def class(%{error: _}), do: "unreported"
  def class(_outcome), do: "dim"

  # ── the seeds ───────────────────────────────────────────────────────────────

  @doc """
  The seed lines: facts about her own week, and nothing else.

  Every line is either something the bot reported or absent — never a zero
  standing in for a silence.
  """
  @spec seed_lines(map() | nil) :: [String.t()]
  def seed_lines(facts) when is_map(facts) do
    [week_line(facts), run_line(facts), notice_line(facts)]
    |> Enum.reject(&is_nil/1)
    |> fallback_line()
  end

  def seed_lines(_facts),
    do: ["the bot has not answered, so there is no record to write from — write anyway."]

  defp week_line(%{week: week, required: required} = facts)
       when is_integer(week) and is_integer(required) do
    if facts[:met?],
      do: "the week is met: #{week} of #{required}",
      else: "devotions this week: #{week} of #{required}"
  end

  defp week_line(_facts), do: nil

  defp run_line(%{run: run} = facts) when is_integer(run) and run > 0 do
    case facts[:longest] do
      longest when is_integer(longest) and longest > run ->
        "the run is #{run}, and it has been #{longest}"

      _other ->
        "the run is #{run}"
    end
  end

  defp run_line(_facts), do: nil

  defp notice_line(%{notice: notice}) when is_binary(notice), do: notice
  defp notice_line(_facts), do: nil

  defp fallback_line([]),
    do: ["the bot has nothing on the week yet — that is not the same as a bad week."]

  defp fallback_line(lines), do: lines

  # ── the cards ───────────────────────────────────────────────────────────────

  @doc "What the bot reports about her week, as the material for a note."
  attr(:facts, :map, default: nil)

  def seeds(assigns) do
    ~H"""
    <div class="devotion-card">
      <div class="card-title">What the week holds</div>
      <ul class="devotion-seeds">
        <li :for={line <- seed_lines(@facts)}><%= line %></li>
      </ul>
      <div class="devotion-openers">
        <div class="dim">to get you started, in the house's voice</div>
        <ul>
          <li :for={opener <- openers()}><%= opener %></li>
        </ul>
      </div>
    </div>
    """
  end

  @doc "The box she writes in, and the honest sentence about what happened to it."
  attr(:draft, :string, default: "")
  attr(:outcome, :map, default: nil)

  def composer(assigns) do
    ~H"""
    <div class="devotion-card">
      <div class="card-title">Write it in your own words</div>
      <form phx-change="draft_devotion" phx-submit="write_devotion" class="devotion-form">
        <textarea
          id="devotion-text"
          name="text"
          rows="7"
          placeholder="anything you want her to have"
          class="devotion-box"
        ><%= @draft %></textarea>
        <div class="devotion-actions">
          <button type="submit" phx-disable-with="sending…">send it to her</button>
          <span class="dim"><%= String.length(@draft) %> characters</span>
        </div>
        <p :if={@outcome} class={class(@outcome)}><%= line(@outcome) %></p>
      </form>
    </div>
    """
  end

  @doc """
  Her earlier notes, newest first — only the notes.

  A stop, a `too_much`, and a `that_hurt` are answers about the dynamic and they
  stay where they are read as answers. This list is what she wrote, kept so she
  does not have to remember whether she said something and how she said it.
  """
  attr(:notes, :list, default: nil)

  def past(assigns) do
    ~H"""
    <div class="devotion-card">
      <div class="card-title">Earlier notes</div>
      <p :if={@notes == nil} class="dim">reading what you have written…</p>
      <p :if={@notes == []} class="dim">nothing written yet — the first one can be short.</p>
      <ol class="devotion-past">
        <li :for={note <- @notes || []}>
          <div class="devotion-when"><%= when_label(note) %></div>
          <div class="devotion-text"><%= field(note, "text") %></div>
        </li>
      </ol>
    </div>
    """
  end

  # ── reading a note ──────────────────────────────────────────────────────────

  @doc "Only the notes, newest first, capped for the screen."
  @spec notes_only(term()) :: [map()]
  def notes_only(replies) when is_list(replies) do
    replies
    |> Enum.filter(&note?/1)
    |> Enum.take(@shown)
  end

  def notes_only(_replies), do: []

  @doc "The day a note was written, from whatever the bot put in `at`."
  @spec when_label(term()) :: String.t()
  def when_label(note) do
    case field(note, "at") do
      at when is_binary(at) and byte_size(at) >= 10 -> String.slice(at, 0, 10)
      _other -> "earlier"
    end
  end

  @doc """
  One field of a note, whether it arrived with string keys or atoms.

  The window round-trips through the store, so a reply read back off the live
  struct carries atoms and the same reply on the wire carries strings. A read
  that only understood one shape would show a blank note and call it a note.
  """
  @spec field(term(), String.t()) :: term()
  def field(map, key) when is_map(map) do
    Enum.find_value(map, fn
      {k, value} when is_binary(k) -> if k == key, do: value
      {k, value} when is_atom(k) -> if Atom.to_string(k) == key, do: value
      _other -> nil
    end)
  end

  def field(_map, _key), do: nil

  # ── plumbing ────────────────────────────────────────────────────────────────

  defp to_text(nil), do: ""
  defp to_text(raw) when is_binary(raw), do: String.trim(raw)
  defp to_text(raw), do: raw |> to_string() |> String.trim()

  # A refusal keeps the bot's own sentence: it says what was wrong, and none of
  # that is improved by this screen paraphrasing it. A reply that is not a result
  # says so rather than being rounded up to success.
  defp decode_write(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => data}} when is_map(data) -> {:ok, data}
      {:ok, %{"ok" => true}} -> {:ok, %{}}
      {:ok, %{"ok" => false, "error" => error}} when is_binary(error) -> {:error, error}
      {:ok, %{"ok" => false}} -> {:error, "the bot refused it without saying why"}
      {:ok, _other} -> {:error, "the bot answered something that is not a result"}
      {:error, _} -> {:error, "the answer from the bot could not be read"}
    end
  end

  # A dead broker is not a refusal and must not read like one. "Nothing was
  # recorded" is the one thing this sentence has to make unambiguous.
  defp write_trouble(reason) do
    Logger.debug("[Devotion] a write answered nothing: #{inspect(reason)}")
    "no answer from the wife care bot — nothing was recorded"
  end
end
