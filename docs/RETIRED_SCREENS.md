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

A path the map does not know is a `404`, and says so. That is not a screen either, but
it is not a lie about one.

All thirteen retired paths are `get` routes outside `live_session`, because there is no
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

## What the bar and the menu carry now

Six screens: **House**, **Window** (with the shelf inside it), Timer, Quest, Fitness,
Health. The five report screens are not among them, and neither is the wardrobe, GTD,
Reflect or Energy. A menu that still listed one would offer a screen that is not there —
the same fog the retirement was for, drawn a second time. `test/phone_nav_test.exs`
pins both lists, and `test/routes_mount_test.exs` pins that each retired path answers
with its move.
