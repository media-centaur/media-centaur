# Remove the pennant and the rose — design

Date: 2026-09-28. Status: decided 2026-09-28 (§ 5).

Follows UIDR-046's 2026-09-28 amendment. The social surfaces (the person
card's social glyphs and the grade) lead; the title surfaces are brought in
line with them.

## 1. Glossary

Terms already in use, restated so this document is self-contained:

| Term | Meaning |
|---|---|
| **Act** | One person's live activity of one kind on one title: a review, a watch, a listing. |
| **Flag** | Which of six an act shows as: love, like, dislike (a review by its sentiment), reviewed (a review with no sentiment), watched, listing. `Title.Flag`. |
| **Mast order** | The fixed order of the six flags: love, like, dislike, reviewed, watched, listing. The name comes from the pennant; see § 4 for its rename. |
| **Social glyph** | The heroicon drawing of one flag: heart, thumbs up, thumbs down, speech bubble, eye, bookmark. Formerly *social glyph* (UIDR-046); renamed 2026-09-28. |
| **Grade** | How many people the reader knows did one flag on one title: **plain** (one — a white line drawing), **silver** (two), **gold** (three or more) — silver and gold the solid glyph in brushed metal. The reader counts. `DiscoveryLive.Grade`. |
| **Acts strip** | The person card's row of posters, each under its social glyphs. |

Terms this change retires:

| Term | Fate |
|---|---|
| **Pennant**, **mast** | Removed. `Components.Title.Pennant`, its CSS, its story, its test. UIDR-037 is superseded. |
| **Love colour** (rose, `--color-love`) | Removed. The heart is drawn like every other glyph. UIDR-040's "love keeps the one warm hue" is amended. |
| **Line weight** (`Flag.glyph(_, :line)`) | Removed. It existed only because the outline heart was drawn solid for the rose; with the rose gone, the outline set is the line drawing. |

New terms:

| Term | Meaning |
|---|---|
| **Social capsule** | The title's glyphs, at their grades, on a dark ink pill, for a title surface over imagery: the title detail's hero, upper right. A control: pressing it opens the social panel. |
| **Social panel** | The glass panel the social capsule opens, anchored beneath it over the backdrop: every review on the title, then one sentence per flag that carries no text. The one place the modal names who did each act. |
| **Lead review** | The review the modal was opened from (a Feed row, a person card), shown above the synopsis. |

## 2. Where the pennant and the rose are today

| Surface | Today | Code |
|---|---|---|
| Title detail hero (Home, Library, Discovery, Incoming) | Pennant mast from the hero's right edge | `detail_panel.ex:202`, `CinematicShell` `:hero_mast` |
| Watchlist rows | Pennant mast bled into the row's right padding | `title/row.ex:73` via `discovery_live.ex:863` |
| Incoming search results | Same row, same mast | `acquisition/media_results.ex:156` |
| Review modal | The Dislike / Like / Love choices are pennants | `review_modal.ex:66-81`, `.pennant-choice` |
| Feed row | Rose heart after the verb | `feed_row.ex:93` → `Title.Sentiment` |
| CSS | `--color-love`, `.pennant*`, `.text-love`, `.detail-hero-mast` | `app.css:115-121, 900, 2949-3010` |

The feed behind every mast is `Activities.friend_activity_for/1`: every
current friend's acts on the given titles, plus the reader's reviews only.

## 3. Design

### 3.1 One count, every surface

The grade on a title surface is the same number as on a person card for
the same title and flag. Today the two are fed differently: the person
card counts every known person including the reader's watches and
listings; the title feed drops the reader's watches and listings. The
title feed takes the reader's every act, so "you and one friend watched
it" is silver on both. `grades/1` moves from `DiscoveryLive.People` into
`Grade`, and both surfaces call it.

`friend_activity_for/1` becomes `activity_for/1` (it is no longer
friends only); its row shape is unchanged.

### 3.2 The social glyph as one component

