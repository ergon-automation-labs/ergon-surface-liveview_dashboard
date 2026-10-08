defmodule BotArmyDashboardLiveview.PartyWindow do
  @moduledoc """
  The window she is in with the party, read from the bot that already keeps it.

  The party, the window and the turns are not new things to build. `bot_army_rpg`
  (the Resistance Chronicle) has held them since before this screen: a **session**
  is an open window with a scene and a status, its joined **characters** are the
  party, and its **scene facts** are the turns. The design draft that planned new
  party tables in another repo would have been a second copy of a live domain in a
  second place to be wrong, so this screen reads the one that exists:

    * `rpg.session.gather_context` — the open window, its scene, its theme and its
      recent turns, or the bot's own word that no window is open
    * `rpg.session.state` — the session's `character_ids`, which is the party
    * `rpg.scene.fact.add` — one turn, written when the operator replies

  Every one of those is a question the bot already answers. Nothing here decides
  what a session is; this module decides what a screen may *say* about one.

  ## Three answers, not two

  A window question has three outcomes, and the screens in this suite have paid for
  the difference more than once (N+25): the bot opened a window (`{:open_window,
  window}`), the bot said there is none (`{:no_window, sentence}`), or the question
  did not come back as a window at all (`{:unreported, sentence}`). An answer that
  never mentioned a window is not a report that no window is open, and a screen
  that reads it as one takes the window away on the strength of a question nobody
  answered.

  A refusal that names `:no_active_session` is the one definite nothing: the store
  was asked, it looked, and there is no active session for this user. Any other
  refusal — a store that answered something unexpected, a reply this screen cannot
  read — is `:unreported`, carrying the bot's own word where there is one.

  ## The story so far

  Every window used to open cold. `rpg.session.start` always creates a new session —
  it never picks up an open one — and the turns were only ever read per session, so a
  new window opened on *nothing has been said in this window yet* while the last
  conversation sat right there in the previous one. The fix belongs to the domain, not
  to this screen: the window question now carries the story so far — the newest turns
  of this identity's *other* windows, oldest first, each with who spoke it.

  That read has three outcomes here, like every other read on this screen, and they
  are not interchangeable: the bot carried the earlier turns (a list, oldest first),
  the bot looked and nothing came before (`[]`), or the bot did not report it
  (`nil` — the field absent, or the carry unreadable). *Nothing came before* is a
  reading; *the bot did not say* is not, and this module never renders the second as
  the first.

  ## What a turn is, and who spoke it

  `scene_facts` arrives newest first (the bot sorts by `created_at desc` and takes
  its limit), so this module reverses it: a window reads as a conversation, oldest
  at the top. A reply is written as `source: "operator"` and `category: "dialogue"`
  — the dashboard is open and proves nothing about who is holding the phone, so the
  record says the operator spoke, which is what the shelf's verbs already say. It
  never says *she* said it.

  ## The words that have not arrived yet

  When the party has named a narrator, the turn is *hers* to write, and rpg hands the
  words to her instead of writing them itself. It also writes a note down (a `system`
  fact, so it is not a turn in either window read) and reports the state of that note
  as `"narration"` on the window question. So a window can be asked for a turn and
  still be wordless, and the screen has to say which of those it is looking at:

    * `{:pending, bot_id, at}` — she was asked and nothing has been written since. The
      window says so with `(she says nothing yet)`, and `at` — when the ask was made —
      is how the screen adds *how long* without ever promising how long is left. It
      does not fill the silence with prose, because the words said here are hers.
    * `{:answered, bot_id}` — a turn newer than the note is signed with her name, so
      she has written. *Signed with her name* is the same rule that decides who wrote
      any other turn.
    * `{:no_ask, nil}` — no turn in what was read was handed to a narrator.
    * `{:unreported, sentence}` — the bot did not say. An older bot never sends the
      field, and *this bot never asked anyone* is not something this screen knows.

  `nil` is not `{:no_ask, nil}`: the first is a question that did not come back, the
  second is a bot that looked and reports nothing pending.

  ## Who narrates

  The party can name one of its members the narrator (`rpg.party.set_narrator`), and
  that role rides the party the window question already carries — so the badge on a
  row is a reading of the window answer, not a third question. It is the same three
  answers as every other read here: one member holds the role, the party was read and
  nobody holds it, or the party was not reported. The badge is drawn only for the
  first; an unread roster badges nobody and this screen says nothing about who
  narrates, which is not the claim that nobody does.
  """

  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.PartyIdentity

  @context_subject "rpg.session.gather_context"
  @state_subject "rpg.session.state"
  @write_subject "rpg.scene.fact.add"
  @request_timeout 5_000

  # The identity the window is read and written as, owned by
  # `BotArmyDashboardLiveview.PartyIdentity` — one owner, so this screen and the party
  # screen cannot disagree about who the party belongs to. A **read** names the tenant
  # and no user (a live session carries `user_id: nil`, so naming one here would make
  # this screen answer *no window is open* while a window is open). A **write** names
  # the party's user, because the bot reads the party back from the turn it is given to
  # find the narrator the line is handed to.

  # The voice a reply is filed as — see the module doc.
  @source "operator"

  # Her side of an exchange is dialogue; the observation the bot narrates is the
  # bot's own category, not this screen's.
  @category "dialogue"

  # A reply longer than this is refused here, with the ceiling in the refusal
  # rather than sent and rejected: a turn in a scene is a sentence, not an essay.
  @max_reply 2_000

  # The bot's word for "I looked, and there is no active session". This is the only
  # refusal that is a report of nothing rather than an unanswered question.
  @no_session ":no_active_session"

  @doc "The subject the window is read on."
  def context_subject, do: @context_subject

  @doc "The subject the party is read on."
  def state_subject, do: @state_subject

  @doc "The subject a reply is written on."
  def write_subject, do: @write_subject

  @doc "The longest reply this screen will send."
  def max_reply, do: @max_reply

  @doc "The voice a reply is written as."
  def source, do: @source

  @doc "The tenant the window belongs to."
  def tenant_id, do: PartyIdentity.tenant_id()

  @doc """
  The user this window's writes are filed as — the party's user.

  Reads do **not** name it; see `PartyIdentity` for why. This is the write identity, and
  it is the identity a reply is keyed on so the bot can find the party the turn belongs
  to.
  """
  def user_id, do: PartyIdentity.user_id()

  @doc """
  The body of the window question, asking for the story so far.

  Opt-in on the wire, so the consumers that do not want it are untouched — and a bot
  that does not know the field ignores it, which is why an answer without it is
  unreported rather than empty.
  """
  def context_payload, do: Map.put(PartyIdentity.read_identity(), "carry_history", true)

  @doc "The body of the party question."
  def state_payload(session_id),
    do: Map.put(PartyIdentity.read_identity(), "session_id", session_id)

  @doc "The body of a reply."
  def write_payload(session_id, text) do
    Map.merge(PartyIdentity.write_identity(), %{
      "session_id" => session_id,
      "content" => text,
      "category" => @category,
      "source" => @source
    })
  end

  # ── the window ──────────────────────────────────────────────────────────────

  @doc """
  What the window question came back as.

  `{:open_window, window}` carries what the bot actually sent: the session, its
  scene, its theme, the character the bot provisioned for whoever asked, and the
  turns. A field the bot did not send is `nil` here and is drawn as not reported —
  never as an empty sentence, and never as a zero.
  """
  @spec window(term()) ::
          {:open_window, map()} | {:no_window, String.t()} | {:unreported, String.t()}
  def window(%{"session_id" => session_id} = answer) when is_binary(session_id) do
    {:open_window,
     %{
       id: session_id,
       status: binary_or_nil(answer["session_status"]),
       scene: binary_or_nil(answer["scene_description"]),
       facts: facts(answer["scene_facts"]),
       times: times(answer["scene_facts_at"]),
       theme: theme(answer["theme"]),
       character: character(answer["character"]),
       narration: narration(answer),
       carry: carry(answer)
     }}
  end

  def window(%{"ok" => false} = answer) do
    case answer["error"] do
      @no_session ->
        {:no_window,
         "No window is open. Nothing has gathered, so there is nothing to say into yet."}

      reason ->
        {:unreported,
         "The bot refused the question about a window" <>
           said(reason) <> " — so this screen is not reporting one."}
    end
  end

  def window(_answer) do
    {:unreported, "The bot answered, but not with a window — nothing here is a reading of one."}
  end

  @doc """
  What the window says about the words that have not arrived yet.

  A party with a narrator hands the turn to her (`rpg.narration.your_turn`), and rpg
  reports the state of that hand-off on the same answer the window came in on — this
  is a *reading* of that field, not a third question:

    * `{:pending, bot_id, at}` — she was asked and nothing new has been written. `at`
      is when the ask was made, or `nil` when the bot did not say; the screen turns it
      into how long the words have been missing. The window is wordless on purpose,
      and the screen says that rather than drawing a sentence nobody wrote.
    * `{:answered, bot_id}` — a turn newer than the ask is signed with her name.
    * `{:no_ask, nil}` — the bot reports nobody was asked for a turn in what it read.
    * `{:unreported, sentence}` — the field is absent (`nil`), the shape is not one
      this screen can read, or the window question itself was refused. A bot that
      does not know the field answers here, and the screen does not turn that into
      *nobody was asked*, which is a claim about the party rather than about the bot.

  Only the ask *itself* is read, not who the party named: a window whose ask fell
  outside the read is `{:no_ask, nil}`, and the screen makes no claim about it either.

  There is no deadline in this reading and there cannot be one: rpg publishes the ask
  once and never awaits it, so the system has no opinion about when an answer is late.
  The elapsed time is honest about that — it says how long it has been, and never how
  long is left.
  """
  @spec narration(term()) ::
          {:pending, String.t(), String.t() | nil}
          | {:answered, String.t()}
          | {:no_ask, nil}
          | {:unreported, String.t()}
  def narration(%{"narration" => %{"asked_of" => bot_id, "pending" => pending} = reading})
      when is_binary(bot_id) and is_boolean(pending) do
    if pending,
      do: {:pending, bot_id, binary_or_nil(reading["asked_at"])},
      else: {:answered, bot_id}
  end

  def narration(%{"narration" => nil}), do: {:no_ask, nil}

  def narration(%{"ok" => false} = answer),
    do: {:unreported, "The bot did not answer with the window" <> said(answer["error"]) <> "."}

  def narration(%{"narration" => _other}),
    do: {:unreported, "The bot answered, but not with a reading of the words that are owed."}

  def narration(_answer),
    do:
      {:unreported,
       "The bot did not say whether a turn was handed to a narrator, so this screen is not saying either."}

  @doc """
  The line under the turns for whatever the window said about the words owed.

  `""` for a window that reports no ask: the turns are complete without it, and an
  extra line claiming nothing happened would be a line about nothing.
  """
  @spec narration_line(term()) :: String.t()
  def narration_line({:pending, bot_id, at}),
    do: "asked of #{bot_id}#{since(at)} — (she says nothing yet)"

  def narration_line({:answered, bot_id}),
    do: "#{bot_id} has written since she was asked — the words are among the turns above"

  def narration_line({:unreported, sentence}), do: sentence
  def narration_line({:no_ask, nil}), do: ""
  def narration_line(_answer), do: ""

  # ── the party ───────────────────────────────────────────────────────────────

  @doc """
  Who is in the window, from the session's joined characters.

  The party is the session's `character_ids`, a map of character to the bot that
  joined as it — a name the window can be read with, rather than a raw UUID. The
  in-memory `PartyStore` is deliberately not read: a party held in a process is not
  a fact that survives a restart, and a window gate has to be a fact (N+38).

    * `{:party, rows}` — the bot reported the field; an empty list means nobody has
      joined yet, and that is a reading
    * `{:unreported, sentence}` — the bot did not answer with a session, or did not
      carry the field at all. A missing field is not an empty party.
  """
  @spec party(term()) :: {:party, [map()]} | {:unreported, String.t()}
  def party(%{"character_ids" => ids}) when is_map(ids) do
    rows =
      ids
      |> Enum.map(fn {character_id, who} -> %{id: character_id, who: who} end)
      |> Enum.sort_by(&to_string(&1.who))

    {:party, rows}
  end

  def party(%{"ok" => false} = answer),
    do: {:unreported, "The bot did not answer with the party" <> said(answer["error"]) <> "."}

  def party(_answer),
    do: {:unreported, "The party was not in the answer — who is in the window is not reported."}

  @doc """
  Who the window says narrates it — the role, read from the window question.

  The bot names one member the party's narrator (`rpg.party.set_narrator`), and the
  role rides the party it already sends, so this is a reading of the same answer the
  window came in on rather than a third question.

    * `{:narrator, character_id}` — the bot reported a party and one member holds
      the role. The id is what is matched against a row; the row draws the badge.
    * `{:no_narrator, nil}` — the bot reported the party and nobody holds the role.
      A party nobody has joined yet is this answer too: nobody narrates it.
    * `{:unreported, sentence}` — the bot did not report the party (`nil`), did not
      carry the field at all, or refused the window question. The screen badges
      nobody, and says nothing about who narrates, which is not the same claim as
      *nobody narrates* — the badge makes no claim either way.

  A member the roster gave no character id for matches no row, so it badges nobody.
  """
  @spec narrator(term()) ::
          {:narrator, String.t()} | {:no_narrator, nil} | {:unreported, String.t()}
  def narrator(%{"party" => %{"members" => members}}) when is_list(members) do
    case Enum.find(members, &(&1["role"] == "narrator")) do
      %{"character_id" => character_id} when is_binary(character_id) -> {:narrator, character_id}
      _ -> {:no_narrator, nil}
    end
  end

  def narrator(%{"party" => party}) when is_map(party), do: {:no_narrator, nil}

  def narrator(%{"party" => nil}),
    do:
      {:unreported,
       "The bot did not report the party, so this screen is not saying who narrates."}

  def narrator(%{"ok" => false} = answer),
    do: {:unreported, "The bot did not answer with the party" <> said(answer["error"]) <> "."}

  def narrator(_answer),
    do:
      {:unreported, "The party was not in the answer — who narrates the window is not reported."}

  @doc """
  Whether this row is the member the party named as its narrator.

  `false` for every row when the role was unreported, so an unread roster badges
  nobody rather than badging the wrong bot.
  """
  @spec narrates?(term(), map()) :: boolean()
  def narrates?({:narrator, character_id}, %{id: id}), do: id == character_id
  def narrates?(_answer, _row), do: false

  @doc """
  The turns, oldest first — or `nil`, for a window whose turns were never reported.

  The bot sends the most recent facts first; a window reads the other way. An empty
  list and an unreported field are not the same answer: the window had nothing said
  in it, versus the bot did not say what had been said. `nil` is the second.

  Each turn is `%{text: line, at: stamp}`, where `at` is when that turn was written —
  or `nil` when the bot did not report a time for it. The two lists are matched by
  position, so a turn the bot did not stamp is drawn without a time rather than
  borrowing its neighbour's. A window from a bot that does not know the field at all
  gives every turn `nil` here, and the screen shows the words it always showed.
  """
  @spec turns(map()) :: [%{text: String.t(), at: String.t() | nil}] | nil
  def turns(%{facts: facts} = window) when is_list(facts) do
    stamps = times_of(window)

    # Paired in the bot's own order (newest first), then turned round together — pairing
    # after the reverse would slide a short list's stamps onto the wrong turns.
    facts
    |> Enum.with_index()
    |> Enum.map(fn {text, index} -> %{text: text, at: Enum.at(stamps, index)} end)
    |> Enum.reverse()
  end

  def turns(_window), do: nil

  @doc """
  How long ago something happened, as words — `"just now"`, `"4m ago"`, `"2d ago"`.

  The window never prints a clock hour: a house that reads "6 minutes ago" knows
  whether the party is warm, where a timestamp makes it do arithmetic at a glance.
  A time this screen cannot read is `nil`, not a guess — and the caller draws nothing
  rather than "unknown ago", which would be a claim about when rather than about the
  reading.

  A stamp that names no zone is read as UTC, because the bot stamps its scene facts
  with Ecto's `:naive_datetime`, which *is* UTC by the store's own definition
  (`Ecto.Schema.__timestamps__/1` autogenerates `NaiveDateTime.utc_now/0`) and which
  `NaiveDateTime.to_iso8601/1` therefore writes down with the zone trimmed off. That
  is reading the store's contract, not guessing at a timezone. It matters more than it
  looks: without it every real turn drew *no time at all*, and "no time" is the one
  reading this screen cannot tell apart from a bot that reported none — the failure was
  invisible until the live wire was read back (see the regression test).
  """
  @spec ago(String.t() | nil) :: String.t() | nil
  def ago(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, _then, _offset} -> BotArmyDashboardLiveview.BotHealth.format_heartbeat(at)
      {:error, :missing_offset} -> ago(at <> "Z")
      {:error, _reason} -> nil
    end
  end

  def ago(_at), do: nil

  @doc """
  The turns of the windows before this one, oldest first — or `nil` when the bot did
  not report them.

  An empty list means the bot looked and nothing came before; `nil` means the bot did
  not say, and the screen says that instead of *nothing came before*, which would be
  this screen's invention.
  """
  @spec history(map() | term()) :: [map()] | nil
  def history(%{carry: rows}) when is_list(rows), do: rows
  def history(_window), do: nil

  # ── a reply ─────────────────────────────────────────────────────────────────

  @doc """
  Send one reply into the window.

  Three outcomes, and the screen owns the first one: a draft this module knows is
  not a reply (`{:refused, sentence}`) never reaches the bot. An empty or
  whitespace-only draft is not a turn, and a draft past the ceiling is refused with
  the ceiling in the sentence rather than sent. `{:ok, :stored}` is the bot's
  acknowledgement and nothing more — this screen does not read it as confirmation.
  Confirmation is the re-read (`settle/2`).
  """
  @spec reply(String.t(), String.t() | nil) ::
          {:ok, :stored} | {:refused, String.t()} | {:error, String.t()}
  def reply(session_id, text) do
    case draft(text) do
      {:ok, text} -> send_reply(session_id, text)
      {:refused, sentence} -> {:refused, sentence}
    end
  end

  @doc """
  What to do with what the operator typed.

  Exposed so the screen can refuse a draft before it draws a confirmation card for
  it: a confirmation of nothing is a step that leads nowhere.
  """
  @spec draft(String.t() | nil) :: {:ok, String.t()} | {:refused, String.t()}
  def draft(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:refused, "There is nothing to say — an empty reply is not a turn."}

      String.length(trimmed) > @max_reply ->
        {:refused,
         "That reply is longer than a turn in this window can be (#{@max_reply} characters) — shorten it and send it."}

      true ->
        {:ok, trimmed}
    end
  end

  def draft(_text), do: {:refused, "There is nothing to say — an empty reply is not a turn."}

  defp send_reply(session_id, text) do
    case Broker.request(@write_subject, Jason.encode!(write_payload(session_id, text)),
           timeout: @request_timeout
         ) do
      {:ok, %{body: body}} -> decode_write(body)
      other -> {:error, trouble(other)}
    end
  end

  defp decode_write(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true}} ->
        {:ok, :stored}

      {:ok, %{"ok" => false} = refusal} ->
        {:error, "The bot refused the reply" <> said(refusal["error"]) <> "."}

      {:ok, _other} ->
        {:error, "The bot answered, but not with a turn — the reply may not have landed."}

      {:error, _reason} ->
        {:error,
         "The bot answered something this screen could not read — the reply may not have landed."}
    end
  end

  defp decode_write(_body),
    do:
      {:error,
       "The bot answered something this screen could not read — the reply may not have landed."}

  defp trouble(:no_broker), do: "The bot is not reachable right now — nothing was sent."
  defp trouble(:timeout), do: "The bot did not answer in time — the reply may not have landed."
  defp trouble({:error, _reason}), do: "The reply could not be sent — nothing was sent."
  defp trouble(_other), do: "The reply could not be sent — nothing was sent."

  # ── the sentence a reply act owns ───────────────────────────────────────────

  @doc """
  Reconcile a reply with a fresh read of the window.

  This is the confirmation, and it is not the write's own ok: the reply is in the
  window only if the window reads back with it among the turns. A read that does
  not carry it says so, and that sentence is the one the screen shows.
  """
  @spec settle(map() | nil, map() | nil) :: map() | nil
  def settle(nil, _window), do: nil

  # A refusal and a failed send have already been answered; a reading that lands
  # after them is news about the window, not about that reply.
  def settle(%{state: state} = act, _window) when state in [:refused, :error], do: act

  def settle(%{text: text} = act, %{facts: facts} = _window) when is_list(facts) do
    if text in facts do
      Map.put(act, :confirmed?, true)
    else
      act
      |> Map.put(:confirmed?, false)
      |> Map.put(:reading, "the window reads back without it")
    end
  end

  def settle(%{text: _text} = act, _window), do: act

  @doc "The sentence under the reply card."
  def line(%{state: :refused, sentence: sentence}), do: sentence
  def line(%{state: :error, sentence: sentence}), do: sentence

  def line(%{confirmed?: true}), do: "said into the window — it reads back with your reply in it."

  def line(%{reading: reading}),
    do: "sent — #{reading}, so this screen is not calling it said."

  def line(%{state: :sent}), do: "sent — reading the window back…"
  def line(%{state: :review}), do: "check it, then send it into the window."
  def line(_reply), do: ""

  @doc "A refusal and a failure are not readings; they must not be styled like one."
  def class(%{state: state}) when state in [:refused, :error], do: "unreported"
  def class(%{confirmed?: true}), do: "ok"
  def class(_reply), do: "dim"

  # ── readers ─────────────────────────────────────────────────────────────────

  defp theme(%{"setting" => setting} = theme) when is_binary(setting) do
    %{
      setting: setting,
      tone: binary_or_nil(theme["tone"]),
      mechanic: binary_or_nil(theme["mechanic"])
    }
  end

  defp theme(_theme), do: nil

  defp character(%{"name" => name} = character) when is_binary(name) do
    %{
      name: name,
      bot_id: binary_or_nil(character["bot_id"]),
      class: binary_or_nil(character["class"]),
      level: if(is_integer(character["level"]), do: character["level"], else: nil)
    }
  end

  defp character(_character), do: nil

  # A field the bot did not send is `nil`, not `[]`: "nothing has been said" and
  # "the bot did not say" are different sentences and the screen says which one it is.
  defp facts(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp facts(_other), do: nil

  # The time of each turn, in the same shape as `facts`: `nil` for a bot that did not
  # send the field at all, `[]` for one that sent it empty, and unreadable entries kept
  # as `nil` so the positions still line up. Dropping them would slide every later
  # turn's time onto the wrong line.
  defp times(list) when is_list(list), do: Enum.map(list, &binary_or_nil/1)
  defp times(_other), do: nil

  # The story so far, as the answer carried it. A window that was never reported, a
  # carry this bot could not read (`nil`) and a bot that does not know the field all
  # come back `nil` here, and the screen says the one true sentence for all three.
  defp carry(%{"carry_history" => rows}) when is_list(rows),
    do: rows |> Enum.map(&carry_row/1) |> Enum.reject(&is_nil/1)

  defp carry(_answer), do: nil

  # A row without a line is not a turn, and is not drawn as one.
  defp carry_row(%{"content" => text} = row) when is_binary(text),
    do: %{text: text, who: who(row["source"])}

  defp carry_row(_row), do: nil

  # Who spoke, naming the role. Both the operator and the maid are *she*, so a bare
  # pronoun in this spot would be a sentence with two possible subjects (§28).
  defp who(@source), do: "the operator"
  defp who("gm"), do: "the GM"
  defp who(other) when is_binary(other) and other != "", do: other
  defp who(_other), do: "someone the bot did not name"

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_value), do: nil

  # When the words went missing, said as a duration. Public because the turns list draws
  # it too: the window has one way of saying how long ago, not two.
  @doc """
  " · 4m ago" for a time, and `""` for one this screen cannot read or was not given.

  An empty string rather than "unknown ago": a turn with no time is drawn with no
  time, which is the truth about the reading rather than a claim about the clock.
  """
  @spec since(String.t() | nil) :: String.t()
  def since(nil), do: ""

  def since(at) do
    case ago(at) do
      nil -> ""
      phrase -> " · #{phrase}"
    end
  end

  # The window's turns newest-first, so `turns/1` can pair them with the words it has
  # just reversed. Kept private: the screen reads turns, not bare stamps.
  defp times_of(%{times: times}) when is_list(times), do: times
  defp times_of(_window), do: []

  @doc """
  The bot's own word for a refusal, said without guessing at what it means.

  A reason that is not a string is not echoed: an unreadable term is a thing this screen
  cannot repeat as if it were an answer. Public because the party is read from two screens
  now — this one and `BotArmyDashboardLiveview.PartySelect` — and the same refusal has to be
  said the same way on both, rather than each screen stripping the leading `:` for itself.
  """
  @spec said(term()) :: String.t()
  def said(reason) when is_binary(reason) do
    word = String.trim_leading(reason, ":")

    if word == "", do: "", else: " — #{word}"
  end

  def said(_reason), do: ""
end
