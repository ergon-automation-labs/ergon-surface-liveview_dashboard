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

A path the map does not know is a `404`, and says so. That is not a screen either, but
it is not a lie about one.

All seven retired paths are `get` routes outside `live_session`, because there is no
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
`HabitsPhoneLive`, `HabitAnchorsLive`, and the two modules that became dead with them —
`SelfReport` (its only readers were the body and yearning screens) and `HabitItems`
(its only readers were the two habits screens). Six test files went with them. The bar
is 14 entries → 9; the long-press menu is 13 → 9.

## What the bar and the menu carry now

Nine screens: **House**, **Window** (with the shelf inside it), Timer, Quest, Reflect,
Energy, Fitness, GTD, Health. The five report screens are not among them, and neither
is the wardrobe. A menu that still listed one would offer a screen that is not there —
the same fog the retirement was for, drawn a second time. `test/phone_nav_test.exs`
pins both lists, and `test/routes_mount_test.exs` pins that each retired path answers
with its move.
