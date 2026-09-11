# A · Poster-left row — reasoning

## Style

One anatomy for every entry. The poster (48×72 `.thumb`) sits on the left as
the identification anchor; to its right a text block of at most three lines:

1. `Nick recommended ♥ · 2h ago` — name at weight 500 / 92% white, verb at
   70%, separator at 40%, time at 55%. 13px.
2. `Movie A  2026` — title at weight 600 / 14px, year at 12px / 55%.
3. The note, when there is one — 13px, 68% white, clamped at 4 lines.

Entries are `.glass` cards with 8px gaps. There is no avatar, no pennant, no
marker, no synopsis, no type badge. The rose heart after "recommended" is the
only colour on the page. Hover is a surface lift to 6.5% white; the only
animation is the toolbar's 120ms opacity fade.

A listing and a recommendation are the same component; a listing simply has
no third line. Nothing else changes — not the surface, not the padding, not
the poster size. The reader learns one shape and reads every entry with it.

## Decisions

**Poster as anchor, not the person.** Round 1 led with the person (avatar,
name-first header). Round 2 strips the avatar, so the person is now just a
word. The poster is the only picture on the entry and the thing the reader is
scanning for ("have I seen this one?"), so it takes the left edge where the
eye lands first. The name still opens line 1, so "who" is the first word
read; "what" is the first thing seen.

**Toolbar seat: fixed-height strip in flow, empty at rest.** BRIEF-2 offered
two ways to avoid the hover jump: a reserved strip, or an overlay in the
bottom padding. This direction reserves a 20px strip as the last child of the
text block, `margin-top: auto`, opacity 0 at rest. Reasons:

- The text block is `align-self: stretch; min-height: 72px` — it is at least
  the poster's height. For a listing, lines 1–2 take ~39px, so the 20px seat
  fits inside the remaining 33px beside the poster. **Listings pay nothing**:
  the entry is exactly poster + padding tall whether the toolbar is shown or
  not, and the toolbar's bottom edge lands on the poster's bottom edge.
- For a recommendation with a note, the seat adds 20px under the note. At
  rest that reads as air under a quote, which a quote wants anyway. An
  overlay would have to sit in the same space to avoid covering the note's
  last line, so it saves nothing; it only trades a flow rule for an absolute
  one that has to be re-derived for every note length.
- In flow means the toolbar participates in keyboard/gamepad geometry
  naturally: the nav graph sees a real box under the text, not a positioned
  layer.

**Toolbar items.** Quiet 12px text with a 14px inline SVG glyph
(`currentColor`, no fill except the "Listed" bookmark). Items are 20px tall
with 6px horizontal padding and a 6px radius so a hover background and a
cursor ring have a shape to sit on. The bar is pulled 6px to the left so the
glyphs align with the text column at rest and "Ignore" (margin-left: auto)
ends on the entry's padding edge.

- **List** → **Listed** (filled bookmark, brighter text). State and verb are
  one control, as on Bluesky's action bar. "Following" would take the same
  slot as non-interactive state text; none of the eight entries is at that
  rung so it is not drawn.
- **Download** → **Downloading** (plain state text, 3px hairline under the
  word, 55%-on-12% white — no colour) → **In library** (plain state text).
  State text is 60% white, slightly quieter than a verb, and has no hover
  background because it is not a control.
- **Ignore** last, right-aligned.

**Cursor states.** The entry ring is `outline: 2px solid var(--p)` with
`outline-offset: -1px` so it sits on the glass border and follows the 14px
radius. The item ring is the same outline at offset 0 on the 20px item box.
Moving the cursor into the toolbar keeps the entry hovered-looking (surface
lift, toolbar visible) so the reader does not lose the entry they are acting
on.

## Requirements mapping (BRIEF-2)

