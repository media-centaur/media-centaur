# 3 · Editorial list — reasoning

Deliverable: `index.html` (links `../base.css`). Rendered with `page-shot` at 1920×1080; every state in the brief is on the one page under a `.sec` label.

## Style

One column of rows on the page ground. No card per entry: a row is bounded by a 1px hairline at 8% alpha above and below and by nothing else. Poster 56×84 on the left; three text lines — the sentence (15px), the title (16px semibold) with the year (13px, 55%), the review text (14px, 70%, four-line clamp) — and the relative time in its own 72px column on the right (13px, 55%, tabular figures, right-aligned). The time column holds nothing else, so the times stack into a vertical axis down the column's right edge. The hairlines, the poster column and the time column are the three verticals the eye tracks; the text between them is the content. System fonts, dark slate, the page's own radial ground, no glass. Colour: the rose heart, "You" in the primary, the primary underline and the primary cursor ring; everything else is the neutral ramp.

## Decisions

1. **Time in its own column.** UIDR-038's line 1 ended with "· 12m ago". Here the sentence ends at the verb (or the sentiment glyph) and the time moves to a fixed-width right column on line 1's baseline. The sentence gets shorter and reads as a sentence; the time axis becomes one visible column instead of eleven fragments at eleven x-positions. Tabular figures keep "12m" and "3w" the same width so the right edge does not stutter.
2. **Hairlines, not cards.** A feed is a stream of homogeneous rows. A card per row repeats a border, a radius, a shadow and a blur N times to say "this is one item", which one hairline already says. Dropping the card also drops the 8px gap and the 16px inner padding on every row; the same eleven entries take less height and the column reads as one list.
3. **Hover is a fill band, not a lift.** `oklch(93% 0.01 264/.065)` on the row, edge to edge, no radius, no transition on the fill (only the toolbar's 120ms opacity fade). It sits between the two hairlines and reads as the row lighting up in place.
4. **The toolbar seat spans the time column.** The seat is round 2's fixed 20px seat at the foot of the text block, empty at rest. It extends under the time column so Ignore (or Delete) sits on the same right edge as the time. The time uses line 1's height only; the seat uses the bottom 20px; they never overlap. The row's left edge holds the poster, its right edge holds the time and the destructive action, both flush with the column.
5. **The review text has a measure.** `max-width: 72ch` on line 3. At 920px the text block is about 736px wide, over a hundred characters per line at 14px; the cap keeps the review readable and leaves air before the time column.
6. **"Show older" on the reading edge.** Left-aligned with the text column after the last hairline, as the list's next line rather than a centred button.
7. **The empty state sits in the list's column** on the reading edge: headline 16px semibold, body 14px at 70%, one ghost action. No illustration, no centring.
8. **The count is omitted at zero.** The You-empty state's tab reads "Feed", not "Feed 0".
9. **Sentiment glyph sizing follows the app.** Commit 80d46627 sets the glyph inline-block, `vertical-align: middle`, `size-3` (12px) in 13px text. This mockup keeps the idiom and the ratio: 13px glyph in the 15px sentence, centred on the x-height.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Own entries interleaved by time | Everyone shows all 11 in the brief's order; own entries at positions 2, 6, 8 |
| Watched stays off the feed | No watched entries anywhere |
| Author scope Everyone · Friends · You; tab count follows scope | Text tabs on the right of the tab strip; Feed reads 11 / 8 / 3 by scope |
| Presence at 1920×1080 | 920px column, 56×84 posters, 15/16/14px type, hairlines; `.page` max-width overridden to 952px |
| Line 1: name (medium), verb, glyph, time | Name 500 at 92%, verb at 72%, glyph 13px inline `vertical-align: middle`; the time leaves line 1 for its column |
| Glyphs: filled heart in `--love`, thumbs up, thumbs down, none | Inline SVG symbols `#i-heart` (filled, `var(--love)`), `#i-up`, `#i-down` (the up path rotated 180°), nothing for no sentiment |
| Line 2: title semibold + year | 16px 600 + 13px at 55% |
| Line 3: review text, 4-line clamp | 14px at 70%, `-webkit-line-clamp: 4`, 72ch measure |
| Poster left | `.thumb` at 56×84, per-title `--h` 350/200/264/140/60 |
| Second person for own entries | "You reviewed", "You want to watch" |
| Toolbar in a fixed seat; height never changes | 20px seat in flow, opacity 0 at rest, 1 on hover or cursor |
| Friend toolbar: List · Download · Ignore; Listed filled; plain states | States 5 and 5 · continued: Listed (filled), In library, Downloading with the 3px hairline |
| Own toolbar: List and Download slots = the title's state; Delete in Ignore's seat | State 6: Listed (filled) · In library · Delete |
| Whole-entry click; names not links | Row has `cursor: pointer`; names are plain spans |
| Own entries: no chips, badges, bars, avatars, alternation | Only the word "You" in `var(--p)` |
| Scope control: text tabs allowed if argued | Argued below |
| States 1–7 under `.sec` labels on one page | All present; state 5 has a second label for the seat's plain states |
| "Show older" after Everyone | Ghost button on the reading edge |
| You-empty copy and one quiet action | The brief's headline and body; "Settings → Social" as a ghost button |
| Keyboard cursor: 2px primary ring | `outline: 2px solid var(--p); outline-offset: -1px` on the row |
| No chips, bars, avatars, day dividers, group headers, animation beyond a 120ms fade, real titles, icon fonts, external assets, light theme | None present; the only transition is the toolbar's opacity |
| No text below 55% alpha except separators and icons | Lowest text alpha is 55% (time, year, scope tabs at rest, `.sec`) |

## Trade-offs

- **Less separation between rows than a card gives.** An 8% hairline is quiet; two adjacent four-line reviews would read as one block if it were lighter. 8% holds at 1920 on the dark ground and is the floor.
- **The right column is mostly empty.** Below the time there is nothing until the toolbar appears. The empty column is what makes the axis read, but a reviewer used to filled rows will see white space. A four-line review fills the middle; a listing does not.
- **Listing rows are poster-height, review rows are taller.** The seat is at the foot of the text block, so a listing's toolbar sits on the poster's bottom edge and a review's under the text. Inherited from UIDR-038, unchanged.
- **Two primary underlines on one line.** Feed and Everyone are both underlined. They belong to different groups at opposite ends of the strip, with the secondary group smaller and lighter, but the idiom is shared. See the scope section.
- **Ignore/Delete at the far right edge** is farther from List/Download than in round 2. That is the intent (the destructive action is isolated on the time edge) at the cost of a longer hover travel.

## At 3 entries and at 300

At 3 entries the list is three rows under the tab strip, about 340px tall, with no "Show older". Nothing frames the rows but the hairlines, so a short list looks short rather than sparse; there is no card grid with empty slots. The tab strip's hairline is the list's top edge, so even one row sits on a defined line.

At 300 entries the column is 300 rows of 112px (listing) or about 130px (short review), roughly 35,000px. What holds it together is the two verticals — posters down the left, times down the right — and the constant hairline rhythm. There is no per-row chrome to accumulate, so scrolling reads as one continuous column rather than 300 objects. The relative time is the only orientation and it is always at the same x; day dividers are unnecessary because the column itself draws the axis. The cost at 300 is that the 72ch measure leaves a consistent empty band in the right third of every row. That band is the axis.

## Own entries among friends'

"You" in the primary colour at 500 weight, and nothing else. The primary is otherwise used only for the tab underline and the cursor ring, so a primary word in the sentence column is the only primary inside the list and the eye finds it. Because the name is the first word of every line 1, the marks form a broken column on the reading edge: scanning down, the coloured words are the own entries. The second person does the rest — "You reviewed" and "You want to watch" do not need a border to say whose they are. A tinted border (`.own-border`) has no place because there is no border; a filled marker is the rail direction's answer, not this one's. The word is enough, and it is the only choice that leaves a friend's row and an own row structurally identical, which is what "an author like any friend" asks for.

## The scope control: text tabs against the pill

The scope is a pick-one over the same list the zone tabs pick over, so it uses the zone tabs' idiom — text with the primary underline — one step down the hierarchy: 13px instead of 14px, 55% instead of 60% at rest, 85% instead of 100% when active, right-aligned on the same line. That reads as a filter on this tab, subordinate to Feed / Watchlist / Friends, and it takes no vertical space of its own.

Against the pill:

- The pill is a 36px glass rail with a lifted option. On the tab strip's line it would be the heaviest object above the fold and the only glass on a page that otherwise has none: the one card on a card-less page.
- The pill's chosen option is lifted on a neutral fill, a second selection idiom on the same line as the underline. Two idioms for two pick-ones is one too many when they share a baseline.
- The pill has its own height and rhythm. On the strip's line it forces the tabs to align to a 36px box or the pill onto a line of its own. The text tabs share the tabs' baseline and hairline at no cost.
- The pill suits a control whose outcome the user must notice, a mode switch. The author scope is a lens on the same list, and the Feed count already reports its effect.

What the text tabs give up: the pill's larger target and its explicitness as a control. On the keyboard/gamepad page the scope tabs are three nav items on the strip's row, reached the way the zone tabs are.

## Page width

`.page` is overridden to `max-width: 952px`; with the base 16px side padding that is a 920px content column, up from the app's `max-w-3xl` (768px). The Feed rows, the tab strip and "Show older" all span the 920px.

The Watchlist and Friends tabs share the column and keep their glass cards. A card-less Feed sits beside them in three ways:

1. **The tab strip is the constant.** All three tabs hang from the same strip and the same hairline. The strip's bottom edge is the frame; what fills it differs by tab.
2. **The column edges are the constant.** The Feed's rows run edge to edge; the cards on the other tabs sit inside the same left and right edges with their own radius. The eye reads the 920px column on every tab; the card is a treatment inside it.
3. **Stream versus collection.** The Feed is a stream of homogeneous rows ordered by time, where per-item chrome multiplies with the count. The Watchlist is a set of titles and Friends a set of people, each with its own state and actions; a card bounds an object with state. Switching tabs, rows become objects, which is a real difference in what the tab holds and not a style change.

At 920px the Watchlist's and Friends' cards gain about 150px of width for the sentence and the state; nothing in their layout has to change.

## Data note

The brief's list carries three own entries (2, 6, 8), not four; the You scope shows those three and its Feed count reads 3. The Friends scope count is 8. Title state is kept consistent per title across every entry (Movie A: Listed · In library; Show B: In library; The Long Field: Listed; Harbor Lights: Downloading) so a toolbar opened on any row of a title says the same thing; the brief marks a state on one entry per title and the others inherit it.
