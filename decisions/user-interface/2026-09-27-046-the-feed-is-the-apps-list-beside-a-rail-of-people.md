---
status: accepted
date: 2026-09-27
amended: 2026-09-28
---
# The Feed is the app's list, beside a rail of people

Amends UIDR-045 (rules 3 and 5), UIDR-038 (rules 7–10, *wall of watching*, *social-network chrome*), UIDR-037 (the pennant as a form) and UIDR-033 (Discovery carries the scrim; a person card's posters are its subject). Design: `docs/superpowers/specs/2026-09-24-feed-appearance-design.md` and the mockup rounds under `docs/superpowers/specs/2026-09-24-feed-appearance-mockups/` (rounds 4–9 settled the cinematic band; rounds 10–13 replaced it). Campaign: *Feed appearance*, complete 2026-09-27 (`campaigns/README.md` § Complete; the file is in git history at `6c362a6c`).

## Context and Problem Statement

UIDR-045 put every author on one row anatomy and marked an own row with the word You alone; the owner found it too quiet, and asked for a Feed that could be told apart at a glance and be "gorgeous". Nine mockup rounds settled a cinematic page — 224px bands on the title's backdrop under an ink scrim, at couch type sizes, across the layout's full width, beside a rail of person cards — and it shipped in five phases on 2026-09-25.

The owner's first look at the shipped page on the desk traced every complaint to the still: the dark box it sat in (a unit darker than its page reads as a hole, the inverse of every other surface in the app), the second picture beside the poster, the time pinned to the still's edge in the middle of the row, the picture on the right. Four further rounds (10–13) tried the ground, the logo in the poster's place, the picture's position, and finally no picture; the owner chose the poster row on the app's own list idiom, then asked for the type to come down to Home's scale and for Discovery to take Library's frame.

## Decision Outcome

The Feed is a list of the app's rows, on the app's page, in the app's type; a person is their acts.

1. **The row** (`Discovery.FeedRow`). One action per row: the identity tile at 40, the poster at 80×120 (the 240 derivative the rail's posters share), then who did what (the sentiment glyph after the verb when the review gives one), the title and year, the review at two lines at most, and the relative time at the row's right edge — all hung from the row's top line. Type on the app's ramp: 16px words, an 18px title, 14px for the year and the time. No still, no scrim, no image box; a title without a poster shows the empty slot. Rows sit in a hairlined column with no ground of their own; hover is a 5% fill. The toolbar is a fixed 32px seat under the words, shown on hover or focus, as UIDR-045 set it. An own row is the filled own tile and the second-person verb; nothing else marks it.
2. **The identity tile** (`Discovery.IdentityTile`) is the app's one drawing of a person: a circle with the name's first letter, or a photo when one exists; the reader's own tile filled with the button primary and a white letter. Two sizes: 40 on a row and the rail's card, 48 on the Friends page's card. "You" is set like any name.
3. **Discovery takes Library's frame.** The page header at the top with the standard margin, the page scrim every page but Home carries, the tab strip and the scope pill under the header. The Feed and the Watchlist sit in the layout's 1280px container like every page but Home; the Friends tab alone opts out to the full width for its two-column grid, which folds at 1700.
4. **The rail.** Beside the Feed and the Watchlist, above 1100px of content (one column below): person cards at 480 — You first (when an identity exists), then friends by their latest act of any kind, friends with no acts last by name, eight at most, *All N friends* under the last card when the cap hides anyone. A card is one press, which opens the Friends tab at that person. The rail is a summary of the Friends tab, never a timeline; the scope and *Show older* never touch it.
5. **The person card at two widths** (`Discovery.PersonCard`), one component. The head is the tile and the name — no clock: the card says what a person did, the Feed says when. Under it the **acts strip**: one poster per title acted on, newest first (96×144 on the rail, three shown; 130×195 on the page, five shown), each under its **act glyphs** — a 36px strip on the card's ground with the glyphs for what the person did centred as a group in mast order (the opinion, the eye, the bookmark): one act in the middle, two as a pair, three across. The glyph is the heroicons solid set, matte white at 78%, **gold at the grade** — two or more friends did that act on that title; the heart is not rose here. A title without a poster is named in its slot. A card says nothing about what a person withholds; a friend with no acts is a tile and a name; the You card is own acts like anyone's. The rail's card is a row in a hairlined list with no ground; the page's card sits on the inset tone, since a grid needs cells. A press on a poster opens the title with the newest act on it; on the Friends page a press on the card opens it in place to every act as a row (the verb, the episode, the title, the glyphs, the ago) and, for a friend, the foot with the key, the added date and Remove friend.
6. **Paging.** A window of twenty rows; *Show older* appends twenty to a cap of sixty ("That's the last sixty."). Arrivals prepend live at the page's top; scrolled into the column they queue behind "N new", which prepends them and scrolls to the top. The tab's count is the window's size under the scope.
7. **No still, no crop rule.** The Feed carries no backdrop; the crop rule and the adjacency offset measured for the bands are not built. `ActivityArtwork` reads the poster alone.
8. **The type scale is the app's, not the couch's.** The mockup rounds' couch floors (22px words, 28px titles) were judged on the desk against Home, the app's reference, and found too large for the interface-scale setting; Home's ramp is the scale every page composes at, and the interface-scale preference is how the couch is served. No surface takes its own type floors.

### Consequences

* Good, because the author is found without reading at any roster size: the filled tile and the second person mark an own row, the letter and the name a friend's.
* Good, because every complaint of 2026-09-26 is answered by removing its cause, and the crop machinery with it.
* Good, because the Feed reads as the rest of the app — Library's frame, Home's type, Watch History's rows.
* Bad, because the cinematic presence the campaign opened for is set aside; the poster is the row's one picture. Rounds 5–9 stand in the mockups folder should it be wanted again.
* Bad, because a poster's printed title still doubles the typed one beside it; the logo in its place (round 11) was drawn and not chosen.
* Bad, because the fixed-slot scan of the act glyphs — "the eye" at one x on every poster — is given up for balance; the order within a group is kept.

## Anti-patterns

* **The still on a row** — a second picture of the title beside its poster, in another aspect and grade.
* **A unit darker than its page** — a row, card or band on a ground below the page's reads as a hole.
* **The time in the middle** — a time aligned to anything but the row's edge.
* **A clock on a person card** — when is the Feed's fact.
* **Sharing notes** — "Doesn't share watching", "Nothing shared yet": a card shows what was shared and says nothing about what was not.
* **Per-surface type floors** — a page whose text is sized for a distance the interface-scale setting already serves.
* **Fixed glyph slots** — an act glyph at the poster's edge because its slot is there.

## Amendment 2026-09-28 — the grade has three tiers, progressive by count

Rule 5's grade ("gold at the grade — two or more friends did that act on that title", the glyph otherwise matte white) is replaced. A two-tier render check had found silver could not separate from matte white; with the plain tier a white line drawing (the heroicons outline set, love a hollow heart) the three separate, so the grade has three tiers: **plain**, **silver**, **gold** — silver and gold the solid glyph in brushed metal: a three-stop sweep with its highlights held below white, under a fine grain running bottom-left to top-right, subtle enough to read as a surface rather than scratches at 28px. Every flag takes the same two metals; a dislike-specific red metal was rendered and set aside for now.

The grade is progressive by count, for every flag alike: one person is plain, two silver, three or more gold. Every person counts once per flag on a title, **the reader included** — the old rule left the reader out, so "you and one friend liked it" stayed matte. An act is not weighed against another (a thumbs down does not lower a thumbs up); a share-based rule was considered and set aside as a model for a larger scale of data. `DiscoveryLive.Grade`'s moduledoc is the authority from here on. The pennant does not take the grade.

## Amendment 2026-09-28 — the social glyph, on every title surface

The act glyph is renamed the **social glyph** (`Title.SocialGlyph`), and `DiscoveryLive.Grade` moves to `Title.Grade`. UIDR-049 removes the pennant: the grade is drawn on every title surface — title rows and the title detail's social capsule — from one feed (`Activities.activity_for/1`) with the reader counted, so the amendment's "the pennant does not take the grade" no longer holds. The opened card's rows draw their flags at their grades.

## Amendment 2026-09-28 — the metals are smooth

The grain is removed: silver and gold are the three-stop sweep alone, with no noise over it. Lowered to a faint texture, the grain still read as rough, so the owner dropped it. `.social-glyph` in `app.css` is the authority.
