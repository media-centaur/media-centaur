# 1 · Person-first post

**Style.** Bluesky's post anatomy, not its skin. Every entry is a post authored by a friend: a header line (small avatar, name in medium weight, verb, sentiment glyph, relative time), the note as body text, and the title as an embedded card underneath. The card is the app's existing row anatomy shrunk into an `.inset` panel — thumb, name, meta, quiet markers, pennant mast bleeding off the right edge — so the title still reads as a title surface, just a subordinate one. Person and verb sit first in reading order and on the brightest text; the card is a step darker and indented under the avatar column, so the eye lands on "Nick recommended ♥" before it lands on "Movie A".

**Decisions.**

- Sentiment is a glyph after the verb, not a chip. Love is the rose `♥` in `var(--love)`; like is the thumbs-up glyph desaturated (`filter: grayscale(1)`) so the header carries no second hue. Rose stays the single warm mark on the page, shared by the glyph and the love pennant.
- Listings have no body. The header runs straight into the card. A recommendation without a note shows the title's overview in the body slot at 60% white, clamped to two lines (entry 6). Notes are shown in full up to four lines; see "long note" below.
- The card is indented 36px (avatar width + gap), Bluesky-style, so avatar / body / card form one left rail per post. The 768px page has the width to spend.
- The mast lives on the card, not the post: it is a property of the title, and the card is the title surface. It bleeds off the card's right edge exactly as it bleeds off today's rows. Entries 5 and 8 have no other friend acts, so their masts are empty and the card simply ends.
- Where the brief specifies a mast I used it verbatim. Where it doesn't (entries 2, 3, 5, 8) I applied the brief's own rule — the mast shows every friend's act on the title — which gives Movie A a `Nick ♥` pennant on both of Nick's posts and nothing on The Long Field / Harbor Lights.
- Same person, same title, minutes apart (entries 2 and 3) renders as two complete posts with the same embedded card. This is what "one entry per act" means under a post model; the repetition is the design, and it reads as "he recommended it, then listed it" with no extra copy.
- Ignore is quiet text at the far right of the header line, revealed on hover (entry 4 shows the hovered state). The header is the one line that is about the *entry* rather than the *title*, so the entry's single verb belongs there. The whole post is the click target for the title modal.
- The header line is `white-space: nowrap` with ellipsis. Names and verbs are short; it only matters if a future verb is long.

**Requirements mapping.**

| Brief | Where |
|---|---|
| One entry per act, flat, newest first | Eight `.post` blocks in the brief's order; two for Movie A, two for Sample Show, two for Show B |
| Person + time on every entry, sentence voice | `.head .line`: "Cleo wants to watch · 12m ago", "Nick recommended ♥ · 2h ago" |
| Note vs overview | `.body` for notes; `.body.overview` (dimmer, two-line clamp) only on entry 6 |
| Markers as quiet text | `.card .mark` after the meta at 55% white: In library, On your list, Downloading |
| Mast on the title surface | `.card .mast` with base `.pen` / `.pen.love`, clipped by the card's `overflow: hidden` |
| Ignore on hover, nothing else clickable | `.ignore` in the header, `opacity: 0` → `1` on `:hover` / `.hovered`; no other links |
| "Show older" archive idiom | `<button class="older">` centred below the last post |
| Dark slate, glass, calm | `.post.glass` on the base palette; hover is a background lift only; no animations beyond the 120ms verb fade |
| Colour is signal only | Rose on `♥` glyph and love pennant; avatars use the base `.avatar` tint; thumbs are placeholder art |

**At 3 friends and at 30.** At three friends the feed is sparse and the post model earns its keep: each act gets room, the note is readable, and the repeated card for "recommended then listed" is legible as a small story. At thirty friends the page is dense with 130px-tall posts, and the cost shows: the card repeats on every act, so a popular title appears as five near-identical cards down the page, each carrying the same mast. The header line is what keeps that tolerable — the reader scans avatars and names, not cards, and the mast on each card is the "who else" summary so no single post needs to be found. The layout itself does not change; the window plus "Show older" bounds the page height. If density becomes the complaint, the fix lives in the model (grouping acts per title) rather than in this rendering, and the brief has already decided against that.

**Long note.** The body is clamped at four lines with an ellipsis (`-webkit-line-clamp: 4`). Four lines of 14px body at 720px is roughly 400 characters — longer than a plausible recommendation note, so the clamp is a guard, not a feature people hit. The full note is read in the title modal, which the whole post opens. The card never moves: it sits under the clamped body at a stable offset, so a long-winded friend does not push the title out of view.

**Trade-offs.**

Gains: the strongest possible statement of "the feed is about what your friends did"; person, verb and sentiment are readable at a glance; the note has a proper home as body copy rather than a sub-line; the card is a reusable title surface that could carry the mast and markers anywhere.

Costs: the tallest entry of the five directions — a listing is ~110px, a recommendation with a note ~135px — so fewer entries fit per screen than a title-first row. The embedded title is deliberately subordinate, which makes "is Show B in here?" a slower scan than a row whose title leads. Repeating the card per act means the mast repeats too. The indent under the avatar spends 36px of every post on rail alignment. Nothing here is hedged toward a row: if the reviewer wants the title to lead, that is a different direction, not a tweak of this one.
