# Party & Banter System (Design)

**Status:** Partly built. The party itself is **built and live**; the banter/affinity half is still a design draft.

**Correction (2026-10-04).** This draft proposed a new `party_selections` table inside `bot_army_companion`
and a `/party-select` screen. Both are wrong in the light of what was already there:

* **The durable party already exists** — `rpg_party_members` in `bot_army_rpg`, reached by
  `rpg.party.get` / `.add` / `.remove` / `.set_narrator`. It is the one owner of who is with her,
  and it already carries `role` (`narrator` | `companion`), `joined_at`, and the member's name/class/
  level. **No `party_selections` table is needed or wanted**; a second table would be a second answer
  to "who is with her," and the two would drift.
* **The screen exists** — `/party-select-phone` (`PartySelectPhoneLive`), reached from `/party-phone`.
  There is deliberately **no 16th navigation entry**: the window screen is where the party is used,
  so it is where the party is built.
* **`/party-phone` is the banter/window surface** — `PartyPhoneLive` already reads the party, the
  narrator, the session, the history, and writes a reply through `rpg.*`, with a subscription to
  `dashboard:party`. **The window is the chat; the session is the window.** Nothing in this draft's
  "reply box" section needs a new route.
* **What is genuinely unbuilt** — `character_affinity`, `banter_turns`, generation triggers, and the
  boomerang queries. Those remain proposals. `bot_army_companion`'s `party_narrator.ex` is the far end
  that already exists for narration.

The rest of this document is otherwise still the design of record for the banter half; read the data
model and phasing below through the correction above.

## Built: `/party-select-phone`

The screen is a **two-read, two-press** screen, and each half of that is a rule:

* **Two reads.** `mount/3` asks two independent questions — `rpg.party.get`
  (`{tenant_id, user_id}`) and `rpg.character.list` (`{tenant_id}` only, so it returns every
  character the tenant has, including the ones no user is bound to). A failure belongs to the read
  that failed: the top block reports it and names which question it was, and the other card still
  draws. A party nobody could read is a refusal, and the characters read anyway.
* **Two presses.** Picking a companion draws a confirmation that names what will be sent (`Add The
  Lorekeeper to the party, and put them in the window if one is open?`) and sends nothing; the second
  press sends it. **The confirmation is the re-read, not the write's `ok`** — `rpg.party.add`
  acknowledging the write proves only that the bot received it, so the act stays `:sent` until the
  re-read shows the member (`… is with her — the party reads back with them in it.`), and a write
  that lands without changing the party is never called done (`… sent, but the party reads back
  without it, so this screen is not calling it done.`).
* **A recruit is two facts, so it is two writes.** The durable party is `rpg.party.add`, but
  **the window draws its people from the session's `character_ids`**, which a recruit never touches —
  so a companion who is in the party can still be in no window. After a recruit that actually went
  out, the screen asks `rpg.session.gather_context` for the open window and, if there is one, joins
  the bot into it (`rpg.session.join` with `{tenant_id, session_id, bot_id}`) and reads the window's
  own party back (`rpg.session.state`) — the join's `ok` is an acknowledgement, exactly like every
  other write here. With no window open, nothing is joined and the screen says so rather than
  inventing a window to put the companion in.
* **This screen's reads name the tenant and no user.** Live sessions carry `user_id: nil`, and
  `Sessions.active_for/2` filters on the user, so a window read that named one would find nothing.
  The party routes are the other way round — they refuse a call with no `user_id` — so `PartyIdentity`
  is the one owner of both shapes: reads name the tenant only, writes name the party user.
* **A failure of this screen's own errand is this act's, not the page's.** `ReadHooks`' page-wide
  `:read_failed` halter is attached in `on_mount`, and LiveView runs `handle_info` hooks in attachment
  order (0.20.17), so a hook attached in `mount/3` can never intercept it. Instead `ReadHooks.report/3`
  offers each screen a chance to claim a failed read of its own through `claim_read_failure/3`;
  `{:claimed, socket}` wins and `:default` falls through to the same page-wide report as before — so
  no view can forget one, and none is required to mention `:read_failed`. Here that is what lets a
  window question that did not come back be said on the recruit card instead of blanking the page.
* **What it refuses here** — an empty bot id, a `user_id` the bot cannot key a party on, and a
  character the party already has. A confirmation card for something the bot cannot act on is a step
  leading nowhere.
* **The narrator is a `character_id`, not a bot id** — `rpg.party.set_narrator` takes a character, so
  the screen never prints a UUID at her; it names the companion that character belongs to.
