# Round 9c brief — the flag's form (2026-09-25)

Round 9b (`I-acts-strip`) settled that a person's card is their acts as
posters, each carrying the glyph for what they did (eye, heart, thumbs
up, thumbs down, bubble, bookmark), and chose the pennant's **mast** as
the glyph's form because it is the house shape and it survived the
half-size check. The owner asks whether the pennant is the right form,
and is open to alternatives. This round renders five forms — different
forms, not variations — on the same cards, and picks one by the render.

The pennant was designed for another job: a horizontal flag with a name
flying inward from a surface's right edge. On a 96×144 poster it is a
small pointed tab, and two acts stack vertically, where it begins to
read as chrome. Judge every form on: legibility at half size (thumbs up
from down, eye from bubble, bookmark from the rest); how two acts on one
poster sit; how much of the artwork survives; and whether it reads as a
mark on the picture or as a badge stuck to it.

No notes on any card (owner, 2026-09-25): a card is the person's acts
and nothing else; the You card has no label; a friend with no acts is a
tile and a name.

## The five forms

1. **The footer band.** A scrim strip across the poster's bottom, 36px
   tall on the rail's 96×144 (44 on the page's 130×195), in the
   text-on-image recipe (`oklch(13% 0.02 264)` at .85 fading to .6 at
   the top edge), the glyph left-aligned at 28/32px outline, a second
   glyph beside it for a second act; the heart on `--love`. The artwork
   above the band untouched.
2. **The clipped corner.** The poster's top-right corner cut away by a
   clip-path (a 44px / 56px notch), the glyph sitting in the notch on
   the card ground at 28/32px. Two acts: say what you do (a second
   notch, or the second glyph beside the first on the ground).
3. **The stamp.** A 44px / 52px rounded square (radius 8) of ink at .85
   in the poster's lower-right, inset 8px, a 28/32px outline glyph
   centred; two acts as two stamps stacked upward. Square, not round,
   so it does not read as a badge.
4. **Under the poster.** The glyph(s) in a row centred beneath the
   poster on the card ground at 28/32px, 8px below; the poster
   untouched. (Round 9b's (c), as the control for legibility.)
5. **The mast.** Round 9b's (a), as the control for the house shape.

## What to render

One page. For each form, three cards at the rail's width (560; posters
96×144, three acts): Cleo (watched Pioneer One; watched-and-loved
Charade; liked Cosmos Laundromat), Ada (loved Night of the Living Dead;
disliked Carnival of Souls; reviewed Caligari with no verdict), Sam
(listed Big Buck Bunny; liked Carnival of Souls) — and one card at the
page's width (900; posters 130×195, five acts) for Cleo with all six
glyphs across her strip. Five rows, one form per row, forms labelled.
Then the half-size check: read your own render at 0.5 and write one
sentence per form on the four criteria. Then pick one and say why; say
which you would pick if the owner rejects yours.

## Deliverable

`K-flag-forms/index.html` linking `../base.css` and `../art/`; copy the
glyph sprite from `I-acts-strip/index.html` (outline, 2px stroke) and
the card head from `J-friends-page` if it exists, else from
`I-acts-strip`. `K-flag-forms/REASONING.md` under 900 words: the sizes
per form; the half-size sentences; the pick and the runner-up; how the
pick handles two acts on one poster; the rules touched (UIDR-037's
pennant is a form, not a rule — say what the pennant remains for, the
title surfaces, if the pick is not the mast). Render with `page-shot` to
the scratch folder at 1920 (three passes) and at half; nothing outside
your folder; no git, no mix.
