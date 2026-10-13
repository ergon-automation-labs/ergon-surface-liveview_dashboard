# Retired screens, and the paths they left behind

A screen is retired when the thing it drew is drawn somewhere better. A **path** is
never deleted — on a phone, from a home-screen icon that was added when the page was
real. Answering a bookmark with `404` turns *the shelf is in the window now* into
*you typed it wrong*, which is the wrong sentence and the wrong feeling. So the path
stays behind and answers with the one thing it still knows: where the screen went.

`BotArmyDashboardLiveview.Retired` is that map, and it is the only place a dead path
is answered. Its destinations come in two kinds, and the difference is load-bearing:

| Kind | Example | Why |
| --- | --- | --- |
| `{:same_host, path}` | `/hypnosis-phone` → `/party-phone?moved=shelf` | Relative on purpose: whichever host the bookmark arrived on is the host the screen behind it is served from. |
| `:her_closet` | `/wardrobe-phone` → her panel's closet | A **different origin**. `/` on this dashboard is this dashboard; no screen here holds a closet. The address is built from the arriving host by `HerPanel`, never from `localhost`. |
| `:her_reports` | `/body-phone` → her panel's **How I am** | The same different origin, for the same reason — and five paths share it, because the distinction worth keeping is *where her own numbers live*. |
| `:her_tasks` | `/gtd-phone` → her panel's **Tasks** | The same different origin again. Two paths share it, and neither of them was a report: what they drew was the box her tasks live in. |
| `:her_reflect` | `/reflection` → her panel's **Reflect** | The same different origin, and the two paths share it for the same reason as the tasks pair: two doors onto one box. What is behind them is her journal. |
| `:her_energy` | `/energy-mood-phone` → her panel's **Energy** | The same different origin, and this pair is the only retire whose defect was not about *who* could write: the check-in left as a publish with no reply, so the screen confirmed a byte on a socket rather than a stored reading. |
| `:her_timer` | `/timer-phone` → her panel's **Timers** | The same different origin, and the pair is the energy pair's defect a second time: the session was filed with a publish nobody had to read, and the running session's id lived in the page, so a reload lost both. The fix went past this surface — her panel's group holds the session in the bridge (§51). |
| `:her_quest` | `/quest-phone` → her panel's **Quest** | The same different origin, and the pair is the GTD pair's defect and the worse half of it: a progress bar and a streak drawn over the box her tasks live in. Her panel counts the open steps it drew, and never a percentage (§50). |
| `:her_fitness` | `/fitness-phone` → her panel's **Fitness** | The same different origin, and this pair is the only retire whose defect was a **word**: the screen carried its own list of activities and intensities — a sixth copy of the bot's vocabulary — so it could send a word the bot folds and draw it back under a word it invented. Her panel draws the bot's own options over the wire (§46). |

A path the map does not know is a `404`, and says so. That is not a screen either, but
it is not a lie about one.

All nineteen retired paths are `get` routes outside `live_session`, because there is no
screen behind any one of them.

## `/hypnosis-phone` — the shelf's own page

The shelf is drawn inside the window now. What she asked to hear is a moment rather
than a place, and a bar that is on every page at once offered it in the middle of every
other thing she was doing, so the page went and the shelf moved inside the window. The
destination carries `moved=shelf`, and the window says in its own words what moved and
why — a redirect that lands somewhere unexplained is only a slightly nicer `404`.

21 of the 22 tests the page carried run against the window now — the one left behind was the
page's own identity, which the window's identity already pins. Retiring a screen that
keeps its tests is a move; retiring one that takes them with it is a deletion with extra
steps.

## `/wardrobe-phone` — the wardrobe on the handheld

This one went **further than the window did**: the thing it drew now lives on a
different surface, on a different port, behind a different link. It is not retired
into this dashboard at all, and that is the whole point.

What it had was the only place that told her *which of the two ways* a set got on her —
her own choice, or the house putting her in something. That distinction is not
decoration: an assignment drawn as her choice is the one lie a closet card can tell.
But the screen drew it on a surface **anyone on the network can reach**, and a wear is
a write whose entire meaning is *whose voice it was*. The bot records `chosen` from the
name the surface claims, and this screen sent the two constants the bot accepts —
`by: "slave"` behind **Wear this**, `by: "louiza"` behind **Assign**. So the open
handheld claimed her voice and the goddess's voice, from the LAN, with no identity
behind either.

Her own panel already holds that write, and holds it better: the name it files under is
the session it came from and not a constant in a component, and it can add a set, edit
one, put one away, and put one on. It now reads the same `chosen` column and says the
same sentence about it, which is what made retiring this screen lossless.

