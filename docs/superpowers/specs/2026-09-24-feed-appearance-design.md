# Discovery › Feed: the Feed's appearance — telling authors apart

**Date:** 2026-09-24 · **Status:** design settled 2026-09-25 (campaign
`campaigns/feed-appearance.md`, rounds 4–9). The Feed page is
`2026-09-24-feed-appearance-mockups/G-couch-feed/` and the person card
is `J-friends-page/` with the act glyph in the owner's corner-disc form
(`CRITIQUE-9.md`, owner's call); the crop rule is `MEASUREMENT.md`; the
couch floors are `BRIEF-7.md`; the paging and the Friends-tab decision
are `BRIEF-8.md`; the settled table from round 5 (the identity tile,
the crop rule, the scrim, "You" neutral, no motion beyond a possible
cursor ease) is `CRITIQUE-5.md`. Implementation plan:
`../../plans/2026-09-25-cinematic-feed.md`. Record to write: UIDR-046.
The shipped design this starts from is
`2026-09-24-feed-timeline-scope-design.md` (UIDR-045); its scope, entry
rule and toolbar contract are kept.

## Glossary

Existing terms are in `docs/GLOSSARY.md`: *Feed*, *feed row*, *Scope*,
*Author*, *Action*, *Review*, *Listing*, *Pennant*, *Rung*, *Ladder*
(artwork tiers). This design adds:

| Term | Meaning |
|---|---|
| **Author mark** | Whatever visual device says who wrote a row, beyond the name itself. Was the word You in the primary colour on an own row; is now the identity tile. |
| **Own mark** | The author mark for the reader's own rows: the identity tile filled with the button primary. |
| **Friend mark** | The author mark that tells one friend from another: the identity tile's letter, or their photo. |
| **Identity tile** | The app's one drawing of a person: a circle carrying the name's first letter (the **monogram**) or a photo when one exists; filled with the button primary and a white letter for the reader's own. 56px on a band, 48 in the rail, 64 on the Friends page. |
| **Row artwork** | The artwork a row is about — the title's poster and its backdrop — resolved by the host down the ladder, never by the component. |
| **Band** | The Feed's unit: one action as a 224px strip on ink, the title's still in a box on the right under the scrim, the tile, the poster, the sentence, the title and the review in the text zone on the left, the time at the text zone's edge, the toolbar in its seat. There is no larger size: no lead. |
| **Text zone** | The band's left 700px, inside which no image box begins; the review's measure ends there and the time is right-aligned to its edge. |
| **Image box** | Where the still is painted: from `max(700px, width − 900px)` to the band's right edge — 536px wide in the 1236 column, a 74% slice of a 16:9 still. Its left edge dissolves under a mask and the scrim. |
| **Crop rule** | `object-fit: cover; object-position: 50% 30%` on every still, measured on real backdrops (`MEASUREMENT.md`); the second of two adjacent bands of one title takes the **offset crop**, `50% 38%`, derived from adjacency in the scoped window. No per-title position exists. |
| **Scrim** | The gradient of ink over the image box: heavy under the text zone, dissolving across the box's first 360px, clear at the right. Hover multiplies every alpha by .8. |
| **Ink** | `oklch(13% 0.02 264)`, the dark ground of the band and the person card — the identity-banner family's literal, not `--color-base-100` (27%). Defined once as `--ink`. |
| **Seat** | The toolbar's fixed 32px slot at the text zone's foot, empty at rest, shown on hover or cursor; unchanged from UIDR-045 in slots and behaviour. |
| **Rail** | The 560px column at the right of the Feed and Watchlist tabs above the fold width: person cards, You first, then friends by latest act, capped at eight, with *All N friends* at its foot. A summary of the Friends tab, never a timeline. Hidden on the Friends tab and below the fold. |
| **Person card** | One component at two widths drawing one person: the head (tile, name, the time of the latest act) over the acts strip. The rail's card at 560; the Friends page's at 900, where a press opens it. |
| **Acts strip** | The person card's picture: one poster per title the person acted on, newest first, each poster carrying an act disc per act on it. Up to three posters in the rail, five on the page. |
| **Act glyph** | The glyph for one act, in the pennant's vocabulary: heart (love), thumbs up (like), thumbs down (dislike), speech bubble (reviewed without a verdict), eye (watched), bookmark (listing). Outline at a 2px stroke, 28px in the rail, 32 on the page. |
| **Act disc** | The act glyph's form on a poster: a disc of ink at .85 with a 1px white/18 ring at the poster's top right, inset 8px — 44px in the rail, 52 on the page — the heart glyph alone solid rose (`--color-love`) on the same ink disc as every other glyph; two acts as two discs stacked downward 6px apart in mast order. The person card's form; the pennant stays the title surfaces'. |
| **Opened card** | The Friends page's card after a press: the strip in full, one sentence row per poster ending in its glyph, then the key, the added date and Remove friend. The rail's card does not open; it goes to the Friends tab. |
| **Window** | The bands the Feed holds: twenty at first, twenty more per *Show older*, sixty at most — a count, not a span. The tab's count is the window's size under the scope. |
| **Queued arrivals** | Actions that arrive while the reader is scrolled into the column: held behind a *N new* control at the column's head until pressed, so the column never moves under the reader. At the top they prepend live. |
| **Couch floors** | The sizes below which nothing on a surface may go, because the TV shows the 1920 composition from three metres: read text ≥ 22px, secondary ≥ 18px, a band title ≥ 28px, tiles 48–64px, 32px targets, a 3–4px cursor ring, 4.5:1 over imagery, and the half-size check. |
| **Half-size check** | The 1920 render read at 960×540: every read text, glyph, initial and time must still be read. The couch, on a desk. |
| **Fold width** | The container width under which the rail is not drawn: 1600px of content (a 1700 viewport). The Friends page folds to one column under 1700px of content (an 1800 viewport). |
| **Presence** | How much of the screen the page composes at 1920×1080. (Retired meaning: the person card's sentence naming the latest act — gone from the card face.) |
| **List surface** | Retired: the inset glass container the rows sat in (UIDR-045 rule 5). Bands sit 6px apart on the page ground. |

## Problem

Observed on the dev server at 1920×1080 on 2026-09-24, under Everyone,
three friends on the roster, sixteen rows (screenshot in the campaign's
first session; reproduce with `page-shot --url http://127.0.0.1:2160/discovery --viewport 1920x1080`).

1. **Authorship has no pre-attentive channel.** The author is the first
   word of line 1 at 15px medium weight, in the same neutral as every
   other name. Nothing in shape, size, position or surface differs
   between a row by you, a row by one friend and a row by another; the
   reader must read to know who. At three friends the names are short
   and distinct. At thirty they are thirty neutral words.
2. **The own mark is a hue change on a three-letter word.** "You" is the
   same size and weight as a friend's name, in the primary blue. Blue is
   also this page's interaction colour — the tab underline, the pill's
   chosen option, the links — so the hue is not reserved for
   authorship, and a colour change at 15px on a dark ground carries no
   redundancy: no second channel confirms it. That is why the word
   alone reads as too quiet.
3. **Every row is one tone.** One inset glass, one hairline between
   rows, one neutral ramp for the text. A listing and a review differ
   only in height. Scanning down, the eye has nothing to catch on.
4. **The artwork is a thumbnail.** Posters at 56×84 are the only colour
   on the page and about four percent of each row's area. Home paints
   the same titles at 453px backdrop cards and a full-bleed hero; the
   Feed, the app's one social surface, is its least visual page. The
   title's backdrop is available for every row and unused.
5. **The page does not compose at 1920.** The 896px column is 47% of
   the width; the right half of the screen is the empty scrim. Under
   the owner's UI scale the list occupies the left third.
6. **The two tabs disagree about how a person is drawn.** Friends draws
   each person as a monogram; the Feed draws the same person as a word.
   Recognition learned on one tab does not carry to the other.

The owner's brief, 2026-09-24, raised the bar past the author mark: the
page should be gorgeous — the reaction should be *holy crap*. So the
round is about the page's presence as much as about authorship: artwork,
type and composition, not a marker added to the shipped row.

## Design objectives

1. **Author at a glance.** Own rows and friends' rows differ
   pre-attentively — a channel besides hue on a small word — and one
   friend is told from another by a device that still works at a roster
   of thirty.
2. **Presence.** The artwork the row is about carries the row; the page
   composes at 1920×1080 and holds at 1280 and 2560.
3. **One anatomy, still.** One component renders every author; the
   author mark is a property of the row, never a second component.
4. **The toolbar contract holds.** A fixed seat, the row's height
   constant at rest and hovered, the same slots (List · Download ·
   Ignore on a friend's row; List · Download on an own row; withdrawal
   stays in the modal).
5. **Couch readability is primary** (owner, 2026-09-25). The app
   composes at 1920 CSS px on the TV (auto scale = screen ÷ 1920), so
   the 1920 composition is what the TV shows, and a 65" panel at three
   metres subtends about half what a 27" monitor does at a desk. Every
   read text at the 1920 composition is 22px or larger, secondary text
   18px, band titles 28px; tiles 56 on a band, 48 in the rail, 64 on
   the Friends page; posters 100×150 on a band, 96×144 in the rail,
   130×195 on the Friends page; the cursor ring is the TV's hover and
   must read at three metres; text over the scrim reaches 4.5:1.
   Rounds 4–6 were composed for the desk and were re-scaled in round 7
   (`BRIEF-7.md`).
6. **Every rule kept or named.** What UIDR-038, UIDR-045, UIDR-037 and
   the colour rule say stands unless the chosen direction argues
   otherwise, naming the rule and the exception precisely.

## What the user sees

Every size below is at the 1920 composition, which is what the TV
shows. Nothing read is below 18px; the one secondary alpha is 66% on
ink (about 10:1).

**The page.** Discovery takes the layout's full width: 1820px of
content beside the collapsed sidebar. From the tab strip down, two
full-height columns: the **Feed column at 1236**, a **24px gutter**,
the **rail at 560**. One line across both holds the strip — Feed ·
Watchlist · Friends at 22px/500 with 18px counts — and the scope pill
(44px tall, 20px options) at the Feed column's right edge; one
hairline under all of it; 16px to the first unit. The strip is
constant at every width; the rail has no heading (the Friends tab
names it) and is not drawn on the Friends tab. There is **no lead**:
every band is a photograph at this scale and the newest is first,
which is the only claim a feed makes. The Watchlist tab keeps its
rows, in the left column beside the same rail.

**The band.**

| | Band |
|---|---|
| Unit | 1236×224, radius 12, ink, 6px apart on the page ground; no border, glass, shadow or hairline |
| Tile | 56 at x=20, vertically centred; initial 22 at 600 (the own tile's at 700) |
| Poster | 100×150 at (92, 24), radius 6, shadow `0 3px 12px oklch(0% 0 0 / .55)`; no artwork: the slot as a 6% fill with a 1px inset ring |
| Text zone | x 210 → 700 |
| Line 1 | the sentence 22/30 at 80%; the name 500 at 96%; the sentiment glyph 20 |
| Line 2 | the title 28/36 at 600; the year 18 at 66% |
| Line 3 | the review 22/30 at 78%, two lines at most |
| Time | 18 at 78%, right-aligned at x=700 |
| Seat | 32px tall at y 168–200; verbs 18, icons 20; List · Download · Ignore on a friend's band, List · Download on an own band; Ignore 10px after Download |
| Picture | the image box from `max(700, width − 900)` → 536×224 at 1236, a 74% slice; the mask fades the box in over its first 240px; the scrim's stops: .93 at 700 · .55 at 820 · .16 at 940 · .04 at 1060 · 0 at the right — the 360px dissolve |
| Crop | `50% 30%`; `50% 38%` on the second of two adjacent bands of one title |
| No artwork | the band on the inset tone with a short left-running scrim; the poster slot empty |
| Hover, cursor | a 3px primary ring; the scrim × .8 and the ground lifted 13% → 16%, instant; the seat shown with its 120ms fade; the height unchanged |

An own band is the own tile and the second-person verb; "You" is set
like any name. Nothing else marks it.

**The rail.** Person cards at the rail's width, 6px apart: **You
first** (when an identity exists), then friends by their latest act of
any kind, friends with no acts last by name; **a cap of eight cards**;
**All N friends** (N the roster) at 20px/70% under the last card
whenever the cap hides anyone. A card is one press, which opens the
Friends tab at that person. The rail scrolls with the page in one
scroll region and ends where its cards end; the Feed column continues
alone beneath. The scope pill and *Show older* never touch it.

**The person card at two widths.**

| | Rail card (560) | Page card (900) |
|---|---|---|
| Unit | 560 wide, padding 12/14, radius 12, ink; 6 apart | 900 wide (two columns of 1820, 20 apart), padding 30, radius 12, ink |
| Ground under the cursor | 16% | 16% |
| Tile | 48; initial 19 at 600 (own at 700, filled); photo when one exists | 64; initial 26 |
| Name | 22/28 at 600, at the tile's top | 24/32 at 600, centred on the tile |
| Ago | 18 at 66%, tabular, at the card's right edge; none when the person has no acts | the same |
| Under the name | nothing | nothing |
| Strip | 8 under the name, at the tile's right; up to three posters 96×144, 16 apart | 16 under the head, at the card's left; up to five posters 130×195, 16 apart (714 of 840) |
| Poster | radius 6, 1px white/8, shadow `0 3px 12px oklch(0% 0 0 / .5)`; no artwork: a 6% slot naming its title at 18/66%, padding 8 | shadow `0 4px 16px oklch(0% 0 0 / .55)`; the slot's padding 12 |
| Act disc | 44px, glyph 28 at stroke 2 | 52px, glyph 32 at stroke 2 |
| Cursor ring | 3px primary | 4px primary |
| Height | 204 with acts; 72 with none | 335 with acts; 124 with none |
| A press | opens the Friends tab at this person | opens the card in place |

**The act disc.** At the poster's top right, inset 8px: a disc of ink
at .85 with a 1px white/18 ring, the act glyph centred in it on the
card's text colour at 80%; every disc the same ink, and the heart glyph alone solid rose
(`--color-love`). Two acts on one poster are two
discs stacked downward 6px apart in the pennant's mast order — love,
like, dislike, reviewed, watched, listing (UIDR-037). The glyphs are
the house's: the sentiment glyphs from `Title.Sentiment`, the bubble,
the eye and the bookmark from the pennant.

**The strip's rule.** One poster per title acted on, newest first, left
to right; every live act on the title is a disc on its poster. The
ago is the first poster's. A binge collapses: three episodes of one
show are one poster with one eye; the episode is the opened card's. A
person's card is what the person shared and says nothing about what
they did not — no sharing notes, no "How friends see you", no
"Nothing shared yet". A friend with no acts is a tile and a name. The
You card is your acts like anyone's; the filled own tile is its only
mark. A press on a poster opens the title modal speaking for the
newest act on it.

**The opened card** (Friends page only). A press on the card grows it
in place: the strip in full, wrapping at 16/16; one row per poster at
22/30 and 80% — the verb and the episode in `ActivityWords`'
vocabulary ("watched S01E03 of Sample Show", "watched and reviewed
Sample Movie"), the title at 500/96%, the poster's glyph at 22 after
it, the ago at 18/66% on the right — each row a press that opens that
act; then the foot: the key and the added date at 18/66%, Remove friend
a 32px ghost at 18/70%. The You card opens to its rows and has no
foot. The same press closes it.

**The Friends page.** A row-major grid of page cards, two columns of
900 at 1920, 20 apart, cards at their row's top so the heads share a
line; one column below a 1700px container (an 1800 viewport). Every
person, You first, then by latest act, no-act friends last; **Add a
friend** at the foot as today, at the grid's width, and the Settings
pointer under it. Opened from the rail, the page opens the named
person's card and lands on it.

**Paging.** The window is **twenty** bands. **Show older** — a 32px
ghost control at 20px/70% on the tile's edge, 10px under the last band
— appends twenty; after the third, sixty bands stand and the foot reads
**"That's the last sixty."** at 66% in the same seat, only when older
actions exist beyond the cap. At the page's top, arrivals prepend live
and the column moves down one band. Scrolled into the column, arrivals
queue behind **"N new"** — a 32px control at 20px/84% on ink at .94
with a shadow and a 20px up-arrow, 12px from the viewport's top, on
the column's reading edge — which prepends them and scrolls to the top
when pressed; N counts the queue in the current scope. The tab's count
is the window's size under the scope (20, 40, 60; a smaller scope
counts what it has). Neither the scope nor Show older touches the
rail.

**The fold.** A container query at 1600px of content (a 1700
viewport): below it the rail is not drawn, the strip keeps its three
tabs, and the column keeps every size — at 1180 the image box is 480
(an 83% slice). At a raw 2560 the 900px cap bites (the box from x=976,
a 43% slice); the app composes 2560 at 1920 CSS px, so this is a
safety, not a state.

**The couch floors and the half-size check.** Read text ≥ 22px,
secondary ≥ 18px, band titles ≥ 28px, tiles 48–64, targets 32px, the
cursor ring 3–4px, text over imagery ≥ 4.5:1 against the ink it sits
on (checked on the lowest-alpha text). Every render is read at half
size before it is accepted: the sentence, the title, the review, the
time, the tile's letter, the rail's names and agos, and each act
glyph — the heart reads as rose first, the eye is a ring with a dot,
the bubble keeps its tail, the thumb reads up from down by where its
stem sits, the bookmark keeps its notch, two discs read as two.

**Motion.** None: no parallax, no drift, no entrance. Hover is the
scrim step and the ground lift, instant; the seat's 120ms fade is the
only transition. A 400ms hover/cursor ease is the one candidate and is
not built.

**Not built.** A profile photo (the tile takes one; no protocol event
carries one); hover ease; the Watchlist in bands; Incoming's activity
in the band language.

## The model

Core idea: the Feed is the timeline of every action the network holds,
drawn as a column of pictures; the people who make it are drawn beside
it, once each, as what they last did.

- **One band component, one size.** `Discovery.FeedBand` renders every
  author from a `FeedEntry`; there is no `size` attr and no lead. It
  keeps the row's DOM contract (`id="feed-row-<activity id>"`,
  `data-component="feed-row"`, `data-kind`, `data-own`, the slot
  attributes, the `data-role`s, the `-list`/`-download`/`-ignore`
  control ids, `open_title` on the root), so the Feed's page tests are
  the regression net while the look changes underneath them. The
  band's positions are custom properties of one CSS class; the text is
  Tailwind on top.
- **One person-card component at two widths.** `Discovery.PersonCard`
  takes `width: :rail | :page` and `opened?`; the rail on the Feed and
  Watchlist tabs and the Friends page compose the same component. The
  rail card's press navigates to the Friends tab naming the person;
  the page card's press toggles `opened?`, which the host keeps.
- **The identity tile has three states and one owner.**
  `Discovery.IdentityTile` (monogram · own · photo, at 48/56/64)
  renders on the band and the person card; the card's inline monogram
  moves into it. A photo comes from the social layer as a replaceable
  profile event on the relay — kept until replaced or removed — and
  there is no such event today (`docs/social-protocol.md`: review,
  watched, listing). The tile takes `photo_url`; the view-models gain
  the field when the protocol carries one.
- **The acts strip is built from the person's activities.**
  `Discovery.Person` gains `acts`, one `Person.Act` per title acted on,
  newest first, each carrying the flags flown on it in mast order and
  every activity behind it (the opened card's rows). The flag for an
  activity and the glyph for a flag are one vocabulary
  (`Title.Flag`: the pennant's `flag/1` and glyph map extracted so the
  pennant and the strip compose it; the sentiment glyphs stay
  `Title.Sentiment`'s). `presence`, `watched`, `listed` and `reviewed`
  leave `Person`; the card reads nothing about sharing preferences.
- **The rail's roster is a projection.** `People.build/3` keeps its
  order (You first, then by latest act, quiet last by name);
  `People.rail/1` takes the first eight and says how many the cap hid.
  Pure, tested without a database.
- **Row artwork is resolved by the host, like the poster.**
  `DiscoveryLive.ActivityArtwork` resolves poster and backdrop down one
  ladder — the library entity's own image by role (`Library.Artwork`,
  the renamed `Library.Posters` with a role argument), the referenced
  tier (`TmdbArtwork`, which already warms backdrops), the TMDB hotlink
  last — and `FeedEntry.backdrop_url` carries the result; a band with
  nothing paints the inset tone. The offset crop is stamped by
  `FeedEntries` from adjacency in the scoped window. The still paints
  at `?w=1280` (a 536 CSS px box on a 4K panel), the band's poster at
  `?w=240`, the rail's at `?w=240`, the page's at `?w=320`.
- **Paging is a window with a cap and a queued head.**
  `FeedEntries.build/2` takes the window (20, 40, 60; `page_size/0` is
  20, `cap/0` is 60) and a `head` — `nil` while the reader is at the
  top, else the time of the newest band shown — and returns the
  entries at or older than the head, `has_older?`, `at_cap?` and the
  `queued` count newer than the head. A small `FeedHead` hook reports
  the column's top leaving and returning to the viewport; "N new" and
  returning to the top clear the head.
- **The fold is a container query**, not a LiveView assign: the rail is
  in the DOM whenever the tab has one and CSS hides it below 1600px of
  content; its items fail visibility and the input system skips them,
  as a closed modal's do. The Friends grid folds at 1700 the same way.
- **The Friends page is a grid** with row-major nav (Left/Right within
  a row, Up/Down across rows; the hardening pass wires it). The card
  named by `?person=` opens and takes focus, which scrolls it into
  view.
- **Not built.** Photo events, hover ease, the Watchlist in bands,
  Incoming's activity, motion of any kind.

## Acceptance criteria

The page

- [ ] `/discovery` renders at the layout's full width; from the tab strip down the Feed column is 1236px beside a 560px rail with a 24px gutter at 1920.
- [ ] The tab strip is Feed · Watchlist · Friends at every width; the scope pill sits at the Feed column's right edge on the Feed tab only.
- [ ] No band is rendered larger than another; index 0 is a band like the rest; an empty Feed shows the empty state and the rail.
- [ ] The Watchlist tab shows its rows in the left column beside the rail; the Friends tab shows no rail.
- [ ] Discovery is the one page besides Home that carries artwork, and only a row's own title artwork.

The band

- [ ] Every band is 224px tall at rest, hovered and under the cursor; it is 1236 wide in the column and keeps 224 at 1180 and at 2560.
- [ ] The band shows the author's tile (56), the poster (100×150), the sentence at 22px, the title at 28px, the year and the time at 18px, the review at 22px on two lines at most.
- [ ] The still paints in a box from the text zone's edge (x=700) to the band's right edge under the ink scrim, at `?w=1280`; the poster at `?w=240`.
- [ ] Every still is cropped `50% 30%`; the second of two adjacent bands of one title in the scoped window is `50% 38%`; a run alternates; adjacency is judged inside the scope and the window.
- [ ] An own band carries the filled own tile and the second-person verb; "You" is set like any name; no border, tint or badge.
- [ ] A band with no backdrop paints the inset tone and an empty poster slot; nothing is broken.
- [ ] The seat holds List · Download · Ignore on a friend's band and List · Download on an own band, shown on hover or cursor, with the existing behaviour and provenance.
- [ ] The time is right-aligned at the text zone's edge on every band.
- [ ] Every text on the band is `/55` or above; the lowest read text is 66% on ink.

The rail and the person card

- [ ] The rail lists You first, then friends by latest act of any kind, friends with no acts last by name; at most eight cards; *All N friends* under the last card when the cap hides anyone, N being the roster.
- [ ] A rail card is the tile (48), the name (22), the ago (18), and up to three posters (96×144) with their act discs; a friend with no acts is a tile and a name at 72px.
- [ ] No person card carries a presence sentence, a sharing note, "How friends see you" or "Nothing shared yet".
- [ ] The acts strip holds one poster per title, newest first; every live act on the title is a disc on its poster in mast order; two acts are two discs stacked downward.
- [ ] The act disc is 44px with a 28px glyph in the rail and 52 with a 32px glyph on the page, ink at .85 with a 1px ring, inset 8px at the top right; love on `--color-love` with a white heart.
- [ ] The You card is own acts like anyone's — reviews always, watched and listings when they were shared — with the filled own tile as its only mark.
- [ ] A press on a rail card opens `/discovery/friends` with that person's card open and focused.
- [ ] A press on a poster opens the title modal speaking for the newest act on that title; the modal keeps Delete on an own act.
- [ ] The scope pill and Show older leave the rail unchanged.

The Friends page

- [ ] `/discovery/friends` is a grid of page cards, two columns of 900 at 1920 and one column below 1700px of content, You first then by latest act, Add a friend at the foot.
- [ ] A page card is the tile (64), the name (24) centred on it, the ago (18), and up to five posters (130×195) with their discs; 335px with acts, 124 without.
- [ ] A press opens the card in place: the strip in full, one row per poster ending in its glyph, the key, the date and Remove friend; the same press closes it; the You card opens to its rows and has no foot.
- [ ] Remove friend works from the opened card; Add a friend works as today.

Paging

- [ ] The first window is twenty bands; the tab's count is the window's size under the scope.
- [ ] Show older appends twenty; it disappears when no older action exists; after sixty it disappears and, when older actions still exist, the foot reads "That's the last sixty."
- [ ] With the page at the top, an arriving action prepends live.
- [ ] Scrolled into the column, an arriving action does not move the column; "N new" appears at the column's head with the queue's count in the current scope; pressing it prepends the queue and scrolls to the top; returning to the top clears it.
- [ ] A scope change re-projects the window and the queue for that scope.

The fold and the widths

- [ ] Below 1600px of content the rail is hidden, the strip keeps three tabs, the column keeps every size; at a 1180 column the image box is 480.
- [ ] `page-shot` at 1920×1080, 1280×800 and 2560×1440 of `/discovery`, `/discovery?scope=you`, `/discovery/watchlist` and `/discovery/friends` render as the tables describe.

The couch floors

- [ ] No read text on the Feed, the rail or the Friends page is below 22px; no secondary text below 18px; no band title below 28px; every target is 32px or taller; the cursor ring is 3px on a band and a rail card, 4px on a page card.
- [ ] The lowest-alpha text over the scrim reaches 4.5:1 against the ink it sits on.
- [ ] The half-size check passes: the 1920 `page-shot` of each page, resized to 960×540, reads in every part named above — an acceptance step for the storybook's band, rail-card and page-card variations and for the page.

The catalog and the contract

- [ ] `identity_tile`, `feed_band` and `person_card` have stories pinning every state named here, at every size and both widths; MC0009 finds every `values:` literal.
- [ ] The Feed's existing page tests pass against the band without edits; the Friends-tab tests are rewritten to the card's new contract.
- [ ] `mix precommit` is clean: no `loading="lazy"`, every local artwork `src` width-declared, no text below `/55`.

## Anti-patterns

Standing: UIDR-038's and UIDR-045's lists, accent and edge bars, a chip
palette, a per-friend hue, social-network chrome as UIDR-038 defines it
(handles, counts, reactions, replies). This design adds:

- **A lead or a masthead** — a larger first unit; the newest is first by position.
- **A per-title crop position, or a smart crop** — one rule, measured.
- **A different still for a repeated title** — the offset and no more; a different picture would lie about behaviour.
- **A hairline, border or glass between bands** — 6px of page ground.
- **A vignette on the box's right edge** — the picture reaches the corner.
- **Motion** — parallax, drift, entrance; the seat's fade is the ceiling.
- **A sharing note on a person card** — "Doesn't share watching", "You don't share watching", "Nothing shared yet", "How friends see you"; the card shows what was shared and nothing about what was not.
- **A presence sentence on the card face** — the strip is the presence; the sentence lives in the opened card's rows.
- **A caption over the strip** — the discs say what each poster is.
- **A badge, stamp or footer band for the act glyph** — the disc is the form; the pennant stays the title surfaces'.
- **A rail heading or a "Manage friends" link** — the Friends tab names the rail and is in the strip at every width.
- **The rail as a timeline** — one card per person, replaced on the next act, bounded by the roster, never paged or grown by activity.
- **A span-based cap** — "the last two months"; the cap is a count.
- **A column that moves under the reader** — arrivals prepend live only at the top.
- **A LiveView assign for the fold** — the width is the container query's.
- **The pennant on the Library grid or Home's rails** — a person card's strip flies flags because there the poster is the act (the skill's rule, 2026-09-25).

## Records

- **UIDR-046 — the cinematic feed**: one band on the title's still under
  the ink scrim, every size named; the identity tile as the app's person
  device; the crop rule; the rail of person cards; the person card at two
  widths with the acts strip and the act disc; the window, the cap and
  the queued head; the fold; the couch floors as a house rule. Amends
  the four below.
- **UIDR-045** — rule 3: the own mark is the identity tile filled with
  the button primary, the word You set like any name, the second person
  kept; rule 5: the list surface is gone, bands 6px apart on the page
  ground, Discovery at the layout's full width with a rail beside the
  column.
- **UIDR-038** — rules 7–10 become the person card's at both widths:
  one card per person, You first, the name as the head, the key in the
  opened card's foot (7); no presence line — the strip is the presence
  (8); the body is the acts strip, one poster per title with its act
  discs, the text rows in the opened card (9); the You card is own acts
  like anyone's, the modal the place to withdraw (10). *Social-network
  chrome* admits the identity tile as the app's person device on every
  Discovery surface; handles, counts and reactions stay banned. *Wall of
  watching* is bent in the rail and the card only: watching as a
  person's presence, replaced on the next act, never a timeline.
- **UIDR-037** — a note: the pennant is a form for the title surfaces —
  named flags flying inward from a hero's edge, with a tooltip; the
  person card takes the act disc with the same glyphs, order and
  tints, because its job differs (one glyph on a 96px poster, not a name
  on a wide surface). The person card's strip flies flags on posters
  because there the poster is the act.
- **UIDR-033** — a note: a row's own title artwork is that row's
  subject; the Feed's bands carry their title's backdrop, a person card
  its acts' posters; a band or a card of an unrelated title stays
  banned; the page-level rule (rule 2) is unchanged.
- **The `user-interface` skill** — the couch floors as a house rule for
  every surface; `identity_tile/1`, `feed_band/1` and `person_card/1`
  in the inventory; the UIDR table's 046 row.