* **No live subscription.** There is no `dashboard:party` subscription here; the party is written by
  this screen and read back by it, so a manual *Read it again* is the whole freshness story. (The
  window screen `/party-phone` does subscribe — it is the surface where someone else's party changes
  matter.)

## Overview

Nova already reframes tasks/projects as quests and gives them a narrator character. This extends that frame with a party mechanic borrowed from party-based RPGs (Dragon Age Inquisition companion banter, JRPG support ranks):

- **Party selection** — before starting a task or heading out, the player picks which bot-characters are "with them."
- **Ambient banter** — the chosen party generates short, in-character side-chat while the task/travel is in progress, checked in on whenever the player has a moment (not pushed as an interruption).
- **Boomerang stories** — banter has continuity. A character can bring up something from three days ago, the way ADHD recall loops back to unfinished threads. This is the mechanic that makes party members feel like a person, not a quote generator.
- **Reply** — the player can write back, companion-chat.sh-style, and the reply feeds the character's continuity thread.
- **Affinity/leveling** — each bot-character tracks a relationship level with the player character (working name: "the maid," i.e. the cottage protagonist) that rises with completed tasks together. Higher affinity unlocks new banter topics/avenues, not new mechanical power — this is a relationship system, not a stat system.
- **The baddie** — the overarching project being worked toward, framed as the antagonist arc the party is united against. (Already implied by quest=project mapping; this doc doesn't change that, just names it explicitly as a framing device for banter content — "we're still up against X.")

## Why this fits the existing design lens

- **Shame-free**: affinity only goes up (completed tasks), never down. No decay, no "they're mad at you for skipping."
- **Nudge, never nag**: banter is pulled (checked when convenient), not pushed as a notification that demands attention.
- **Protect hyperfocus**: banter generation is triggered by task-state-change events already flowing through the system (start/complete/travel), not a timer — so it never fires mid-focus.
- **Externalize, don't rely on recall**: the boomerang mechanic is the system remembering so the player doesn't have to — a callback is generated for the player, not expected of them.

## Core loop

1. Player is about to start a task/quest → **party select** screen: choose 1-3 bot-characters for this task.
2. Task runs. On task-state-change events (start, checkpoint, complete — reusing what already flows through `nats_bridge.ex`), the chosen party has a chance to generate a banter line as an **async LLM job**, not a blocking call.
3. Player checks the banter feed whenever they have a moment (existing "check in" pattern from `quest-status`/`habit-anchors`) — sees new lines, can scroll history, can reply.
4. A reply is appended to that character's continuity thread and optionally triggers a follow-up job.
5. On quest/task completion, affinity for the party members who were present increments. Crossing a threshold can unlock a new banter *topic* (a tag fed into the generation prompt), not a new UI.

## Banter generation

**Model:** local uncensored model via the existing Ollama-first fallback chain in `bot_army_llm` — free, local, no per-call cost, matches CLAUDE.md's note that "an uncensored local 27B can take a minute+."

**Pattern:** reuse the existing async job contract verbatim rather than inventing a new one:

```
llm.request.chat  {"async": true, ...}  -> {"job_id", "status": "accepted"}
llm.job.status    {"job_id"}            -> {"ok", "status", "result", "error", "timestamp"}
```

This is exactly the pattern already documented for `bridge.chat` / `bridge-query.sh` and for pi-go long generations — no new bot-to-bot contract needed, just a new caller.

**Trigger, not poll-loop:** a banter job is kicked off on a task-state-change event — the same `events.gtd.task.*` events `nats_bridge.ex` already subscribes to and broadcasts over PubSub — not on a timer. The LiveView starts the job and stores the `job_id`; the next time the player opens the banter view, it polls `llm.job.status` once and renders whatever's ready. This keeps it opt-in-to-check, not push-driven.

**Prompt shape:** short, in-character, capped token count (this is side-chat, not a chapter) — a system prompt per character (in the same spirit as `companion-chat.sh`'s persona file) plus:
- the task/quest context that triggered it
- the character's current affinity level (unlocks topic tags)
- the last N turns of that character's continuity thread — gives the line its *voice* (tone, running jokes the character itself originated)
- real task/quest history for the player (recently resumed/reopened items, patterns) — gives a boomerang line something *true* to reference, see "Boomerang continuity" below

## Boomerang continuity

Each bot-character needs a short rolling memory distinct from its production log data — not the bot's real operational history, its *narrative* voice history. Practically: a small table of `{character, turn_text, speaker (character|player), created_at, task_ref}` per character, capped to the last N turns (e.g. 20) fed back into the prompt. This is new state — nothing existing tracks it. Old turns age out; the "boomerang" is the model choosing to reference something still in that window, not a permanent story graph.

**Decided: boomerang pulls real task history, not just turn memory.** The point isn't that the character remembers its own last banter line — it's that the callback draws on the player's actual recurring patterns (a task she keeps circling back to, a project she actually returned to or finished), so the moment lands as self-recognition. "The bots are a reflection of me" means the reflection has to be of real behavior, not of the character's own prior chat output.

Concretely: the boomerang prompt pulls from the player's real record, not only the `banter_turns` table. `banter_turns` still exists (it's what makes a character's *voice* consistent turn to turn — tone, inside jokes it originated), but it is not the source of what gets called back to. Real record means more than tasks:

- task/quest history via `bridge.task.list` / `bridge.quest.current` — a task reopened after sitting stale, a project resumed after a gap
- **interaction history beyond tasks** — reflections captured (`events.reflection.captured`), companion observations/thoughts (`bot_army_companion`'s existing `thoughts.ex`/`reflection_history.ex`), habit check-ins — the things she actually said or noted, not just what she checked off. This is the difference between "you finished this project" and "you said three weeks ago you were dreading this, and here you are" — the second is what makes a callback feel witnessed rather than logged.

That means boomerang generation needs a lightweight query across both real task/quest history and real reflection/observation history (e.g. "tasks touched >N days apart," "same project resumed," "a reflection that mentioned this project before") feeding the prompt alongside the character's own recent turns — the turns give it voice, the real record gives it something true to say.

**Decided: `bot_army_companion` owns it.** It already owns narrative-adjacent state (`thoughts.ex`, `reflection_history.ex`) and is the closest existing thing to "the layer that turns bots into characters" — **banter** state (`banter_turns`, `character_affinity`) is new tables inside companion's existing Ecto repo, not a new bot. **Party membership is not part of this**: it already lives in `bot_army_rpg`'s `rpg_party_members` and is read, never duplicated (see the correction at the top).

## Affinity/leveling

Per bot-character, per player:
- `tasks_completed_together: integer` — increments on quest/task completion where that character was in the selected party
- `level`: derived from thresholds (e.g. 0-4 tasks = level 1, 5-14 = level 2, ...) — exact curve is a tuning decision, not a design blocker
- `unlocked_topics: [string]` — topic tags available to the prompt once a level is crossed

This is a **relationship system, not a stat/power system** — leveling never changes task outcomes, only what a character is willing to bring up in banter. That keeps it inside the shame-free lens: nothing punishes low affinity, it just means quieter small talk.

## Reply box

A textarea + submit, same shape as `ReflectionLive` (`phx-change` bound text, one submit action, `Gnat.pub`/publish on submit, brief confirmation toast, clear on send). Difference from reflection: the payload targets a specific character's continuity thread and can chain into a follow-up async job rather than being a terminal write.

## New surfaces (routes)

Following the existing `*-handheld` / `*-phone` pairing (`timer-handheld`/`timer-phone`, etc.):
- `/party-select-phone` — choose who is with her — **built** (writes `rpg.party.*`; `/party-phone` is its
  front door and there is no separate nav entry)
- `/party-phone` — the window: the party, the narrator, the session, the history, the reply box — **built**
- `/party-banter` — the check-in feed as its own screen — **not built**; today the banter lives in the
  window, and a separate feed would need a reason beyond this draft

## Data model sketch (new state only)

```
rpg_party_members            (BOT_ARMY_RPG — already built and live)
  user_id, tenant_id, character_id, role (narrator|companion), joined_at

character_affinity           (proposed — companion)
  bot_id, tasks_completed_together, level, unlocked_topics

banter_turns                 (proposed — companion)
  bot_id, speaker (character|player), text, task_ref, created_at
```

There is deliberately **no `party_selections`**: `rpg_party_members` is the party, and it is not
per-task (the window/session is the scope — see the correction at the top). The two proposed tables
live in `bot_army_companion`'s Ecto repo.

## Explicitly out of scope for v1

- Live/real-time chat (this is check-in-when-convenient, not a chat window)
- Affinity decay or negative banter from low affinity
- Voice/audio
- Cross-character banter (party members talking to each other, not just to the player) — interesting later, adds real complexity (whose turn, who initiates), not needed for the core loop

## Phasing suggestion

1. Party select screen + the party state — **done**: `/party-select-phone` over `rpg_party_members`
2. Banter generation on task-complete only (single trigger, not every state change) + check-in feed, no reply
3. Reply box + continuity thread (boomerang becomes possible) — the reply half is **done** in `/party-phone`;
   the continuity thread (`banter_turns`) is not
4. Affinity/leveling + topic unlocks