So the closet has **one** home. Nothing moved off the closet; the second copy of it is
gone. Two screens showing the same cupboard is the fog this household does not need:
*which one do I use?*, and then two answers that can drift apart.

Removed with it: `BotArmyDashboardLiveview.Wardrobe` (the read, the two verbs, the
re-verify) and `WardrobePhoneLive`, plus their two test files. The bar is 15 entries
→ 14; the long-press menu loses the same line.

### What is not on this dashboard any more, and what still is

The bar still carries the **window** (with the shelf inside it) and the **house**
(the household HUD). The reporting screens — Yearning, Body, Devotion, and the rest —
were still here when the wardrobe went; they are gone now, and the section below is
where they went.

## The five report screens — Yearning, Body, Devotion, Habits, Anchors

These are the same defect as the wardrobe, **without even a name attached**, which is
the worse half. Each one *made* one of her reports:

| Path | The write it made |
| --- | --- |
| `/yearning-phone` | `record_goddess_proximity` |
| `/body-phone` | `record_body_reading` — and it also carried the **escape card**: `record_cage_escape`, `undo_cage_escape`, `set_cage_escape_period` |
| `/devotion-phone` | `subject_reply` |
| `/habits-phone` | `record_hygiene_event` |
| `/habit-anchors` | `record_hygiene_event`, against an anchor's items |

The bot files **all** of them under `:slave` without being told — the identity is not on
the wire at all — so the page that sent the write was the only thing on this surface
that knew whose hand was on the screen, and this surface is open. A body reading or an
urge filed by a screen nobody authenticated is not a report; it is a number with no
owner.

Her own panel makes all five behind her own link (§44 of the bot's control surface
contract), and the house screen still **reads** what they wrote: both the yearning
indicator and the five body channels are drawn on the household HUD, with no tap and no
ladder, saying in its own words that she logs them on her own screen. So nothing is lost
by the bar dropping them — the read stayed where it was and the write went where the
identity is.

All five land on one destination, and that is a decision rather than a shortcut: the
distinction worth keeping is *where her own numbers live*, and one group she can
recognise is a better answer to a bookmark than five addresses that each have to be
right. (The panel does not read a `moved=` parameter, so the redirect is unexplained —
unlike the shelf, which lands on the window that draws it. The group's own heading is
the explanation.)

Removed with them: `BodyPhoneLive`, `YearningPhoneLive`, `DevotionPhoneLive`,
`HabitsPhoneLive`, `HabitAnchorsLive`, and the three modules that became dead with them —
`SelfReport` (its only readers were the body and yearning screens), `HabitItems` (its only
readers were the two habits screens) and `Devotion` (the devotion screen's own helper: the
openers, the draft, and the `subject_reply` write). Six test files went with them. The bar
is 14 entries → 9; the long-press menu is 13 → 9.

## The GTD screen and its handheld — the smaller half of the same defect

The report screens above are the worse half of one defect: a write with **no identity on
the wire at all**. These two are the smaller half, and the difference is worth stating
precisely, because it is the difference between *the wrong voice was used* and *there are
two answers*. What they wrote went through the bridge as `slave`, so nothing was filed
under the wrong hand. What they drew was a list, a defer and a done over `bridge.task.*`
— the box her tasks live in — on a surface anyone on the network can reach.

That is still a defect, and the reason is one sentence long: **a task list is an answer
to *what should I do next*.** Two screens drawing one list are two answers to it, and the
one on the open surface is the one nobody is holding. Her own panel's **Tasks** group
draws the same box with the same verbs (§45 of the bot's control surface contract), which
is what makes this a move rather than a deletion with extra steps — the done and the
not-now are both there, reading the same tasks.

Both paths land on that one group. The handheld went with the phone not because anyone
linked to it, but because it drew **the same** screen: retiring one and not the other
would have left a second answer reachable by URL. (The handheld's twin for the reports was
retired on the same rule.)

Removed with them: `GtdPhoneLive`, `GTDHandheldLive`, and their test files. The bar is 9
entries → 8; the long-press menu loses the same line. `test/view_read_path_test.exs` kept
the lesson those tests carried — a read that died must say so rather than show an empty
state — by moving it onto the health screen, which is one of the two that still read.

## The reflect screens — the reports' defect exactly, and the worst of the set

`/reflection` (the desk screen) and `/reflect-phone` are **not** the smaller half of
anything. The five report screens had a name on the wire — the bot files those writes
under `:slave` without being told, so at least the name was known — and these two had
**nothing**. Both wrote `companion.reflections.capture`: her own words, in her own journal,
from a surface anyone on the network can reach. A reflection's shape is text, a prompt and
a `dedupe_key`; the store has **no notion of a person**, so the page that sent the write was
the entire answer to *whose words are these*, and it was the page on the open surface.

Her panel's **Reflect** group (§47 of the bot's control surface contract) is where that
write belongs now: it holds `companion.reflections.capture` under her own session's
identity (`slave`, the hand she uses it with), asks the same question, draws the journal as
the confirmation of a write, and shows the companion's answer when it lands. It reads the
same two subjects the retired pair read (`companion.reflections.list`, and the row by id),
and it does not read `companion.reflections.read` — a subject the old screens used and the
panel has no business asking for.

