# B · Sentence then card — reasoning

## Style

The Bluesky post, taken literally, with everything Bluesky puts around the
post removed. An entry is three things stacked: a sentence, what the person
said, and the object the sentence points at.

* **Line 1, the sentence.** `Nick recommended ♥ · 2h ago`. 15px so it is the
  largest text on the entry. Name at weight 500 / 95% white; verb at 70%;
  separator glyph at 40%; time at 55%, 13px. The rose heart (`--love`, 13px)
  follows "recommended" for a love and is the only colour on the page. "wants
  to watch" has no glyph.
* **Body.** The note, 14px/1.5 at 88%, clamped at four lines. Recommendations
  only. No overview fallback — round 2 dropped the synopsis, so a note-less
  recommendation (entry 6) is sentence + card and nothing else.
* **Card.** `.inset`, shrink-wrapped (`inline-flex`), poster `.thumb` 56×84,
  name semibold 14px and year 12px/55% on one baseline. Nothing else. It is
  identification, not a summary.
* **Feed surface.** One `.glass` column; entries divided by a 1px hairline
  at 7% white. Entries are not boxed. Hover / cursor lifts the entry's
  background to 6% with a 10px radius inside the column.
* **Toolbar.** 12px text at 70%, 14px inline-SVG glyphs in `currentColor`,
  overlaid in the entry's bottom padding. 120ms opacity fade only.

## Decisions

