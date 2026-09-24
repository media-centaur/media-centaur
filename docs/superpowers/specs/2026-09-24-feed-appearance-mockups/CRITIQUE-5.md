# Round 5 critique — the cinematic feed, four settings and three explorations

Written in the night of 2026-09-24 after rendering every page at
1920×1080 (top and 2600px tall) and reading each REASONING.md.
Round 5 built the round-4 critique's cross — direction 1's bands with
direction 4's lead — under one crop rule from the measurement
(`object-position: 50% 30%`, no per-title positions), in four
settings that isolate the questions the critique left open. Two
explorations ran beside it: motion, and the language carried to the
other Discovery tabs.

## The cross holds

All four settings confirm the cross as a page. One markup at two
sizes reads as one language; the lead gives each screen a dominant
element and the bands keep the pop on every screen after; the own
mark (a tile filled with the button primary, a white initial, "You"
set neutral) is found without reading on every page; the fixed crop
rule, applied without a single hand-set position, produced no failed
still on sixteen PD/CC backdrops in any setting — Metropolis at the
21% slice shows the robot's rings and torso with the head above the
band, the rule's known marginal case, and the poster beside it names
the title. The question of this round is which setting, not whether.

## The settings

### A · Full width, box from 560, time at the far right

The strongest page of the night on presence: bands reach the
monitor's edge, the lead's still is 1820px wide. Its costs are the
ones direction 1 carried: the band's 21% slice (safe by the
measurement, but with the least margin), the time 1,650px from the
words, and one new one — the full-bleed lead veils a subject that
sits dead centre (x≈910 is under a .5 scrim); Sintel and Night of the
Living Dead put their subjects right of centre and read; a centred
face would be half hidden. The lead's left half is a colour cast
under the poster, not a picture and not ink. A's designer named the
fix, a lead whose image box starts at 560 like the band's (a 48%
slice, the subject in the clear), and A2 renders it.

### B · The 1280 container, box from 560, time at the text zone's edge

Safe and handsome. The band's 720px box gives a 37% slice and every
still lands a subject; the lead at 1280×300 shows Sintel's whole face;
the time at x=540 sits beside the words and forms one axis down the
column. Its cost is the one the owner asked this campaign to remove:
the right 540px of a 1920 monitor is ground on every band, and the
page's presence is the lead's alone. B's designer said it plainly —
"this page pops on the lead and is handsome below it" — and that
handsome is not the bar.

### C · Full width, the band's still in a 900px box, time at the text zone's edge

The best band of the round. The 900px box holds the measured safe
slice (30%) at any width above 1476; the time at x=576 is one axis on
every unit, 1,200px closer to the words than A's; no vignette is
needed and the picture's right edge is clear to the band's corner. The
cost is the ink between the words and the picture — 344px at 1920 —
which reads as the deep end of the still's dissolve at 1920 (the
designer's honest word is "gutter", and the render agrees) and as a
hole at 2560 (984px), where the app's UI scale makes 2560 render near
1920 anyway. Its lead is A's full-bleed lead with the time moved to
the text zone's edge inside the block, which its designer is least
sure of; B's rule is better there — the time is right-aligned at the
body's edge, which on a band is the picture's start and on the lead is
the padding, so the lead's time sits top right.

### D · Full width, bands grow to 200px when the review has words

The height rule is clean (a data property, two layouts) and the
taller band's 28% slice is safer, and the render is handsome: the
column takes on a magazine rhythm. But on this data six of eight
reviews are one-liners, so most 200px bands hold a line of words and
two lines of air; the time axis loses its beat; the arrival shift
becomes variable. D's designer says it: if the extra height reads as
air, the fix is not a threshold but C's setting with the words filling
the ink gap. Rejected for now; kept as the fallback if the owner wants
three lines of review on the band.

## The explorations

### X · Motion

Three switchable motions on direction 1's bands, each transform-only
and behind `prefers-reduced-motion`. Scroll parallax is the most
beautiful and the only one that changes what a band shows — it sweeps
the crop from 27% to 36% across a band's travel, into the measured
failure zone at the top edge — on sixteen new compositor layers.
Ambient drift on the newest still keeps the GPU awake for a 0.1%/s
change. Hover ease (400ms, scale 1.03) costs nothing at rest and is
the page's existing idiom. The designer's verdict, which I share: if
one ships it is hover ease, carried by the cursor ring on the shell
where there is no hover; and the honest case is that none of the
three makes a sentence easier to find. Motion is the lever demos pull
and feeds regret. Recommendation: hover/cursor ease as the one
candidate, decided in implementation; no parallax, no drift.

### P · Propagation to the Watchlist and Friends tabs