Both paths land on that one group. As with the GTD pair, the desk screen and the phone
screen were the same screen twice, so retiring one and not the other would have left a
second door open to the same box.

## The energy screens — the only retire about a *confirmation* rather than a permission

`/energy-mood-phone` and `/energy-mood-handheld` drew the last energy reading and filed a
check-in. They are not the reports' defect: they carried an identity on the wire, and a
reading is about her rather than a decision taken about her — which is why §10 says
recording energy is deliberately **not** gated by the pause gate. They are not the GTD
pair either, where the cost was two answers to one question. Their defect is narrower and
quieter, and it is the one thing a check-in has to get right.

The check-in went out as `Gnat.pub/3` to `events.context.updated` — a **publish**, with no
reply. `:ok` from a publish means the bytes reached the socket, not that a bot received
them and not that anything was stored, and with no subscriber that day the bytes reached
nobody at all. The screen drew **"Context saved"** over that. So the confirmation was a
statement about a write the page could not see, and a link that said "saved" while
nothing was saved is worse than one that said nothing: it teaches her to distrust the
word, and the next genuine save reads the same.

Her panel's **Energy** group (§49 of the bot's control surface contract) asks
`wife_care.energy.record` instead. The reply *is* the bot's answer — a refusal arrives in
the bot's own words rather than as a silent no-op — and the card above is redrawn from the
reading the bot now holds, which is the only confirmation this page claims. It also draws
the three ways of having nothing as three different sentences: a word the bot has never
been given is not a zero, a failed read is not "no reading", and a block that arrived but
cannot be read out is a fault in the answer rather than a fact about her.

Both paths land on that group. The handheld twin goes with the phone because the screen
it drew is gone, not because anyone linked to it — the same rule the GTD pair followed.
Nothing about the reading is lost: the panel reads the same pet-layer reply these screens
read (the `energy_detail` block), and the one subject the old screens *wrote* it now asks
and reads back.

**What did not move with them: the publish.** `events.context.updated` still exists and
other producers still send it; what stopped is this surface treating a publish as a
confirmation. The lesson the retired modules carried — *a write's confirmation is a
re-read, never the write's own reply* — is pinned in `docs/REFLECTION_READBACK.md` and in
her panel's tests.

