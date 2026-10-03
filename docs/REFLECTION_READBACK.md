# The read-back lanes: reflections and the tavern window

Two phone screens used to write and then claim success without ever reading:

- **`/reflect-phone`** and **`/reflection`** published `events.reflection.captured`
  on the broker's `:ok` and printed "✓ Reflection captured. The story continues."
  The broker accepting bytes says nothing about whether the store kept them. A
  store that refused, or a companion that never answered, looked exactly like a
  store that worked — and the words she had just typed were the only place the
  reflection existed.
- **`/party-phone`** closed its window on the write's own ok, so a dropped scene
  event meant a window that never opened, with nothing on screen to say so.

Both lanes now read. The bot side did not change: the companion and `bot_army_rpg`
already serve every subject used here.

## The shape

Interpretation lives in one pure module per lane — `ReflectionWindow` (mirroring
`PartyWindow`) — and the LiveViews only carry assigns. That is what makes the
rules below testable without a broker.

| Lane | Subject | Direction |
|------|---------|-----------|
| reflections | `companion.reflections.capture` | the write (a request, never a publish) |
| reflections | `companion.reflections.list` | the recent list (read at mount, re-read on the cadence) |
| reflections | `companion.reflections.read` | one row by id (the diff after a write) |
| reflections | `events.llm.job.completed` → `dashboard:reflections` | the bell: a job ended |
| tavern | `events.rpg.>` → `dashboard:party` | the bell: the scene moved |

Bells carry **ids only — never the words**. They are an accelerator; the guarantee
is the bounded cadence underneath: a poll runs only while something is owed, only
inside the lane's budget (`ReflectionWindow.pending_budget_ms/0`), and stops when
nothing is owed. One poll chain per screen — starting a second while one is
running would double the cadence on every event.

## The laws

1. **The write's ok is never the confirmation.** `save_reflection/1` sends the
   request; the "saved" card is drawn from the row `capture/1` returned, and the
   row is then re-read by id. The tests make the write's reply disagree with the
   re-read on purpose, so a card drawn from the write cannot pass them.
2. **A write is never retried.** If it does not come back, the screen says so and
   waits for a human. A reflection written twice is worse than one written again.
3. **A refusal keeps her words.** The confirmation card stays up, the box keeps
   the text, and the store's own sentence is shown where the confirmation was.
4. **A failed read is a refusal, not an empty list.** `@list_refusal` is a
   separate assign from `@refusal`, and the list renders only when a read reported
   rows. `[]` is a reading; a refusal is not a list.
5. **A blank string is not words.** `text_or_nil/1` sends an `answered` row with
   empty text to `{:failed, …}` and never draws a blank answer line; a `failed`
   row with no sentence gets an honest sentence of its own.
6. **A field the store has never sent is `nil`** — never `""`, never `0`.
7. **Two presses to write.** Y reviews the draft (the confirmation card), Y again
   sends it, B backs out. Nothing is sent on a keystroke.

## A trap for tests: a `live/2` mounts twice

The router performs a **dead render** and then the **connected render**, and
`mount/3` runs in both. A read started in `mount/3` therefore goes out on the wire
**twice per page load** — that is how every screen in this app already mounts, so
it is not something these lanes introduced, but it means:

- a test cannot infer the screen's state from a *call count* (the first read is
  the dead render's, and the screen never sees its answer);
- the read-back tests drive the store's state with a `:counters` flag the **test**
  flips, not with a counter of calls.

`ReflectionWindow`/`PartyWindow` are pure, so they are tested directly. The
LiveView tests install `BrokerStub` through app env and use `{:answers, fun}` so
the write's reply and the re-read can tell different stories.

## Where the tests are

| File | What it pins |
|------|--------------|
| `test/reflection_window_test.exs` (30) | subjects, payload shapes, all four answer states, the blank-string law, `nil`-not-`""` |
| `test/reflect_phone_read_test.exs` (15) | the phone: write is a request, refusal is not a save, re-read drives the card, bell, cadence |
| `test/reflection_desk_read_test.exs` (6) | the desk: same laws, and the empty-page refusal asks the store nothing |
| `test/nats_bridge_test.exs` (+4) | the two new subscriptions and their channel/event names |

21 of these fail against the pre-read-back code (proven by stashing the `lib/`
changes and re-running), which is what makes them a proof rather than a
description.
