# Party & Banter System (Design)

**Status:** Design draft, not built. No routes, bots, or schemas exist yet — everything below is a proposal to be broken into phased work.

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

**Decided: `bot_army_companion` owns it.** It already owns narrative-adjacent state (`thoughts.ex`, `reflection_history.ex`) and is the closest existing thing to "the layer that turns bots into characters" — party/affinity/banter state (`party_selections`, `character_affinity`, `banter_turns`) is new tables inside companion's existing Ecto repo, not a new bot.

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
- `/party-select` — choose party before a task/quest
- `/party-banter` — check-in feed + reply box, scoped to the active/most-recent party

## Data model sketch (new state only)

```
party_selections
  task_id | quest_id, characters: [bot_id], selected_at

character_affinity
  bot_id, tasks_completed_together, level, unlocked_topics

banter_turns
  bot_id, speaker (character|player), text, task_ref, created_at
```

Lives in `bot_army_companion`'s Ecto repo (see "Boomerang continuity" above).

## Explicitly out of scope for v1

- Live/real-time chat (this is check-in-when-convenient, not a chat window)
- Affinity decay or negative banter from low affinity
- Voice/audio
- Cross-character banter (party members talking to each other, not just to the player) — interesting later, adds real complexity (whose turn, who initiates), not needed for the core loop

## Phasing suggestion

1. Party select screen + `party_selections` state (no banter yet — just prove the "who's with me" mechanic reads back correctly)
2. Banter generation on task-complete only (single trigger, not every state change) + check-in feed, no reply
3. Reply box + continuity thread (boomerang becomes possible)
4. Affinity/leveling + topic unlocks
