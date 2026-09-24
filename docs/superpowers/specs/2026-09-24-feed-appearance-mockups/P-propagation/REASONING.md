# P · Propagation — reasoning

An exploration, not a direction: the Feed's band (round 4, direction 1) carried to the Discovery page's other two tabs, so the owner can see whether the language travels. Deliverable: `index.html` (links `../base.css`, art from `../art/`), five states under `.state` labels. Rendered with `page-shot` at 1920×1080 three times, per-state clips from a 7000px-tall viewport, once each at 1280×800 and 2560×1440, and one scratch render of the alternative I was unsure of (an empty tile seat). Written from the renders.

## What carried over unchanged

Everything the band is, copied from `1-cinematic-rows/index.html` and not retuned: the 152px band, 10px radius, 6px gap, the ink `oklch(13% 0.02 264)`; the image box from x = 560 to the band's right edge with the 320px dissolve mask; the scrim with its pixel stops (.97 at 0, .93 at 540, .55 at 800, .16 at 1060, .06 at 1260) and the .48 right-edge vignette; hover as `--s: .8` plus the ground lifting to 16%, nothing moving; the crop rule `object-position: 50% 30%` on every backdrop (`MEASUREMENT.md` — no hand-set crop anywhere on this page); the 72×108 poster with its `0 3px 12px` shadow; the title line at 18px semibold with the 13px/60% metadata beside it; the note line at 14/20, 78%, two-line clamp, 58ch; the 20px seat at the poster's foot with `.st` words at 66% and Downloading's 3px hairline; the 13px time seat at top-right (right 20, on line 1); the identity tile in all three states with direction 1's values (18% tint + 22% ring, the 62% button-primary own fill with a white initial, the 167×94 portrait crop for the photo); the no-artwork band on the inset tone; the tab strip with the pill at the right.

## What had to change per tab, and why

### Watchlist (states 1 and 2)

