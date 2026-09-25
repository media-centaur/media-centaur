# Discovery › Feed: the Feed's appearance — telling authors apart

**Date:** 2026-09-24 · **Status:** design in progress (campaign
`campaigns/feed-appearance.md`). Round 4 mockups in
`2026-09-24-feed-appearance-mockups/` (brief `BRIEF.md`, comparison
`index.html`, critique `CRITIQUE.md` — recommends crossing
`1-cinematic-rows` and `4-front-page`); the crop measurement
(`MEASUREMENT.md`) fixed the focal rule at 30%; round 5 (`BRIEF-5.md`)
builds the cross in four settings; the owner's decision is open. The shipped
design this starts from is `2026-09-24-feed-timeline-scope-design.md`
(UIDR-045); its scope, entry rule and toolbar contract are kept.

## Glossary

Existing terms are in `docs/GLOSSARY.md`: *Feed*, *feed row*, *Scope*,
*Author*, *Action*, *Review*, *Listing*, *Pennant*. This design adds:

| Term | Meaning |
|---|---|
| **Author mark** | Whatever visual device says who wrote a row, beyond the name itself. Today: the word You in the primary colour on an own row, nothing on a friend's. |
| **Own mark** | The author mark for the reader's own rows. |
| **Friend mark** | The author mark that tells one friend from another. |
| **Monogram** | The Friends tab's person device (`Discovery.PersonCard`): a 40px circle on a primary tint carrying the name's first letter. The app's one existing drawing of a person. |
| **Row artwork** | The artwork the row is about: the title's poster, and its backdrop, which every activity's title snapshot carries (`TMDB.Title.backdrop_path`) but no Feed surface has used. |
| **List surface** | The one inset glass container the rows sit in, hairlines between rows (Watch History's idiom). UIDR-045 rule 5. |
| **Row anatomy** | Poster, three text lines, time column, toolbar seat (UIDR-038 rule 3, amended by UIDR-045). Every author shares it. |
| **Presence** | How much of the screen the page composes at 1920×1080: what it fills, what it leaves to the scrim. |

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
   18px, band titles 28px, the lead title 44px; tiles 56/64px; posters
   96×144 on a band; the cursor ring is the TV's hover and must read
   at three metres; text over the scrim reaches 4.5:1. Rounds 4–6 were
   composed for the desk and are re-scaled in round 7 (`BRIEF-7.md`).
6. **Every rule kept or named.** What UIDR-038, UIDR-045, UIDR-037 and
   the colour rule say stands unless the chosen direction argues
   otherwise, naming the rule and the exception precisely.

## What the user sees

*Draft, pending the owner's decision:* the proposed page is
`2026-09-24-feed-appearance-mockups/F-cinematic-feed/` and its
`REASONING.md` opens with the complete table of sizes, alphas, gaps,
the crop rule, the scrim recipes, the identity tile's four states and
the toolbar seats. That table becomes this section, verbatim, once the
owner chooses. In one paragraph: the Feed is a full-width column of
**bands**, one per action, 6px apart on the page ground, each carrying
its title's backdrop in a 900px box under the base-hue scrim with the
identity tile, the poster, the sentence, the title and the review in a
dark text zone to its left and the time at that zone's edge; the newest
action is the **lead**, the same unit at 340px with the still boxed
from the text zone's edge. Every backdrop is cropped by one rule
(`object-position: 50% 30%`, measured on real backdrops), never by
hand.

## The model

*To follow the mockup round.* Standing notes that hold whichever
direction is chosen:

- **The identity tile has two states and one owner.** The monogram is
  the default and is what ships. A photo, if one ever exists, comes from
  the social layer as a replaceable profile event on the relay — kept
  until the person replaces or removes it — and there is no such event
  today: the protocol carries three addressable kinds (review, watched,
  listing; `docs/social-protocol.md`). The Feed makes the space; the
  social campaign that adds the event fills it. `Discovery.Person` and
  `Discovery.FeedEntry` would each carry the photo URL or nil, and one
  component (`Discovery.IdentityTile`, with the `PersonCard` monogram
  moved into it) renders both states on both tabs.
- **Row artwork is resolved by the host, like the poster.** The
  backdrop follows `ActivityPosters`' ladder — the library entity's own
  backdrop when the install owns the title, the referenced tier
  otherwise, the TMDB hotlink last — and a row with nothing paints the
  quiet fallback; a direction that uses backdrops needs
  `TmdbArtwork` to warm backdrops as it warms posters.

## Acceptance criteria

*To follow the mockup round.*

## Anti-patterns

*To follow the mockup round.* Standing: UIDR-038's and UIDR-045's lists,
accent and edge bars, a chip palette, social-network chrome as UIDR-038
defines it.

## Records

- UIDR-045 rule 3 is reopened by this design; the record to write
  amends it and, depending on the device chosen, UIDR-038's *state as
  decoration* and *social-network chrome* anti-patterns and the
  colour-is-signal rule in the `user-interface` skill.