| Requirement | Where |
|---|---|
| Name, medium weight | `.l1 .who`, 500 |
| Action verb; love = "recommended" + rose heart; "wants to watch" no glyph | `.l1`, `.l1 .love` — entry 2 (love) vs entries 4/6/7 (like) vs listings |
| Title identification: poster, name, year; no badge, no overview, no markers, no pennants | `.thumb` + `.l2`; none of the forbidden elements exist in the markup |
| Relative time, quiet | `.l1 .time`, 55% |
| Note only on recommendations; clamp 4 lines | `.l3`, `-webkit-line-clamp: 4` |
| Toolbar only on hover/cursor; List, Download, Ignore in order | `.bar`, shown via `:hover`, `.hovered`, `.cursor`, `:focus-within` |
| List filled when listed | entry 5 — `.v.on` + `#i-bm-on` |
| Download → "Downloading" with 3px hairline | entry 8 — `.st .w.prog` |
| Download → "In library" | entry 4 — `.st` |
| No layout jump on hover | reserved 20px seat, above |
| States: rest / hovered / cursor on entry / cursor on item / Downloading / In library / Listed | rest: 1, 2, 3, 6, 7 · hovered: 4, 5, 8 · cursor on entry and on "List": the two labelled entries after "Show older" |
| Same eight entries, `--h` per title consistent | Sample Show 350, Movie A 200, Show B 264, The Long Field 140, Harbor Lights 60 |
| "Show older" | `.older` |
| Whole entry clickable, name not a link | entry is the click target; no anchors anywhere |

## Trade-offs

- **Bottom air under a note at rest.** A recommendation with a note carries
  20px of reserved space under the quote (34px including padding, against
  12px above line 1). This is the honest cost of "no jump". It is invisible
  on listings and reads as deliberate on quotes; it would look wrong only if
  notes were the majority, and at 30 friends they are not (below).
- **Two-line minimum.** Every entry is at least 94px tall because the poster
  is. Round 1's compact listing was ~58px. This direction trades density for
  a single anatomy; at 8 entries the page is ~30% longer than round 1's.
- **Year only, no type.** Without "TV" / "Movie" the reader distinguishes a
  show from a film by title and poster alone. The type badge was explicitly
  removed; the modal has it one click away.
- **Heart is a text glyph.** `♥` at 12px in the system font. It matches the
  text baseline and needs no SVG, but its exact shape varies by platform
  font. Acceptable for a mockup; the app would use its existing heart icon.

## How it holds at 30 friends

At 30 friends the feed is mostly listings — people add to their watchlist far
more often than they write a note. Listings are the cheap case here: fixed
94px, two lines, no seat cost, scanning by poster down the left edge at a
steady rhythm. A recommendation with a note breaks the rhythm by exactly the
height of its note, which is the right thing to be interrupted by. Because
nothing but line 3 varies, the eye never has to re-learn where the title is:
it is always the second line, always 14px semibold, always beside the poster.
The same title appearing three times in a row (three friends listing it) is
three identical posters stacked — the repetition itself is the signal that
something is popular, without a pennant saying so.

At 3 friends the page is short and every entry is read, not scanned; the note
line carries the weight and the calm of the rest of the anatomy keeps the
notes from competing with each other.

## Losing the pennants: does "Cleo agrees" matter?

The pennants showed every friend's act on a title, so on Cleo's listing of
Sample Show the reader also saw that Nick had recommended it. Without them,
that entry says only "Cleo wants to watch Sample Show". The agreement is
still on the page — Nick's recommendation is entry 6, six days older — but
the reader has to notice the same poster twice to connect them.

I think this loses less than it looks like. The feed is flat and
reverse-chronological by decision; its job is to show acts as they happen,
not to aggregate opinion per title. Aggregation is what the title modal is
for, and the whole entry opens it. What the pennants bought on the entry was
a shortcut to that aggregate at the cost of a second visual system (flags,
clip-paths, per-friend labels, one warm colour repeated) competing with the
entry's own three lines. The repeated-poster signal above does part of the
job for free at feed scale. The part it does not do — "two people I trust
both liked this" while I am looking at one of their entries — is a real loss
for a reader with many friends and a fast-moving feed. If that turns out to
matter, the place to add it back is as one quiet line-1 suffix on the
recommendation entries only ("Nick recommended ♥ · 2h ago · Cleo too"), not
as a second system on the edge.
