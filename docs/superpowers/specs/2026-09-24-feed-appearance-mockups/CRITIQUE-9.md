# Round 9 critique — the Friends page, and the acts strip

2026-09-25. Two pages: `H-friends-page` (the Friends tab redrawn
breathable and poster-led, a two-column grid, the presence sentence
kept) and `I-acts-strip` (the owner's pitch: a person's picture is a
strip of their latest acts, each poster flying the pennant's flag for
what they did, no sentence — three flag placements, at the rail's width
and the page's). Both rendered at 1920 and at half size.

## H · the Friends page

It answers the brief. Cards at 900px with 30px padding, the tile at
64, the name at 24, one presence line, one note slot, a captioned strip
of five posters at 130×195; the text rows, the key and Remove friend
moved into the opened card. Breathable, and the posters carry the
watch-sharers. It reads at half size.

**Its defect is structural.** In a row-major grid, a short card beside
a strip card leaves a 220px hole (You beside Cleo, Nick beside Bob), and
at thirty friends that is about half the rows. Top alignment keeps the
heads on one line and the brief forbade a placeholder, so the holes are
the honest rendering of the sentence card: a friend who shares only
reviews has no picture. The fix is not a layout trick; it is giving
every sharer a picture, which is what the acts strip does.

## I · the acts strip

**It works, and it is better than the sentence.** A person's card is
their latest three acts, newest first, one poster per act, each flying
the flag for what they did — the eye, the heart on rose, the thumbs,
the bubble, the bookmark — with two flags on one poster when the person
watched and loved a title. The pennant's own form (placement (a), the
mast: a flag flying from the poster's top-right edge, 36px tall with a
28px outline glyph) passed the half-size check where the corner disc
did not (thumbs up and down merge at 12px, the ring reads as a badge)
and below-the-poster took the flag off the poster. Outline glyphs at a
2px stroke survive where solid ones become blobs.

What it gives: every friend who shared anything has posters, so the
reviews-only card is no longer a line of text under a name; the
sharing states fall out of the flags (eyes present or not); the card
is denser and more pictorial than the sentence at the same height; and
the vocabulary is the house's own — the Feed's bands say "Nick reviewed
👍" beside the same glyph, so the flags are taught on the page above.

What it costs, all named by its designer: the rail's posters had to
grow from 72×108 to 96×144 for the flag to read, so four cards sit in
the rail's fold instead of five and a half; the episode number and the
verb leave the card for the person's opened view; the TV has no hover,
so the flag's tooltip does not exist there; and the vocabulary is
learned, not read — the one risk. State 1b renders the reviews-only
card with and without a "Doesn't share watching" note; the owner's
call (2026-09-25): **no sharing notes** — the card shows what the
person shared and says nothing about what they did not, so a strip of
only hearts is a strip of only hearts, and a friend with no acts is a
tile and a name.

## Verdict

**Adopt the acts strip on both surfaces** — the rail's card (posters at
96×144, the flag at 36/28) and the Friends page's card (posters at
130×195, the flag at 42/32) — with the mast placement, no sharing notes
of any kind, no "How friends see you", and the presence sentence gone
from the card face: the You card is your acts like anyone's, the filled
own tile its only mark. Keep
H's frame for the page: the two-column grid of 900px cards, the head
(tile 64, name 24, time 18), Add a friend at the foot, the text rows and
management in the opened card. With every sharer carrying posters the
grid's holes reduce to the rare "nothing shared" card. The Feed's rail in
`G-couch-feed` takes the same card at its width.

Round 9c assembles it: `J-friends-page` — H's grid with I's strip, the
rail column redrawn beside it once for the shared component — and then
the spec's "What the user sees" is complete: the Feed page from G, the
person card from J at two widths.

## Rules touched, for the record

- **UIDR-037 "never on poster cards"** — exception: on a person card
  the poster is the act's subject and the flag is the act; the mark is
  the pennant's, the subject flips from the title to the person.
- **UIDR-038 rules 8–9** (the card's presence line and Recently watched
  strip) — replaced by the acts strip: one strip of the person's latest
  acts, flags for the act, newest first; the presence line survives
  only as the note slot and in the opened view.
- The identity tile, the crop rule and the couch floors as settled.

## Addendum, round 9c — the glyph's form

`K-flag-forms` rendered five forms on the same cards at both widths
and judged them at half size: the footer band, the clipped corner, the
stamp, under the poster, and the mast as control. All five pass the
glyph-legibility check at a 28px outline with a 2px stroke (round 9b's
disc failed on size, not form).

**The pick is the clipped corner**: the poster's top-right cut away by a
44px notch (56px on the page), the glyph centred in the notch on the
card's ground. Nothing sits behind the glyph, so it is the crispest form
at couch distance, and it is the one form that reads as a mark on the
picture rather than a layer stuck to it. One act costs a corner the art
uses least, never the title zone. Two acts: the notch grows down
(44×76, 56×92) and the second glyph sits under the first in mast order;
a side-by-side notch was tried and read as a cropped image.

**Runner-up, the footer band**: two acts free and legibility uniform,
but every poster pays — five posters become five bars, and the band
sits on the title lettering. **Not the mast**: its two-act stack is the
chrome that opened this round. **Not the stamp**: a rounded ink square
is a badge. **Not under the poster**: clean, but off the picture.

The reservation, the designer's and mine: on a poster dark at its
top-right the cut vanishes and the form is a bare glyph on imagery —
legible, and the fixed corner makes it read as the same mark, but one
form in code is two in the eye. If the owner sees a hole rather than a
mark, the band is the answer.

**UIDR-037 is a form, not a rule.** The pennant stays the title
surfaces' idiom (named flags flying inward from a hero's edge, with a
tooltip); the person card takes the corner form with the same glyphs,
order and tints, because its job is different (one glyph on a 96px
poster, not a name on a wide surface).