The social glyph markup lives inline in `PersonCard` today. Three more
surfaces need it, so it becomes a component with a story:
`Title.SocialGlyph.social_glyph/1` (`flag`, `grade`, `class`) and
`social_glyphs/1` (a title's flags with their grades). The brushed-metal
CSS moves from `.act-slots` to the glyph (`.act-glyph`/`.act-icon` become `.social-glyph`/`.social-icon`), so it works outside a person
card. `Title.Sentiment` and its story are removed; the feed row renders
its sentiment through `social_glyph` at plain.

### 3.3 Title detail hero — the social capsule and the social panel

Mockups: `2026-09-28-remove-pennant-and-rose-mockups/` (round 1:
`1-at-rest`, `2-open` 2b, `3-from-review`; `build.py` regenerates them).

**The social capsule.** In the hero's upper right, 12px in from the panel's
top and right edges: a dark ink pill (`oklch(12% 0.015 264 / 0.82)`, a
1px white/12 inner ring, blur) holding the title's glyphs, 24px
glyphs at their grades, 12px apart, then a 12px chevron. The ink ground
is what makes the plain white line drawing and the metals read over any
backdrop. No names in the capsule. It is a button and a nav item,
present whenever the title has any act; `aria-expanded` follows the
panel. `CinematicShell`'s `:hero_mast` slot is renamed `:hero_corner`.

**The social panel.** Pressing the capsule opens a glass panel anchored
beneath it, 420px wide, over the backdrop — the glass menu's surface
and dismissal (click-away, BACK, pressing the capsule again), never
pushing the modal's content. It lists:

1. every review on the title, newest first: the identity tile, the name
   (`Format.person_name/1`, "You" for the reader), the sentiment glyph at
   its grade (or the reviewed glyph), the relative time at the right,
   and the text beneath when there is any;
2. under a hairline, one sentence per text-less flag in flag order —
   the flag's glyph at its grade and the pennant's sentence ("Nick, Sam
   and you watched this", "Cleo wants to watch this").

The panel scrolls past its max height (460px). Its entries are not
controls. This is the one place the modal says who did each act, so a
gamepad reader can see it.

**The lead review.** When the modal is opened from a review, that
review leads the prose above the synopsis, as the note does today, now
drawn as the identity tile, the name, the sentiment glyph at its grade,
then the text. The reader's own review reads "You" like any other. The
watchlist note (`intent_note`) keeps its current unattributed line.

### 3.4 Title rows (Watchlist, Incoming search results)

The glyphs at the row's right, vertically centred, where the mast
was — no capsule, since the row is on the app's ground like the person
card. No names; the grade says how many, the title's view says who.
The hover tooltip keeps the pennant's sentence ("Nick and you watched
this"), moved to the glyphs.

### 3.5 Review modal

The three choices become the house `segmented_control` (Dislike, Like,
Love), none pressed at open; pressing the pressed one clears it, as
now (the handler's rule, not the control's).

### 3.6 Feed row

The sentiment glyph after the verb is `social_glyph` at plain: a hollow
heart like the hollow thumbs. No rose.

### 3.7 Person card

Unchanged in look. The strip renders through `act_group`; the opened
card's rows render their flags through `social_glyph` at the act's grade
(today: solid at 80%, ungraded).

## 4. What is removed

- `Components.Title.Pennant`, `storybook/title/pennants.story.exs`, the
  `_title.index.exs` entry, `pennant_test.exs`.
- `Components.Title.Sentiment`, `storybook/title/sentiment_glyph.story.exs`.
- `Flag.glyph/2`'s `:line` weight and the solid-heart exception.
- CSS: `--color-love`, `.pennant-mast`, `.pennant`, `.pennant-love`,
  `.pennant-on-image`, `.pennant-choice`, `.text-love`.
- `Activities.pennant_author?/2` and the own-review-only rule.
- "Mast order" is renamed **flag order** (`Flag.order/0`).

Docs: UIDR-037 superseded by a new UIDR; UIDR-040 and UIDR-046 amended;
`docs/GLOSSARY.md` (Review, Sentiment, Ignored, Feed); `docs/social.md`;
the user-interface skill's Pennant recipe; the wiki's `Social.md`
(§ where a friend's activity shows, the Review dialog, List),
`Watchlist.md` (rows, title view).

## 5. Decisions (2026-09-28)

1. **Names**: *social glyph*, *social capsule* and *social panel* (the owner's; "act" terms were rejected, and *act glyph* is renamed in code and current docs).
2. **Who, on the hero**: no names in the capsule; the capsule opens
   the social panel (reviews, then one sentence per text-less flag), over
   the backdrop. Glyphs at 24px. Tiles inside the capsule, a Reviews
   view, a reviews block in the prose band and a section at the body's
   foot were considered and set aside.
5. **Lead review**: kept, with the tile and the sentiment glyph.
3. **Rows**: the glyphs with no ground.
4. **Review modal**: the segmented control, words only.

## 6. Test strategy

- `Grade.grades/1`: pure unit tests (moved from `People`), including the
  reader's watch counting on a title surface.
- `SocialGlyph`, `SocialCapsule`, `SocialPanel`: stories for the flag × grade
  matrix, the capsule on imagery, the panel with reviews only, with acts
  only and with both (no markup assertions, per the testing policy).
- The social panel's content (reviews newest first, the text-less flags'
  sentences in flag order) is a pure function with unit tests.
- Title detail host: pressing the capsule opens the panel, click-away
  and BACK close it (LiveView test on the open assign and the rendered
  `aria-expanded`).
- `activity_for/1`: the reader's watched and listing acts are included;
  a former friend's are not.
- Detail panel, title row, review modal, feed row: rewrite the pennant
  assertions against `data-flag` / `data-grade` on the glyphs; the
  review modal's clear-on-second-press stays covered.
- Credo/boundaries/precommit green; a page-shot of the hero, a watchlist
  row and the review modal.