1. **No tile seat.** The tile is a person device (UIDR-038 as the critique amends it: the app's drawing of a person); a Watchlist row has no person. Three options were considered. *A bookmark in the seat*: every row on this tab is listed, which is why `Logic.row_markers/2` drops "On your list" here (`list_implied?`) — a bookmark on every row is the list's own name repeated, and state as decoration. *An empty seat with the poster kept at x = 74*: rendered from a scratch copy (`alt-empty-seat.png`); 56px of ink before every poster reads as a missing column, not a spine. *No seat*: the poster takes the band's left edge at x = 18 and the text block starts at x = 108. Chosen. The text zone stays 560px so the image box and the slice are the Feed's; the text gains 56px of measure it does not use (the note stays at 58ch).
2. **Title first.** The Feed's line 1 (author + verb) has no content on a title row, so the title is the first line at y = 22, with the house's identity text beside it ("Movie · 2010", "TV · 2010") in place of the Feed's bare year. UIDR-038's *title-first row* anti-pattern is about the Feed reading as a list annotated with names; on a list of titles it is the correct order.
3. **The markers move into the seat.** The row's state words (In library, Planning, Downloading, Needs review; Tracking, Auto-grab; Next: Oct 13 — `row_markers` order) sit where the Feed seats its toolbar, always visible, at the seat's 66%. The Watchlist row has no toolbar (every verb is the modal's, `Title.Row`), so the seat is a readout. A bare listing has an empty seat (Night of the Living Dead): the same silence the Feed's seat has at rest. Nothing was added; the house's markers were re-seated.
4. **Notes displace the synopsis** as the row does: one unattributed note reads plain (Spring), several carry their names at 500/92% (Charade: Nick, Cleo). Two-line clamp; a third note is cut.
5. **The mast flies from the band's right edge**, vertically centred (the row's `self-center`), the hoist meeting the band's edge and clipped by its radius — UIDR-037's row placement. The pennant is `.pennant` / `.pennant-on-image` from `app.css` with the tokens resolved: 22px, 0.72rem/600, the clip-path polygon, dark glass at 72% for neutral flags, the rose fill for love. Up to three flags fit the band (74px in 152). The neutral flag over a bright still (Cleo over Sintel's hair) reads because the glass is the flag's own ground; the vignette under it is kept from the recipe and helps.
6. **No time.** A watchlist row has none, so the band's top-right is empty and the mast is the band's one right-side element.

### Friends (states 3 and 4)

7. **A person's card is the band of their latest act.** Left to right on the band's first line: the tile at x = 18 (top 14, centred on the name line, not on the card), the name at 18px semibold at x = 74 — the poster's column, there being no poster — and under it the presence sentence at 15px/80% with the title at 500 and the sentiment glyph; the "ago" in the time seat; the still from x = 560. Read as the Feed reads: person, sentence, picture. The card is one markup with the band (`.card` shares `.row`'s ink, image box, scrim, hover); its height is the content's, set at render, one band at minimum.
8. **The shelves sit in the text zone under the sentence**, one 126px label column (`.sec`) for all three: Recently watched as 56×84 posters (the shipped Feed poster size) with the "all N" tile on a 7% fill; Wants to watch and Reviewed as 14px/88% text rows, separators at 40%, "N more" at 55%, the glyphs inline. The house's "Recently watched" heading above a six-column grid became an inline label so the three shelves share one column. The rows are capped as the card caps them (5 / 3 / 3).
9. **The footer** is the key (11px mono) · added date at the left and Remove friend as a 12px ghost at the text zone's right edge (x ≈ 604), with 14px of space above it and no hairline (the band has no hairlines).
10. **The You card**: the own tile is the own mark and "You" is set like any name (direction 1, decision 4); the primary-tinted border is dropped — two own marks would be redundancy. "How friends see you" becomes the You card's footer fact, where a friend's card has the key, so the header stays one anatomy across all cards.
11. **Nothing shared** (Femi): the inset tone, no still, the presence line reads "Nothing shared yet" at 55%, header and footer only, one band tall.
12. **The still is the presence line's title** — Charade for You, Sintel for Cleo, Metropolis for Nick, Night of the Living Dead for Ada. Whether it is the card's subject, honestly: **no**. UIDR-033's rule is that artwork on a surface means "this is what the surface is about". The card is about a person; the still is what they last did, which is the card's one time-bound fact. It is decoration keyed to a fact — better than a rotating band of an unrelated title, worse than a Feed band whose picture is the row's own title. Consequences the render makes visible: the card's picture changes every time the person acts, so the Friends tab's look is unstable in a way the Watchlist's is not; two friends whose last act was on one title show one still twice; a person whose last act was on a title with no artwork gets the ink card though their strip is full of posters. The case for it: the presence line is rule 8's headline fact and the card reads as a captioned still, exactly as the Feed does. The case against: it puts a title's picture on a person's card. I built it because the brief asked; I would not argue for it over the Feed's band.

## What did not fit

- **The Recently watched strip as the card's artwork.** Today it *is* the card's picture: a six-column grid at ~116px per cell. In the band language two pictures compete for one card; the still wins and the strip shrinks to thumbs. The strip's at-a-glance recognition (five big posters, one look) is lost; at 56×84 the posters are identifiers, not pictures. This is the honest cost of point 12 and the reason the Friends tab resists the language: its artwork was already there, plural, and the band wants one picture.
- **The episode label** ("S01E11" on a watched poster, a rounded pill at the cell's corner) has no seat: at 56×84 it is a badge over a thumbnail and DESIGNER.md forbids it. Dropped; the tooltip would carry it. A finding, not a fix.
- **Variable card height.** The Feed's rhythm is 152px, constant; the Friends column runs 276 / 262 / 262 / 152 / 152. Set at render, never on hover, but it is not the Feed's column.
- **Add a friend** is a form, not a row; it is drawn on the page ground at the tile's edge as the Feed's empty state is. The band language has nothing to say about it.
- **The right side of the strip** is empty on the Watchlist and Friends tabs (the pill is the Feed's scope and leaves with it — state 5). At full width that is 1,500px of hairline with nothing above its right end.

## The width comparison

| | Full width (1820 at 1920) | 1280 container |
|---|---|---|
| Band image box | 1260×152 → 21% slice | 720×152 → 37% slice |
| What the slice catches | Sintel's eyes; Charade's two faces; Pioneer One's doorway silhouette; Night of the Living Dead as a colour field with heads; Nosferatu's eclipse and a face at the far right | Sintel's face and the dragon; both Charade faces whole; Pioneer One's figure and the green coat; the Living Dead heads with the moon; Nosferatu's face beside the eclipse |
| Mast distance from the title | ≈ 1,700px | ≈ 1,100px |
| You card (276px) image box | 1260×276 → 39% slice | 720×276 → 68% slice (the Metropolis robot whole, Hepburn's face whole) |

The Friends tab gains the most from 1280 because its cards are tall: at 720 wide the still is nearly a frame. The Watchlist gains the same 37% the Feed would, and the flags come 600px closer to the words. The strip is width-agnostic. Whichever width the Feed takes, the other two tabs must take it — a tab switch that changes the container's width would move the h1's right edge and the pill's seat, which is the one constant the three tabs have (state 5).

**1280×800**: `.content{max-width:none}` gives 1180px bands, a 44% slice; four bands per fold; the type and seats identical. **2560×1440**: 2460px bands, a 14% letterbox; the mast is 2,300px from the title. The app's UI scale (screen ÷ 1920) renders a 2560 monitor at ~1920 CSS px, so the raw 2560 check is the edge case.

## Rules touched

| Rule | Watchlist | Friends |
|---|---|---|
| **UIDR-033** artwork is the subject | Kept in substance, as the Feed argues it: each band shows only its own title's still and poster. | Bent: the still is the presence title's, on a person's card. Stated above as decoration keyed to a fact, not the subject. |
| **UIDR-037** the pennant on every title surface; the row bleeds the mast into its right padding so the hoist meets the border; rule 3, the Feed has no mast | Kept: the mast at the band's right edge under `overflow: hidden`, the `on_image` variant the app already has for imagery. The Feed still has none; the Watchlist keeps its own. | n/a |
| **UIDR-038 rule 7** one card per person, You first, the name as the title, the key in the footer | | Kept. |
| **UIDR-038 rule 8** the header's right side is the presence line | | Bent: the presence sentence moves under the name (the band's text zone) and its "ago" to the band's time seat; the right side is the picture. |
| **UIDR-038 rule 9** the strip of up to five posters with "all N", then the two text rows | | Bent: the posters shrink to 56×84 and the heading becomes an inline label; order and caps kept; the episode label dropped. |
| **UIDR-038 rule 10** the You card is the audit view, primary border, subtitle, no footer | | Bent: the own tile replaces the border (the Feed's own-mark move, UIDR-045 rule 3 as round 4 replaced it); the subtitle sits in a footer the You card now has; no Remove friend; the audit-view role unchanged. |
| **UIDR-038** *state as decoration* | Kept: the seat's words are the row's own markers, moved, not added; the bookmark-in-the-seat was rejected on this rule. | Kept. |
| **UIDR-038** *social-network chrome* | | Bent as the Feed bends it: the tile is the app's person device; the key stays a footer fact. |
| **UIDR-045 rule 5** one list surface with hairlines | Broken on all three tabs, consistently, as direction 1 broke it. | |
| **UIDR-041** Settings cards | Does not apply. The Add-a-friend form is not a settings card. | |
| **Text ≥ 55%** | Kept: 55% floor (keys, "N more", the empty presence); separators at 40%. | |
| **No JavaScript, no animation** | Kept: none at all; the only transition is the scrim's `--s` on hover, instant. | |

## Beyond Discovery

**Home's Continue Watching.** Already backdrop cards: a 453px card with a gradient scrim and a `.text-on-image-lg` title. The band is the same material at row scale — a still under a base-hue scrim with a dark text zone — so the two scrim recipes could be one recipe with two stop sets, and the tile-poster-text spine could be Home's card anatomy at a different aspect. But Home's card is a 16:9 box showing the whole still and the band shows a fifth of one; Home should keep its cards. The language propagates as a material, not as a component.

**History.** Rows of what was watched, with a time axis: the band fits on paper — poster at the edge, title, episode and progress in the seat, the time in its seat. What breaks it is the data: History is long and repetitive, a run of ten episodes of one show is ten bands of one still, and the 8% offset rule covers a pair, not a run. A wall of one picture is the anti-pattern with a picture. If History takes the band it takes it for the first group only; more likely it keeps its list.

**Incoming's activity.** The best fit outside Discovery. A title being acquired is a title, the acquisition state (Downloading with the hairline, Needs review, Planning) is exactly the seat's vocabulary, and the still gives a download the identity the release name hides. Two costs: Incoming has `.page-side-dim-calm` because UIDR-033 found the standard ramp already read as a band there, so a column of bands re-opens that decision; and the row's technical detail — release name, size, indexer, speed — has no seat in the band, which holds one line of words.

## Trade-offs, and the one thing I am least sure of

- **The Watchlist propagates cleanly; the Friends card does not.** The Watchlist band is the Feed band minus a person; the Friends card is a Feed band with a person's ledger under it, and its picture is not its subject. The finding is that the language travels where the row *is* a title and strains where it is not.
- **The mast at the far right at full width** is the Feed's time-seat problem again: the flags are the row's most social fact and they sit 1,700px from the title. At 1280 they are closer; a mast at the text zone's edge (x ≈ 560) would put the flags over the dissolve, which the pennant's dark glass could take. Not tried.
- **Five posters at 56×84 versus one still.** The one thing I am least sure of: whether the Friends tab is better served by the still it gained or the big strip it lost. The render says the cards are handsome and the strip is now a list of stamps; the owner should judge against the live tab's grid.
- **The You card's subtitle in a footer** is a small invention; the alternative (a third header line) would break the one-anatomy header.
- **Eight distinct stills, no adjacent duplicates** on the Watchlist by the data's design; a Watchlist with two cuts of one title, or a Friends tab where two people last acted on one title, shows the repeat.