**What did not move with it: the bell.** The screen woken by `events.llm.job.completed` was
one of these two — the bridge broadcasts it to `dashboard:reflections`, and the screen
re-read the answer on it, with a ten-second poll as the guarantee. Her panel polls at the
same cadence and does **not** subscribe to the bell, so an answer arrives up to one poll
late. The bell is an accelerator and the poll is the guarantee (that was the retired
module's own phrasing), so nothing is lost in correctness — but the acceleration is gone,
and `nats_bridge.ex` still broadcasts to `dashboard:reflections` for a listener this
surface no longer has.

Removed with them: `ReflectionLive`, `ReflectPhoneLive`, `ReflectionWindow` (the wire
module only those two screens read), and their three test files. The bar is 8 entries → 7;
the long-press menu loses the same line. The lessons those tests carried are pinned in her
panel now — a refusal is not an empty store, `pending` is a state and not a synonym for *no
answer*, and a read that never came back says so (`test/wife_care_control_liveview/
panel_live_test.exs`, "The companion did not answer…").

## The timer and the quest — the pair this surface's own shape argued against

Four paths: `/timer-phone`, `/timer-handheld`, `/quest-phone` and `/quest-status`. They are
the first retires here that are **not** the reports' defect, and saying so is what keeps this
document honest. The timer wrote through the bridge as `slave`, and the quest screen did not
write at all — so nothing was filed under the wrong hand, and no journal was written from an
open surface. Their cost is the other half of the same coin, twice over, which is why neither
is a gate either.

### `/timer-phone` and `/timer-handheld` — the energy defect, in a second place

The timer screen filed its session as an `events.timer.*` event: a `Gnat.pub/3`, with no
reply, so the **"Session logged"** it drew was a statement about bytes that had reached the
socket, exactly the sentence the energy screen taught her not to trust. And the running
session's own id lived in the LiveView's state — so a reload took the session *and* the only
handle that could end it, leaving a timer running in the bridge that nothing on the page
could finish.

That is why the fix for this pair did not stay on this surface. A session that must survive a
page it is not in has to live somewhere the page is not, so her panel's **Timers** group holds
it **in the bridge**: the bridge gained `bridge.timer.list` and a 24h age-based sweep (§51 of
the bot's control surface contract — a session abandoned by a closed tab expires instead of
accumulating), and the panel asks for the list, asks the bridge to end the one she names, and
throws the id away. The session's clock is the bridge's from beginning to end.

### `/quest-phone` and `/quest-status` — the GTD defect, and the worst half of it

`/quest-phone` drew a **progress bar** and `/quest-status` a **streak**, both over the box her
tasks live in. A bar and a streak are a board-shaped view of *how much is done*, and that is
the view this household refuses on purpose: a list of nineteen things is where a foggy person
gives up, which is the exact reason the GTD screen was retired into her panel's Tasks group
(§45). Two screens answering *how am I doing* with a percentage is that same fog, drawn a
second time and with a number attached.

Her panel's **Quest** group (§50) is where the quest went: it draws the open steps — the
quest is the GTD project the steps belong to — and the only count is the count of the rows it
drew. No bar, no percentage, no streak. That it is drawn at all, and not gated, is the same
reasoning as the two it followed: a quest is a read, and reading is not a permission.

### Why all four are moves rather than gates

Neither defect is about *who* could write, so there is nothing here for a gate to admit. What
was wrong was **where the state lived** (the timer's session, in the page) and **what shape a
read took** (the quest's progress, as a bar). Both are answered by the screens her panel
already holds — the session in the bridge, the steps counted — and so every one of the four
paths hands its bookmark to the group that holds what it was about.

Removed with them: `TimerPhoneLive`, `TimerHandheldLive`, `QuestPhoneLive`,
`QuestStatusLive`, `QuestPayload` (the wire module only the two quest screens read), and
their test files. The bar is 6 entries → 4 — Timer and Quest were two of the six — and the
long-press menu loses the same two lines. `test/phone_nav_test.exs` pins both lists, and
`test/routes_mount_test.exs` pins that each of the four paths answers with its move.

## The fitness screens — the sixth copy of one vocabulary

Two paths: `/fitness-phone` and `/fitness-handheld`. They are the one retire here whose
defect is a **word** rather than a write, and saying so is what keeps this document honest.
The phone screen carried its own list of what a workout is — `@workout_types` and
`@intensity_levels`, hard-coded in the view — which made a **sixth** copy of a vocabulary the
bot itself had already retired five times over. A screen with its own list can send the bot a
word it folds onto `"other"` and then draw the row back under the name it invented, so the
open surface and the bot disagree about what she did while both are showing her the same log.
(The screens *did* write the right verb — `fitness.workout.log`, not the dead
`events.fitness.workout_logged` publish an earlier version carried — so this is not the energy
defect. What was wrong was the words, not the write.)

Her panel's **Fitness** group (§46 of the bot's control surface contract) asks
`fitness.workout.options` and draws the activities and the intensities **and the bot's own
words for them** off the wire, so the picker can only offer what the bot accepts and a stored
row can only be named as the bot named it. That is why the fix had to reach the bot — the
`options` subject exists for exactly this — where the vocabulary could not be corrected on the
surface that invented it. The panel also counts nothing: the card is what she has done, in
felt time, with no streak and no total.

Both paths land on that group. The handheld twin goes with the phone because the screen it
drew is gone, not because anyone linked to it.

Removed with them: `FitnessPhoneLive`, `FitnessHandheldLive`, and their two test files. The
bar is 4 entries → 3, and the long-press menu loses the same line.

## What the bar and the menu carry now

Three screens: **House**, **Window** (with the shelf inside it), **Health**. The five report
screens are not among them, and neither is the wardrobe, GTD, Reflect, Energy, Timer, Quest
or Fitness. A menu that still listed one would offer a screen that is not there — the same
fog the retirement was for, drawn a second time. `test/phone_nav_test.exs` pins both lists,
and `test/routes_mount_test.exs` pins that each retired path answers with its move.
