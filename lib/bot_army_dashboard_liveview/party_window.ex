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

  ## What a turn is, and who spoke it

  `scene_facts` arrives newest first (the bot sorts by `created_at desc` and takes
  its limit), so this module reverses it: a window reads as a conversation, oldest
  at the top. A reply is written as `source: "operator"` and `category: "dialogue"`
  — the dashboard is open and proves nothing about who is holding the phone, so the
  record says the operator spoke, which is what the shelf's verbs already say. It
  never says *she* said it.
  """

  alias BotArmyDashboardLiveview.Broker

  @context_subject "rpg.session.gather_context"
  @state_subject "rpg.session.state"
  @write_subject "rpg.scene.fact.add"
  @request_timeout 5_000

  # The identity the window is read and written as. The bot's deployment is
  # single-tenant and single-user: a session belongs to one `user_id` and this
  # dashboard has no auth to learn a different one from, so the default is named
  # once, here, and is overridable in config — rather than invented at each call
  # site, which is how a screen ends up asking about a user that does not exist.
  # Both are the runtime's `default_tenant_id/0`, which is the same UUID.
  @default_tenant_id "00000000-0000-0000-0000-000000000001"
  @default_user_id "00000000-0000-0000-0000-000000000001"

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
  def tenant_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_tenant_id, @default_tenant_id)

  @doc "The user whose window this is."
  def user_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_user_id, @default_user_id)

  @doc "The body of the window question."
  def context_payload, do: %{"tenant_id" => tenant_id(), "user_id" => user_id()}

  @doc "The body of the party question."
  def state_payload(session_id),
    do: %{"tenant_id" => tenant_id(), "session_id" => session_id}

  @doc "The body of a reply."
  def write_payload(session_id, text) do
    %{
      "tenant_id" => tenant_id(),
      "user_id" => user_id(),
      "session_id" => session_id,
      "content" => text,
      "category" => @category,
      "source" => @source
    }
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
       theme: theme(answer["theme"]),
       character: character(answer["character"])
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
  The turns, oldest first — or `nil`, for a window whose turns were never reported.

  The bot sends the most recent facts first; a window reads the other way. An empty
  list and an unreported field are not the same answer: the window had nothing said
  in it, versus the bot did not say what had been said. `nil` is the second.
  """
  @spec turns(map()) :: [String.t()] | nil
  def turns(%{facts: facts}) when is_list(facts), do: Enum.reverse(facts)
  def turns(_window), do: nil

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

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_value), do: nil

  # The bot's own word for a refusal, said without guessing at what it means. A
  # reason that is not a string is not echoed: an unreadable term is a thing this
  # screen cannot repeat as if it were an answer.
  defp said(reason) when is_binary(reason) do
    word = String.trim_leading(reason, ":")

    if word == "", do: "", else: " — #{word}"
  end

  defp said(_reason), do: ""
end
