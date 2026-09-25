# H · Friends page — reasoning

Round 9: `G-friends-page` redrawn breathable and poster-led, as a two-column grid. Three 1920 passes, each read at half; once at 1280 and 2560. No JavaScript.

## Sizes

| | Value |
|---|---|
| Grid | two columns of 900 at 1920, 20 apart, row-major, cards at the row's top; one column below a 1700 container (viewport 1800) |
| Card | ink `oklch(13% .02 264)`, radius 12, padding 30; **371** shares watches · **149** with a note · **123** nothing shared |
| Tile | 64, initial 26/600; own filled `oklch(62% .16 264)`, white 700; photo per R1 |
| Name | 24/32 600; the ago 18 at 66%, tabular, at the card's right edge |
| Presence line | 22/30 at 80%, title 500 at 96%, glyph 20; "Nothing shared yet" at 66% |
| Note slot | 18/24 at 66%: "Doesn't share watching", or "How friends see you" on You |
| Caption | "Recently watched" 18/24 at 66%, 20 under the head, 10 over the strip |
| Strip | six cells across 840, 12 apart, each ≤ 130 → **130×195**; radius 6, 1px white at 8%, shadow `0 4px 16px .55`; no-artwork slot a 6% fill naming its title at 18/66%; "all N" 20 at 66% on 7% |
| Cursor | 4px primary ring, ground 13 → 16% |
| Open card | rows: label 18/66% in 150, names 22/88%; foot: key and date 18/66%, Remove friend a 32px ghost at 18/70% |

Nothing read is below 18px; one secondary alpha, 66%. The 1080 fold holds two rows and the third row's heads.

## The poster size

Five at 130×195. The card has 840 inside; six cells 12 apart make exactly 130, the full width with no slack. Four at 158×237 was rendered: richer, but 42px more card for one fewer title, the third row leaves the fold, every hole grows by 42, and 130 already reads at half. Cells shrink to the 120 floor before the fold — hence 1800, not the brief's 1500: two strips at the floor plus sides need 1700 of content. Also tried: cells growing with the column (176×264 at 1280) — lush, but no ceiling (246×370 at 1700) and a second size on one component. Below two columns the strip sits at the card's left, at 1280 and at a raw 2560 alike (the app composes 2560 at 1920 CSS px).

## What left the face, and where it went

The Wants to watch and Reviewed rows, the key, the added date, Remove friend — all in the **open card**: a press grows it in place (the app's `expanded?` state, which "all N" already invokes) to every shelf in full (Cleo's nine posters wrap to two rows), the text rows, and a foot with the key, the date and Remove friend. The same press or Back closes it; state 4 draws Nick's. You opens to its Reviewed row, no foot. No "Manage" verb: a second target on every card for a fact read once.

## The grid and its nav

Row-major, You then latest act. A row is its taller card's height, both cards at its top, so the heads share a line. The card is one item: Right → the next card in the row, Down → the card below, Up from the first row → the strip, Left at a row's first card a wall (`gridNavigate`). Opened, its posters and names become items. Thirty friends are all on the page, nothing-shared last, Add a friend at the foot — fifteen rows, about four folds; a roster is bounded, and a window hides a friend behind a press.

## Shared with the rail's card, and differing

**Shared**: the head's order (tile, name, the ago at the right, presence under the name, the note slot under that); the tile's three states; name 600; ago 18/66%, none for nothing shared; presence 80% in `ActivityWords`' vocabulary, title 500/96%, glyph after; the note's and the caption's words at 18/66%; the strip's radius, border and empty fill, only for watch-sharers; ink, radius 12, the 13 → 16% lift; the order and the sharing states.

**Differing**: tile 64 / 48; name 24 / 22; presence 22 / 20; posters 130×195 / 72×108, 12 / 8 apart; five and "all N" / three; padding 30 / 12–14; cards 20 / 6 apart; ring 4 / 3; the empty slot names its title here; the grid; a press opens the card here, the tab there.

## The 10-foot check

Every name, presence line, ago, note, caption, initial, poster and "all N" reads at half. It changed one thing: the ring, 3 → 4px — at half, 3px was a faint line on a 900-wide card, and the 3% lift cannot carry it alone.

## Rules touched

| Rule | Status | The exception |
|---|---|---|
| UIDR-038 rule 7 — one card per person, You first, name as title, key in the footer | Bent | The key is in the open card's foot |
| Rule 8 — presence at the header's right | Bent | Under the name, the rail's seat; the right holds the ago |
| Rule 9 — five posters with "all N", then the text rows | Bent | Posters at 130×195; the rows only when open |
| Rule 10 — the You card's border, subtitle, no footer | Bent | The own tile replaces the border; the subtitle takes the note slot |
| *Wall of watching* | As the rail | One strip per person, replaced by the next watch |
| UIDR-033, *social-network chrome*, no backdrops, hover height, text ≥ 55%, no JS | Kept | Opening is a press, not hover |
| The brief's fold at 1500 | Bent to 1800 | The strip's arithmetic |

## The one thing I am least sure of

The empty cell beside a short card: at thirty friends about half the rows pair a watch-sharer with someone sharing less, leaving 220–250px of ground under the shorter one. Top alignment keeps the heads on one line and the brief forbids a placeholder; if the holes read as unfinished on the panel, the fix is column-major newspaper columns, which break Left/Right — not a taller short card.
