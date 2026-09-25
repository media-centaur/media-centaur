# Round 9b brief — the acts strip: posters flying flags, no sentence (2026-09-25)

The owner's pitch, on the Friends rail's card: "we could have the text
that says 'watched'... or we could have a set of poster images that has
an eye on one, a thumbs up on the next, a heart on the next, and
completely omit the text 'reviewed ___', 'watched ___'."

The app already owns those glyphs. UIDR-037's **pennant** is the house
provenance idiom on every title surface: six flags in mast order —
love (heart, on `--color-love` rose), like (thumbs up), dislike (thumbs
down), reviewed (speech bubble, a review without a verdict), watched
(eye), listing (bookmark) — all but love on a neutral tint, drawn by
`Components.Title.Pennant` as flags flying inward from the surface's
right edge; the sentiment glyphs come from `Components.Title.Sentiment`.
Read `lib/media_centaur_web/components/title/pennant.ex` and
`sentiment.ex` for the shapes, sizes and tints; copy the glyphs as
inline SVG.

**What flips is the subject.** On a title surface the flag says
"friends did this to the title"; on a person card it says "this person
did this to this title". Same marks, person-centric meaning. Name that
in REASONING against UIDR-037's rule "never on poster cards" — the
exception: on a person card the poster is the act's subject and the
flag is the act.

## The acts strip

A person card's picture is a strip of their latest acts, **newest first,
left to right**: one poster per act, each flying the flag(s) for what
the person did. No presence line, no "reviewed ___", no "watched ___".
Two acts on one title (watched and loved Charade) are one poster with
two flags in mast order — the pennant's own stacking. The head keeps
the identity tile, the name and the time of the latest act (which is the
first poster's).

The sharing states fall out of the strip: a watch-sharer's strip has
eyes; a reviews-only friend's strip has hearts, thumbs and bubbles; a
listings-sharer's has bookmarks; nothing shared is an empty card that
says so. The one ambiguity — a strip with no eyes could mean "doesn't
share watching" or "hasn't watched" — is drawn **both ways**: with the
quiet 18px note under the head, and without.

Draw the strip in **both widths**: the rail's card in `G-couch-feed`
(560 wide; posters at 72×108 → say what size the flag needs to read at
half size, and whether 72×108 must grow) and the Friends page's card
(the grid card from `BRIEF-9.md`; posters ≥ 120×180).

## Three flag placements, on one page, for the owner to compare

- **(a) The mast** — the pennant's own form: a flag flying inward from
  the poster's top-right edge, clip-path point, bleeding 6–8px past the
  poster's edge as the house mast does on a hero. Glyph ≥ 28px.
- **(b) The corner disc** — the glyph in a 36px dark disc (ink at 85%)
  at the poster's top-right corner, a 1px white/18 ring; the heart on
  rose. Not a chip: no text, no fill colour but the tint the pennant
  gives that flag.
- **(c) Below the poster** — the glyph(s) centred under the poster at
  28px on the card ground, the poster itself untouched.

For each: the rail card (three posters: eye, heart, thumbs up — one of
them with two flags), the Friends-page card (five posters covering the
six flags across two people), and the reviews-only card. Then the
**10-foot check**: at half size, can you tell thumbs up from thumbs
down, the eye from the bubble, the bookmark from the rest? Say which
placement survives it and at what glyph size. Choose one and say why.

## States

1. The rail (from `G-couch-feed`'s rail column, 560 wide, on its own):
   You, then six friends, each card an acts strip in the chosen
   placement; the four sharing states visible; the note both ways on
   the reviews-only card.
2. The three placements side by side on one rail card and one
   Friends-page card.
3. The Friends-page grid card (from `BRIEF-9.md`) with the acts strip:
   four cards in a two-column grid at 1920.
4. The half-size check of states 1 and 3, as the designer saw it (a
   sentence in REASONING per placement).

## Deliverable

`I-acts-strip/index.html` linking `../base.css` and `../art/`, and
`I-acts-strip/REASONING.md` (under 1000 words): the strip's rule (order,
one poster per act, two flags on one poster); the placement chosen and
the glyph size that survived half size; what the strip loses (the
episode number; the sentence) and where it goes (the person's opened
view); the rules touched (UIDR-037 "never on poster cards", UIDR-038
rules 8–9 on the presence line and strip) with each exception; the one
thing you are least sure of. Render with `page-shot` to the scratch
folder at 1920 (three passes) and half size; nothing outside your
folder; no git, no mix.