The band language travels where the row is a title and strains where
it is not. The Watchlist in bands is striking and coherent: title
first, the ladder and acquisition words in the seat, the house
pennant mast flying from the band's right edge over the still, a
no-artwork title as an ink band. The Friends card resists: its
artwork was already plural (the Recently watched grid), so a still
behind the card is decoration keyed to the presence line, not the
card's subject (UIDR-033), and the grid shrinks to stamps. Beyond
Discovery: Incoming's activity fits best (state words are the seat's
vocabulary), History would wall one still across an episode run, Home
keeps its cards — the language propagates as a material (a still under
the base-hue scrim, a dark text zone), not as a component. Two
findings for later: whatever width the Feed takes, all three tabs
share it; and the pennant mast at the far right at full width is the
time-seat problem again — a mast at the text zone's edge is worth
trying.

## Decisions this round settles

| Question | Setting | Evidence |
|---|---|---|
| Full width or the container | **Full width** | B is handsome, not gorgeous; the crop rule makes full width safe (0 failures at 30% on 24 real stills at the 21% slice; C's 900px box adds margin) |
| The band's image box | **Capped at 900px, right-aligned** (C) | The measured safe slice at any width; the ink reads as a gutter at 1920; A's 21% is the fallback if the owner prefers the picture reaching further |
| The time's seat | **Right-aligned at the body's edge**: x≈576 on a band, top right on the lead (B's rule, C's band) | One axis, 1,200px closer to the words; the lead has no text/picture boundary to sit on |
| Review lines on a band | **Two, at 152px** (A/C) | D's taller bands are air on one-line reviews; D stays the fallback for three lines |
| "You" beside the filled tile | **Neutral** | Unanimous across A–D |
| The own tile's fill | **Button primary `oklch(62% 0.16 264)`, white initial at 700** | Unanimous; the 72% text primary cannot carry a white letter |
| Adjacent rows of one title | **Accept the repeat**; keep the 8% offset | The offset stops an exact repeat and no more; a different picture would be a lie about behaviour |
| The lead's image | **A2 decides** (boxed from 560 vs full-bleed) | A's full-bleed veils a centred subject; the boxed lead is one image-box rule for both sizes |
| Motion | **Hover/cursor ease at most; no parallax, no drift** | X |
| The other tabs | **Watchlist takes the band; Friends keeps its card and gains the identity tile; Incoming next; Home and History unchanged** | P |

## What the owner decides in the morning

1. **Ship the cinematic feed** as C's band (capped box, time at the text
   zone's edge) with the lead A2 or A settles, or send it back with
   one more setting to render. Everything below assumes yes.
2. **Full width for Discovery**, all three tabs, as the page decision.
3. **Whether the Watchlist follows** in the same campaign or the next.
4. **Hover ease**: yes, no, or decide in the storybook.

## Records the cross amends

- **UIDR-045 rule 3** — the identity tile is the own mark (filled
  button primary, white initial, a 2px ring over a photo); the word
  "You" is set like any name; the second person stays.
- **UIDR-045 rule 5** — bands 6px apart on the page ground, no shared
  surface, no hairlines; the Discovery page takes full width.
- **UIDR-038 *social-network chrome*** — the identity tile (the Friends
  tab's monogram, a photo when one exists) is the app's person
  device on both tabs; handles, counts and reactions stay banned.
- **UIDR-038 *wall of watching*** — a captioned still per action is
  not a wall of titles: the sentence leads in a fixed text zone.
- **UIDR-038 *title-first*** — bent on the lead only: the title is the
  headline, the sentence still reads first.
- **UIDR-033** — a row's own title artwork is that row's subject; a
  band of an unrelated title stays banned.
- **New UIDR-046**, *the cinematic feed*: one unit at two sizes, the
  band and the lead; the identity tile; the crop rule; the scrim
  recipe; every size named — from the spec round 5 finishes.

## What implementation needs, in order

1. `Discovery.IdentityTile` (monogram · photo · own · own+photo, at
   32/40/48) replacing `PersonCard`'s inline monogram; story.
2. Row artwork: `FeedEntry.backdrop_url`; `ActivityPosters` becomes an
   artwork resolver for poster and backdrop down the same ladder;
   `TmdbArtwork` warms backdrops for activity identities; derivatives
   at `?w=1280` (bands) and `?w=1920` (the lead).
3. `FeedEntryRow` becomes the band component with a `size` attr
   (`:lead | :band`); the scrim, mask and crop as CSS classes in
   `app.css` (`.feed-band`, `.feed-band-lead`); the story pins all
   thirteen states.
4. `DiscoveryLive`: `full_width`, the inset list surface removed, index
   0 rendered as the lead; the You-empty state without a lead.
5. The spec's "What the user sees" and "The model" written from the
   chosen pages with every size; UIDR-046 and the amendments; the wiki's
   Social page; then the hardening pass (nav zones for bands, the pill,
   the seat).
6. Follow-ups, each its own phase: the Watchlist in bands with the mast
   at the text zone's edge; the Friends card with the tile; Incoming's
   activity; hover/cursor ease.
