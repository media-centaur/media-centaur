# Round 7 brief — the couch, and a Friends rail (2026-09-25, morning)

Two things changed after round 6 (`F-cinematic-feed`, `CRITIQUE-5.md`).

**1. The couch is the primary design consideration.** The owner: "this
needs to be readable from a couch on a TV; that should be a primary
design consideration for all of this." Facts that turn that into
numbers: the app composes at 1920 CSS px on the TV (the UI scale's
auto factor is screen ÷ 1920, so a 4K panel renders the 1920
composition at 2× device pixels), so **a 1920 mockup is exactly what
the TV shows**; and a 65" panel at three metres subtends roughly half
the angle a 27" monitor does at arm's length, so type that is
comfortable at a desk is half-size from the couch. Every round so far
was composed for the desk: the band's 15/18/14px type is too small for
the couch. This round re-scales.

**Couch floors, at the 1920 composition** (the designer chooses exact
sizes at or above these and names them; larger is allowed):

| Element | Floor |
|---|---|
| Read text (the sentence, the review, presence lines) | 22px |
| Secondary text (time, year, plain toolbar states) | 18px; nothing read below 18px except separators and icons |
| Band title | 28px |
| Lead sentence / lead title | 26px / 44px |
| Rail name / rail presence line | 22px / 20px |
| Identity tile | 56px on a band, 64px on the lead, 48px in the rail |
| Poster | 96×144 on a band, 200×300 on the lead |
| Toolbar verbs and icons | 18px text, 20px icons, 32px tall targets |
| Cursor ring | 3px primary; the TV has no hover, so the cursor state is the TV's hover and must be obvious at three metres |
| Contrast | text over the scrim reaches at least 4.5:1 against the ink it sits on; check the lowest-alpha text, not the brightest |

Band height follows the floors (expect 220–260px); rows per fold fall
to about three plus the lead, which is right for a couch. The desk gets
a large UI; the UI scale preference can shrink it there. Do not shrink
anything to fit more rows.

**2. A Friends rail, pitched by the owner.** "If the viewport is wide
enough, the Friends section becomes a second column on the right. The
Friends list could lose some of its content to the Feed but keep its
'what they've been watching' focus, ordered by latest watching
activity." The critique's case for it: B's band (the 1280 container, a
37% slice, every still landing) lost only on the empty right third,
and a rail fills that with a second kind of content — the one social
fact the Feed excludes by rule, what friends are watching now — instead
of a wider picture. Its costs: two layouts (the rail folds back into
the Friends tab below a width), the card's management affordances need
a home, and it introduces a page shape (main column plus rail) the app
does not have.

## The rail

Per person: the identity tile, the name, a **presence line** in the
Friends card's verbs ("watching Pioneer One · S01E03 · 2h ago",
"reviewed Charade · 1h ago", "wants to watch Sintel · 12m ago",
"Nothing shared yet"), and one poster of the latest watched title. Ordered
by latest activity, **You first** (your own presence line; the You card's
"How friends see you" as its subtitle). At the rail's foot, one quiet
control, **Manage friends**, which opens today's Friends tab content
(add a friend, keys, remove) — draw it as a link, not the form. Show
eight people on the page and say how the rail scrolls at thirty. No
five-poster strip, no "all N" grid, no counts: those live behind the
person's entry, which opens the person (draw nothing for that).

The Feed excludes watched by rule (UIDR-038 *wall of watching*); the
rail is presence, one line per person, not a timeline — say so in
REASONING and argue why it is not the wall.

## Directions

Each renders at 1920 (the TV) and at 1280 (a narrow window; the rail
folds into the Friends tab), in the app frame from `base.css`.

- **`R1-rail`** — the feed column (about 1180px: B's band, a 37% slice
  from a box starting at the text zone's edge, the time at that edge)
  beside a Friends rail (about 560px, a 24px gutter) at 1920. The
  lead at the column's width (1180×340 → re-scale the height to the
  couch floors). The Watchlist tab with the same rail. The 1280 state:
  tabs Feed · Watchlist · Friends, no rail.
- **`R2-full`** — `F-cinematic-feed` re-scaled to the couch floors,
  no rail: the fair comparison. Band and lead sizes re-derived (the
  band grows; say what the 900px box's slice becomes at the new
  height). The 1280 state as F had it.
- **`R3-masthead`** — the lead spans the full width above both columns
  (1820 wide, couch-scaled), then the feed column and the rail below
  it: the lead keeps its presence, the bands sit beside people. Say
  what the lead does when the newest action is yours and the rail's
  first entry is also you.

All three: the identity tile as the own mark (filled button primary,
white initial; "You" neutral); the crop rule (`50% 30%`, `50% 38%` on
the second of two adjacent units of one title; no per-title positions);
the scrim recipes from F, re-anchored to the new text zone; the
toolbar contract; states 1–9 from `BRIEF.md` re-scaled, plus: (10) the
cursor on a band with the seat shown — the TV's hover; (11) the rail's
states — You first, a friend with a photo, a friend with nothing shared;
(12) the Watchlist with the rail (R1, R3) or at full width (R2); (13)
the 1280 state.

## The 10-foot check

After the 1920 render, make a half-size copy (`vips resize in.png out.png 0.5`)
and Read it: that is roughly the couch. Every read text must still be
read at half size; every tile's letter, every time. Fix what fails and
say in REASONING what the check changed.

## Data

`BRIEF.md`'s sixteen rows and art. Rail people: You, Cleo, Nick, Bob,
Sam, Ada, Femi, plus one friend with nothing shared (Theo); watched
titles for presence lines from the PD/CC set (`pioneer-one`,
`one-step-beyond`, `big-buck-bunny`, `coffee-run`, `caligari`).

## Deliverable

`<dir>/index.html` linking `../base.css` and `../art/`, and
`<dir>/REASONING.md` (under 1400 words): the sizes table at the couch
floors; the rail's anatomy and ordering (R1, R3); what folds at 1280
and how the tab strip changes; the 10-foot check's findings; what a new
arrival does; the rules touched (UIDR-038 rules 7–10 on the Friends
card, *wall of watching*, UIDR-045, UIDR-033) with each exception; the
one thing you are least sure of. Render with `page-shot` to the scratch
folder; nothing outside your folder; no git, no mix.
