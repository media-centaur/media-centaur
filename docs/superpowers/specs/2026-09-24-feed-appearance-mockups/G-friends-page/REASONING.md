# G · Friends page — reasoning

Round 8: the Friends tab at couch scale, the full page where the roster is managed, built from the person-card anatomy the rail draws at 560. Rendered at 1920 three times with a half-size copy read each time, once at 1280×800 and 2560×1440. No JavaScript.

## Sizes

| | Value |
|---|---|
| Column | 700px, left-aligned; the tab strip across the full 1820 |
| Card | glass tier (`--glass-bg`, `--glass-border`, radius 14, blur 12); padding 26 / 32 / 22; 12px apart |
| Tile | 56, initial 22/600; monogram `oklch(72% .14 264/.18)`, 1px inset ring at .22; own: filled `oklch(62% .16 264)`, white initial 700; photo: R1's window recipe |
| Name | 22/28 600; the time 18 at 60%, tabular, right-aligned on the name's line |
| You's subtitle | "How friends see you", 18/24 at 60%, under the name |
| Presence line | 20/26 at 80%, the title 500 at 96%, the glyph 20px with 6px before it; "Nothing shared yet" at 60% in the same slot |
| Note | "Doesn't share watching" / "You don't share watching", 18/24 at 60%, under the presence line |
| Strip | "Recently watched" 18 at 60%; posters 96×144, gap 12, radius 6, 1px white at 8%, shadow `0 4px 16px .55` (the band's); "all N" the same size on a 7% fill, 20px at 60% |
| Text rows | label 18 at 60% in a 150px column; names 22/30 at 88%; separators 40%, trailing each name; "N more" 55% |
| Footer | hairline; the key in 18px mono and the added date at 60%; Remove friend a 32px ghost at 18/70% |
| Add a friend | heading 22/600; body 18 at 70%; 44px fields at 20/55%; a 44px soft button at 20 |
| Cursor | a 3px primary ring on the card's edge, radius inherited; the ground lifts to `oklch(24% .02 264/.5)` |

Nothing read is below 18px; the lowest alpha on read text is 55%.

## What the card shares with the rail's

The head's order — tile, a 16px gap, the name with the time at its right, the presence line under the name; the tile's three states and colours, 56 here and 48 there, initials 22 and 19; the name 22/600; the time 18/60% on the name's line, none when nothing is shared; the presence line 20/80% in `ActivityWords`' vocabulary, one line; the note's wording and 18/60%, under the presence line; the subtitle 18/60% under the name; the strip's label, gap, radius, border and shadow — posters 96×144 here, 64×96 there; five plus "all N" here, three there — only when the person shares watches; the glyph at 20; the 3px ring. The tile sits at the top of the text stack, so it centres on the name + presence pair at both widths. The rail may drop the surface and sit its rows on the page ground; the tab's cards carry footers and a form and need the glass.

Tab only: the two text rows, the footer, Remove friend, Add a friend.

## The four sharing states

- **Shares watches** (Cleo, Bob): the line, the strip — five and "all 9" for Cleo, three and no tile for Bob — the two rows.
- **Reviews only** (Ada, with the photo; You): the line, the note, the Reviewed row. No Wants to watch row: listings are not shared, and the You card shows what friends see.
- **Shares listings, not watches** (Nick, Sam): the line — Sam's is a listing — the note, both rows.
- **Nothing shared yet** (Theo): the words in the presence slot at 60%, no time, header and footer only.

Seven of thirty are drawn; the rest follow in the same order, nothing-shared last, then Add a friend. The episode label on a strip poster is dropped: at 96×144 it is a chip; the presence line carries the episode.

## The page's width

**A 700px column, left-aligned, under a strip that spans the full width.** The width is the strip's: six cells of 96 and five gaps of 12 are 636, plus the card's 32px sides; the "all N" tile's right edge is the time's right edge.

Not 1820: P found a person card at full width is a band, and a band wants one picture where the card has five. Not 1236, the feed column: the strip fills half the card with 600px of air beside it. Not two 700 columns: the cards' heights vary with what each person shares, a row-major grid leaves holes under the short ones, the order by latest act becomes a Z, and a rail card that opens the tab scrolled to its person wants one linear scroll. The strip stays 1820 because it is the constant across the three tabs.

**Landing** (state 3): the card's top sits 24px under the viewport's edge, the page's padding, where the first card sits unscrolled; the card above shows its last 12px, the gap.

**1280**: the same strip and column in 1180; nothing folds. **2560** raw: 700 in 2460; the UI scale renders 2560 at 1920 CSS px anyway.

## The 10-foot check

Every name, presence line, time, tile letter, poster and label reads at half size. It changed three things: the key at 55% was the weakest read, now 60%; "· 2 more" wrapped alone with a leading dot — separators now trail each name inside no-wrap groups, so a line ends with the dot and the count hugs its title; the thumbs glyph touched its title at 3px, now 6px.

## The alternative tried

Row labels above the names. It fits You's Reviewed row on one line, but a one-title row becomes a heading over a single word and every card grows two lines. The column stays: a small table the eye scans down.

## Rules touched

| Rule | Status | The exception |
|---|---|---|
| UIDR-038 rule 7 — one card per person, You first, name as title, key in the footer | Kept | — |
| Rule 8 — the header's right side is the presence line | Bent | The line sits under the name, the rail's seat, so presence has one definition; the right side holds the time only |
| Rule 9 — five posters with "all N", then the text rows | Kept in structure | Posters fixed at 96×144, not a fluid sixth; the strip only when watches are shared; the episode label dropped |
| Rule 10 — the You card as audit view: primary border, subtitle, no footer | Bent | The own tile replaces the border (two own marks are redundancy, as R1 and P decided); subtitle and no-footer kept; the note is the audit view's sharing state |
| UIDR-033 — artwork when it is the subject | Kept | The only artwork is the person's own watched posters; no still behind a card (P's finding) |
| *Social-network chrome* | Kept | No counts beyond the tab's; the key is a footer fact |

## The one thing I am least sure of

The empty right of the page at 1920: 1,100px of ground beside a 700 column is the honest width for a card sized to its strip, but on a 65-inch panel it may read as unfinished. If it does, the answer is not a wider card: accept it, as Settings does, or take a second column with its ragged rows.