**The feed is one surface, not eight cards.** Round 1 gave every entry a
glass box with an inset card inside it — box in box. With the sentence now
the entry's first line, the entry itself does not need an edge; the
timeline column (Bluesky's own shape) gives it one. The result is that the
only rounded boxes on the page are titles, which is exactly the relationship
the direction asks for: the sentence is prose on the ground, the title is
the object.

**The card is shrink-wrapped.** Name and year sit on one line beside a
56×84 poster; a full-width inset would be a 96px-tall slab that is ~70%
empty, repeated eight times — the wall-of-cards failure. Shrink-wrapping
makes the card as wide as its title, so widths vary per entry (Movie A vs
The Long Field) and the eye does not read a grid. It also makes "object"
literal: the card ends where the title ends.

**Toolbar overlaid in the bottom padding, not a reserved strip.** Both
options give the same rest appearance (empty space under the card); the
difference is what the space *is*. A reserved strip is a layout slot that
happens to be empty — an absent toolbar. Padding is the entry's own
breathing room, and the toolbar borrows it while hovered. Concretely:
`.entry{padding:14px 16px 34px}` and `.bar{position:absolute;bottom:8px;
height:20px}`, so the bar occupies the bottom 8–28px of the entry and the
card keeps a 6px gap above it. The entry's box is identical at rest, on
hover, and under the cursor; nothing reflows. The extra 20px under each
card also does spacing work: the gap between one entry's card and the next
entry's sentence is larger than any gap inside an entry, which is what
makes eight entries read as eight sentences rather than one column of
posters.

**Toolbar contents and states, per BRIEF-2:**

| Slot | Default | Alternate readings |
|---|---|---|
| List | outline bookmark + "List" | filled bookmark + "Listed" (on your list, `.v.on`); "Following" when the title is Follow+ (not a toggle; not in the data set) |
| Download | arrow-down + "Download" | plain "Downloading" with a 3px progress hairline under the word (`.prog:after`, 42% filled, grey on grey); plain "In library" |
| Ignore | word only, `margin-left:auto` | — |

Plain state text uses `.v.plain` (60% white, `cursor:default`) so that a
reader can tell a state from a verb by tone before hovering it. Controls
hover to 95%; Ignore underlines on its own hover.

**Cursor.** The entry ring is a 2px `--p` outline at `-2px` offset on the
lifted entry, with the toolbar shown. Moving into the toolbar moves the ring
to the item (2px outline, 3px offset, 4px radius); the entry stays lifted so
the toolbar stays visible. Enter on the entry opens the title; Enter on an
item fires it.

## Requirements mapping (BRIEF-2)

| Requirement | Where |
|---|---|
| Name medium weight | `.sentence .who` 500 |
| Like = plain "recommended"; love = heart in `--love`, the one colour | entries 4/6/7 vs 2 |
| Title identification only: poster, name, year; no badge, overview, markers, pennants | `.card` |
| Relative time, quiet | `.sentence .time` 55%, 13px |
| Note as body, clamp 4 lines | `.body` with `-webkit-line-clamp:4` |
| Toolbar only on hover/cursor; List / Download / Ignore in that order | `.bar`, `.entry:hover .bar` etc. |
| List filled when on your list | entry 5 (hovered) |
| Download → "Downloading" with 3px hairline | entry 8 (hovered) |
| Download → "In library" | entry 4 (hovered) |
| Ignore last, right-aligned | `.ignore{margin-left:auto}` |
| No layout jump on hover | overlay in bottom padding, see above |
| States: rest; hovered; cursor on entry; cursor on an item | entries 1–3, 6–7 rest; 4, 5, 8 hovered; two labelled blocks at the bottom |
| Same eight entries, same order, then "Show older" | body; `.btn.ghost` |
| Consistent `--h` per title | Sample Show 350, Movie A 200, Show B 264, The Long Field 140, Harbor Lights 60 |
| No avatars, pennants, chips, accent bars, animations, real titles, day dividers | none present; only `opacity .12s` |

Entry 7 (Cleo recommended Show B) is shown at rest, but its toolbar carries
"In library" like entry 4's, since it is the same title — the state is the
title's, not the entry's.

## Trade-offs

* **Shrink-wrapped card vs Bluesky-literal full width.** Bluesky's embed is
  full width because it carries a description and a domain line. Ours
  carries nothing beyond identification, so full width would be empty
  surface. The cost: card widths vary, and the right side of every entry is
  empty. That emptiness is deliberate — it is where the sentence's
  dominance comes from — but at 768px it is a lot of unused ground.
* **Toolbar in padding means a fixed 34px under every card, hovered or
  not.** The alternative — overlaying the toolbar on the card's own bottom
  edge — would remove the dead space but puts controls on top of the
  object they act on, and the brief places the bar under the card.
* **One surface, hairline dividers.** Adjacent hovered entries (4 and 5 in
  the mockup) show two lifted blocks separated by a hairline; in the real
  app only one is ever hovered, so this is a mockup artefact.
* **Toolbar is pointer-events:none at rest.** Clicking where the toolbar
  would be opens the title, not a verb; a verb has to be visible to be hit.
  This is the correct side of the tradeoff for a whole-entry click target.
* **The 3px hairline under "Downloading" is grey.** Progress is the one
  place a colour would be conventional; keeping it grey holds the
  one-colour rule and reads fine at 3px.

## At 30 friends

Entry height is ~150px for a listing, ~180px for a recommendation with a
one-line note, ~240px at the four-line clamp. A 30-friend feed at a dozen
acts per day is a few screens per day, all the same shape. What carries it:

* The sentence is always the first line, always the same grammar, so a
  reader scans the left edge for names and verbs the way they scan a
  timeline — without the poster grabbing first.
* Repeats of one title (entries 2–3, 4–7) show the same `--h` poster at
  the same width, so "this again" is visible without a pennant.
* Variety comes only from the note (present or not, short or long) and the
  card width. At 30 friends the feed will still be a column of sentences
  over small boxes; it does not degrade into something else, but it does
  not compress either. If density becomes the problem, the shape to reach
  for is the round-1 direction 3 idea (listings collapse to one line),
  not smaller cards.

At 3 friends the feed is a handful of entries a week; the generous
spacing reads as calm rather than sparse, since each entry is one person
saying one thing.

## Losing the pennants — does "Cleo agrees" matter?

Yes, something is lost, and no, it should not come back as a pennant.

The pennant said, on Cleo's listing of Sample Show, that Nick had
recommended it earlier. In a flat one-entry-per-act feed that information
is *already in the feed* — six entries lower, as Nick's own sentence. The
pennant was a cross-reference, compressing the feed's history onto every
surface that title appears on. That is a title-page concern (the modal, the
Watchlist row), where "who among your friends has an opinion about this"
is the question being asked. On the feed the question is "what did people
do lately", and the answer is the sentences themselves.

What does go missing is the *count*: with 30 friends, "four people
recommended this" would be worth knowing at a glance, and eight separate
entries scattered over a week do not add up visually. If that signal turns
out to matter, the right shape is a second quiet clause in the sentence —
"Cleo wants to watch · 12m ago · Nick recommended it" — text in the same
voice, not a flag. Not in this round: BRIEF-2 says the entry shows the five
listed things and nothing else, and the mockup holds to that.
