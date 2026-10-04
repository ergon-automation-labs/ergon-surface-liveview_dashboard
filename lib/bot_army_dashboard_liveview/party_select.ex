defmodule BotArmyDashboardLiveview.PartySelect do
  @moduledoc """
  Building the party from the phone: who is with her, who could be, and who writes the turns.

  ## The party was on the wire with nothing to build it with

  `bot_army_rpg` has kept parties since before this dashboard existed — `rpg_party_members`
  is the durable party, `rpg.party.add` recruits into it, `rpg.party.set_narrator` names who
  writes the turns — and no screen here could reach any of it. `/party-phone` reads the
  *window*, and a window is opened by a session that has a party; with no party there is no
  window, and the screen correctly said so and offered nothing to do about it. A screen that
  can show the party and cannot make one is a dead end, which is what this module removes.

  ## One party, not a second table

  The design draft for banter (`docs/PARTY_BANTER_DESIGN.md`) proposed a `party_selections`
  table for the dashboard to keep the party in. The party already exists, in this bot, on
  these routes; a second table would be a second answer to *who is with her*, and the two
  would disagree the first time someone recruited from one of them. Nothing here writes a
  table: it asks the routes that own the party.

  ## The identity is named here, and only here

  The party routes **require** a user and refuse without one (`:missing_user_id`), unlike the
  window routes, which resolve a session the fleet opens with no user on it. So this screen
  names one — the same literal `/quest-status` sends — and the bot resolves it through
  `BotArmyRpg.Identity.resolve_user_id/2`, the same call `rpg.session.*` makes, so `"abby"`
  here is the same person as `"abby"` in the window this party belongs to. A screen that named
  nobody could read the party and never build one, which is the dead end again.

  The **roster** is the opposite case and is asked with no user at all: `rpg.character.list`
  filters by the user it resolves when a caller names one, and every character the fleet
  auto-provisions carries `user_id: nil` — naming the party's user would answer *no
  characters* for a tenant that has several, and every candidate would vanish behind a
  filter nobody asked for. Measured against the live bot: three characters, each with
  `user_id` null.

  ## Three answers to every read

  Same law as every other read in this suite: the bot reported it, the bot refused it, or the
  question never came back. A party nobody could read is **not** an empty party — the second
  says *nobody is with her* about a party nobody looked at — and a roster nobody could read is
  not *no bot has a character*.

  A party that does not exist yet is its own case, and the bot says so itself: it answers the
  blank party with a `message` naming the way out. That sentence is drawn as the bot's, rather
  than this screen inventing a second one for the same fact.

  ## A structural write is two presses, confirmed by the re-read

  Recruiting, dismissing and naming the narrator all change who is with her, so none of them
  happens on a stray tap: each is picked, then confirmed, then sent. `{:ok, :stored}` is the
  bot's acknowledgement and nothing else — the confirmation is the re-read, settled against
  the fresh party (`settle/2`), because *the bot said yes* is the one claim a write can make
  that is not about the party. A write that failed is reported and never retried: the operator
  decides, and the party is read back either way.

  ## Recruiting by id is a real capability, not a workaround

  `rpg.party.add` resolves a bot id through `CharacterProvisioning.ensure_bot_character/2`, so
  a bot that has no character yet *gets one*. That is why the screen offers the roster **and**
  a box to name a bot id: the roster is what the bot already knows, and the box is everything
  else it can make.

  ## Who narrates has one owner

  The rule "the member whose role is `narrator`" is `BotArmyDashboardLiveview.PartyWindow`'s
  (`narrator/1`), because the window screen draws the same badge from the same answer. This
  module **delegates** rather than re-reading the rule out of the rows it drew — two owners of
  one rule is how a badge and a line start disagreeing (N+56).
  """

  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.PartyWindow

  @get_subject "rpg.party.get"
  @add_subject "rpg.party.add"
  @remove_subject "rpg.party.remove"
  @narrator_subject "rpg.party.set_narrator"
  @roster_subject "rpg.character.list"

  @request_timeout 5_000

  # The identity the party is read and written as. The bot's deployment is single-tenant and
  # this dashboard has no auth to learn a different tenant from, so it is named once here and
  # is overridable in config — the same two keys `PartyWindow` uses for its tenant.
  @default_tenant_id "00000000-0000-0000-0000-000000000001"

  # The user the party belongs to; see the module doc for why a user is named here and not on
  # the window's reads. Overridable, because a second operator is a configuration rather than
  # a code change.
  @default_user_id "abby"

  # A bot id longer than this is a typo rather than a bot, and it is refused here with the
  # ceiling in the refusal instead of sent and refused by the bot.
  @max_bot_id 64

  @doc "The subject the party is read on."
  def party_subject, do: @get_subject

  @doc "The subject the tenant's characters are read on."
  def roster_subject, do: @roster_subject

  @doc "The subject a companion is recruited on."
  def add_subject, do: @add_subject

  @doc "The subject a companion is taken out on."
  def remove_subject, do: @remove_subject

  @doc "The subject the narrator is named on (`null` clears the role)."
  def narrator_subject, do: @narrator_subject

  @doc "The longest bot id this screen will send."
  def max_bot_id, do: @max_bot_id

  @doc "The tenant the party belongs to."
  def tenant_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_tenant_id, @default_tenant_id)

  @doc "The user whose party this is — see the module doc for why one is named here."
  def user_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_select_user_id, @default_user_id)

  @doc "The body of the party question."
  def party_payload, do: identity()

  @doc """
  The body of the roster question: the tenant, and **no** user named.

  See the module doc: naming the party's user here would filter the roster down to the
  characters that user owns, and the fleet's characters are owned by nobody.
  """
  def roster_payload, do: %{"tenant_id" => tenant_id()}

  @doc "The body of a recruit: the bot whose character joins the party."
  def add_payload(bot_id), do: Map.put(identity(), "bot_id", bot_id)

  @doc "The body of a dismissal: the character to take out of the party."
  def remove_payload(character_id), do: Map.put(identity(), "character_id", character_id)

  @doc """
  The body of naming the narrator — `nil` clears the role.

  The key is always present, because to the bot an absent `character_id` and an explicit
  `null` are different requests: the first is a caller who forgot to name anyone and is
  refused (`:missing_character_id`), the second is how the role is cleared.
  """
  def narrator_payload(character_id), do: Map.put(identity(), "character_id", character_id)

  defp identity, do: %{"tenant_id" => tenant_id(), "user_id" => user_id()}

  # ── the party ───────────────────────────────────────────────────────────────

  @doc """
  The party, read from the bot.

  `{:party, party}` carries four things and each is used for one job: `members` are the rows
  this screen draws, `name` is the party's own name, `message` is the bot's own sentence when
  it sent one (the blank party carries the way out), and `raw` is the answer itself — kept
  because who narrates is a rule with one owner (`PartyWindow`, which reads the bot's party
  shape) and this module would be the second place to decide it if it re-derived the answer
  from the rows it drew.

  `{:unreported, sentence}` is a question that did not come back as a party, including a
  refusal, whose own word is carried. A party nobody could read is not an empty party.
  """
  @spec party(term()) :: {:party, map()} | {:unreported, String.t()}
  def party(%{"members" => members} = raw) when is_list(members) do
    {:party,
     %{
       name: binary_or_nil(raw["name"]),
       members: members |> Enum.map(&member/1) |> Enum.reject(&is_nil/1),
       message: binary_or_nil(raw["message"]),
       raw: raw
     }}
  end

  def party(%{"ok" => false} = answer),
    do:
      {:unreported,
       "The bot refused the question about the party" <> PartyWindow.said(answer["error"]) <> "."}

  def party(_answer),
    do: {:unreported, "The party was not in the answer — who is with her is not reported."}

  @doc """
  The tenant's characters: who the bot could bring into the party.

  The answer is the list of characters themselves, so a map is not a roster of none — it is a
  question that did not come back, and it is said that way rather than drawn as an empty list.

  A character the bot sent no `bot id` for is not a candidate and is left out: `rpg.party.add`
  recruits a **bot**, so a row this screen cannot name one for could not be acted on.
  """
  @spec roster(term()) :: {:roster, [map()]} | {:unreported, String.t()}
  def roster(characters) when is_list(characters) do
    {:roster, characters |> Enum.map(&candidate/1) |> Enum.reject(&is_nil/1)}
  end

  def roster(%{"ok" => false} = answer),
    do:
      {:unreported,
       "The bot refused to list the characters it has" <> PartyWindow.said(answer["error"]) <> "."}

  def roster(_answer),
    do:
      {:unreported,
       "The bot did not answer with a list of characters — who could join is not reported."}

  @doc """
  Who could join: the roster, minus the characters already with her.

  A character is already with her when the party has a member of the same **bot** —
  `rpg.party.add` resolves a bot to its one character and the store refuses a second member
  with the same character id, so a bot already in the party cannot be recruited twice. A
  roster row with no bot id falls back to its character id, which is what the party keys
  membership on.

  `nil` is "not yet": the characters are still being read. A list needs both readings,
  because with the party unread what is already with her is not known and a list built anyway
  would offer her companions she already has — offering nobody is a smaller lie than
  offering someone already in the party.
  """
  @spec candidates(term(), term()) :: {:candidates, [map()]} | {:unreported, String.t()} | nil
  def candidates({:roster, rows}, {:party, party}),
    do: {:candidates, Enum.reject(rows, &with_her?(&1, party.members))}

  def candidates({:unreported, sentence}, _party), do: {:unreported, sentence}

  # Still being read — or never came back as a roster at all. Nothing is known about who
  # could join, and that is not the same fact as there being nobody.
  def candidates(nil, _party), do: nil

  def candidates(_roster, _party),
    do:
      {:unreported,
       "The party has not been read, so this screen is not offering anyone she may already have."}

  @doc """
  Who narrates the party.

  Delegated to `BotArmyDashboardLiveview.PartyWindow.narrator/1`, which is the one owner of
  the rule and reads the bot's own party shape; the answer is wrapped in the shape that
  module reads so both screens ask one question and get one answer. An unread party is
  `{:unreported, sentence}` — the same three answers as everywhere else, and never the claim
  that nobody narrates.
  """
  @spec narrator(term()) ::
          {:narrator, String.t()} | {:no_narrator, nil} | {:unreported, String.t()}
  def narrator({:party, %{raw: raw}}), do: PartyWindow.narrator(%{"party" => raw})

  def narrator({:unreported, sentence}), do: {:unreported, sentence}

  def narrator(nil),
    do: {:unreported, "The party has not been read, so this screen is not saying who narrates."}

  # ── one act on the party ─────────────────────────────────────────────────────

  @doc """
  Do one thing to the party: recruit, dismiss, name the narrator, or clear the role.

  One press, one write, no retry. `{:ok, :stored}` is the bot's acknowledgement and nothing
  more; the confirmation is the re-read (`settle/2`). A draft this module already knows the
  bot cannot act on never leaves the phone (`{:refused, sentence}`), so a failure here is a
  failure the operator can fix rather than a round trip.
  """
  @spec act(atom(), term()) :: {:ok, :stored} | {:refused, String.t()} | {:error, String.t()}
  def act(verb, target) do
    case draft(verb, target) do
      {:ok, {subject, payload, what}} -> send_act(subject, payload, what)
      {:refused, sentence} -> {:refused, sentence}
    end
  end

  @doc """
  What to do with the thing the operator picked, before a confirmation is drawn for it.

  Exposed so the screen refuses what it knows the bot cannot act on — an empty bot id, a
  member row the bot sent no character id for — **before** it draws a confirmation card: a
  confirmation of nothing is a step that leads nowhere.
  """
  @spec draft(atom(), term()) :: {:ok, {String.t(), map(), String.t()}} | {:refused, String.t()}
  def draft(:recruit, bot_id) when is_binary(bot_id) do
    id = String.trim(bot_id)

    cond do
      id == "" ->
        {:refused, "There is no bot to recruit — an empty id is not a bot."}

      String.length(id) > @max_bot_id ->
        {:refused,
         "That is longer than a bot id can be (#{@max_bot_id} characters) — check it and try again."}

      true ->
        {:ok, {@add_subject, add_payload(id), "recruit #{id}"}}
    end
  end

  def draft(:recruit, _bot_id),
    do: {:refused, "There is no bot to recruit — an empty id is not a bot."}

  def draft(:dismiss, character_id) when is_binary(character_id) and character_id != "",
    do: {:ok, {@remove_subject, remove_payload(character_id), "take that companion out"}}

  def draft(:dismiss, _character_id),
    do: {:refused, "That row has no character id, so the bot cannot be asked to take it out."}

  def draft(:narrator, character_id) when is_binary(character_id) and character_id != "",
    do: {:ok, {@narrator_subject, narrator_payload(character_id), "name that narrator"}}

  def draft(:narrator, _character_id),
    do: {:refused, "That row has no character id, so the bot cannot be asked to name it."}

  def draft(:clear, _target),
    do: {:ok, {@narrator_subject, narrator_payload(nil), "clear the narrator"}}

  def draft(_verb, _target), do: {:refused, "There is nothing to do to the party."}

  defp send_act(subject, payload, what) do
    case Broker.request(subject, Jason.encode!(payload), timeout: @request_timeout) do
      {:ok, %{body: body}} -> decode_write(body, what)
      other -> {:error, trouble(other)}
    end
  end

  defp decode_write(body, what) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true}} ->
        {:ok, :stored}

      {:ok, %{"ok" => false} = refusal} ->
        {:error, "The bot refused to #{what}" <> PartyWindow.said(refusal["error"]) <> "."}

      {:ok, _other} ->
        {:error, "The bot answered, but not with the party — #{what} may not have landed."}

      {:error, _reason} ->
        {:error,
         "The bot answered something this screen could not read — #{what} may not have landed."}
    end
  end

  defp decode_write(_body, what),
    do:
      {:error,
       "The bot answered something this screen could not read — #{what} may not have landed."}

  defp trouble(:no_broker), do: "The bot is not reachable right now — nothing was sent."
  defp trouble(:timeout), do: "The bot did not answer in time — nothing may have changed."

  defp trouble(_other),
    do: "The bot was not asked — the party did not change."

  @doc """
  Reconcile an act with a fresh read of the party. This is the confirmation.

  The bot's own ok is not the party; the re-read is. A recruit has landed when that bot is
  among the members, a dismissal when their character is gone, naming the narrator when the
  role is theirs, and clearing it when nobody holds it. A read that did not come back says so,
  and that sentence is the one the screen shows.

  An act nobody sent yet (`:review`) and an act already answered (`:refused`, `:error`) are
  left alone: a reading that lands after them is news about the party, not about that act.
  """
  @spec settle(map() | nil, term()) :: map() | nil
  def settle(nil, _party), do: nil
  def settle(%{state: state} = act, _party) when state in [:refused, :error, :review], do: act

  def settle(%{state: :sent} = act, {:party, party}) do
    if landed?(act, party) do
      Map.put(act, :confirmed?, true)
    else
      act
      |> Map.put(:confirmed?, false)
      |> Map.put(:reading, "the party reads back without it")
    end
  end

  def settle(%{state: :sent} = act, _party),
    do: Map.put(act, :reading, "the party did not read back")

  @doc "The question the confirmation card asks, in the words of the thing being done."
  def ask(%{verb: :recruit, label: label}), do: "Add #{label} to the party?"
  def ask(%{verb: :dismiss, label: label}), do: "Take #{label} out of the party?"
  def ask(%{verb: :narrator, label: label}), do: "Let #{label} write the turns from now on?"
  def ask(%{verb: :clear}), do: "Let the bot write the turns itself again?"
  def ask(_act), do: "Do this to the party?"

  @doc "The sentence under the action card."
  def line(%{state: :refused, sentence: sentence}), do: sentence
  def line(%{state: :error, sentence: sentence}), do: sentence
  def line(%{confirmed?: true} = act), do: landed_line(act)

  def line(%{reading: reading, label: label}),
    do: "#{label} — sent, but #{reading}, so this screen is not calling it done."

  def line(%{state: :sent, label: label}), do: "#{label} — sent, reading the party back…"
  def line(%{state: :review}), do: "check it, then do it."
  def line(_act), do: ""

  @doc "A refusal and a failure are not readings; they must not be styled like one."
  def class(%{state: state}) when state in [:refused, :error], do: "unreported"
  def class(%{confirmed?: true}), do: "ok"
  def class(_act), do: "dim"

  # ── what landed ─────────────────────────────────────────────────────────────

  defp landed?(%{verb: :recruit, target: bot_id}, %{members: members}),
    do: Enum.any?(members, &(&1.bot_id == bot_id))

  # A dismissal has landed when the row is *gone* from a party that was read — the reading is
  # the fresh party, not an absence of an answer.
  defp landed?(%{verb: :dismiss, target: character_id}, %{members: members}),
    do: not Enum.any?(members, &(&1.id == character_id))

  defp landed?(%{verb: :narrator, target: character_id}, party),
    do: narrator({:party, party}) == {:narrator, character_id}

  defp landed?(%{verb: :clear}, party), do: narrator({:party, party}) == {:no_narrator, nil}
  defp landed?(_act, _party), do: false

  defp landed_line(%{verb: :recruit, label: label}),
    do: "#{label} is with her — the party reads back with them in it."

  defp landed_line(%{verb: :dismiss, label: label}),
    do: "#{label} is out — the party reads back without them."

  defp landed_line(%{verb: :narrator, label: label}),
    do: "#{label} writes the turns now — the party reads back with the role on them."

  defp landed_line(%{verb: :clear}),
    do: "the bot writes the turns again — the party reads back with nobody holding the role."

  defp landed_line(_act), do: "the party reads back with the change."

  # ── readers ─────────────────────────────────────────────────────────────────

  # A member the bot could not describe is kept, not dropped: the bot keeps them too, and a
  # party of four reported as a party of three is a reading nobody took. What is dropped is a
  # row that is not a row at all.
  defp member(member) when is_map(member) do
    %{
      id: binary_or_nil(member["character_id"]),
      who: who(member),
      bot_id: binary_or_nil(member["bot_id"]),
      class: binary_or_nil(member["class"]),
      level: integer_or_nil(member["level"])
    }
  end

  defp member(_member), do: nil

  defp who(member) do
    binary_or_nil(member["name"]) || binary_or_nil(member["bot_id"]) ||
      "someone the bot did not name"
  end

  defp candidate(%{"bot_id" => bot_id} = character) when is_binary(bot_id) and bot_id != "" do
    %{
      bot_id: bot_id,
      id: binary_or_nil(character["id"]),
      name: binary_or_nil(character["name"]) || bot_id,
      class: binary_or_nil(character["class"]),
      level: integer_or_nil(character["level"])
    }
  end

  defp candidate(_character), do: nil

  defp with_her?(%{bot_id: bot_id}, members) when is_binary(bot_id),
    do: Enum.any?(members, &(&1.bot_id == bot_id))

  defp with_her?(%{id: id}, members) when is_binary(id),
    do: Enum.any?(members, &(&1.id == id))

  defp with_her?(_candidate, _members), do: false

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_value), do: nil

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_value), do: nil
end
