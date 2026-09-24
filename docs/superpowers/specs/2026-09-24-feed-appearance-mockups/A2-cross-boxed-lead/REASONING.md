# A2 · Cross, boxed lead — reasoning

One change to `A-cross-full`: the lead's image box is the band's. Same states 1–13, data and computed crop offsets; no JavaScript. Rendered with `page-shot` three times at 1920×1080 (A and A2 stacked lead against lead), once each at 1280×800 and 2560×1440.

## The change, and the geometry

`.u.lead` no longer sets `--img-x`; the band's edge mask now applies to `.u .bd`; the `.u.lead .scrim` block is deleted. Every unit paints its backdrop in a box from x=560 to the right edge, dissolved over 320px, under one scrim. Everything else on the lead is A's.

| | 1280 | 1920 | 2560 |
|---|---|---|---|
| Image box | 620×340 | 1260×340 | 1900×340 |
| Still scaled to | 620×349 | 1260×709 | 1900×1069 |
| Slice, boxed lead | **97%** | **48%** | **32%** |
| Slice, A's full-bleed lead | 51% | 33% | 25% |
| Clear picture past the dissolve | 300px | 940px | 1580px |

At 1920 the 30% crop shows rows 16–64% of the still: Sintel and the dragon's whole head; both figures of Night of the Living Dead with the moon; Grant and Hepburn's two-shot. At 2560 the lead is what A's was at 1920 — one large face. At 1280 the box is the band's 620px and the still fits almost whole: a postcard at the lead's right, 300px of it clear, 47% of the lead ink at rest. The band's `?w=1280` derivative serves the lead; A's `?w=1920` tier goes.

In A's sizes table the lead's image-box, slice (48%), scrim and vignette rows now read as the band's; every other row holds.

## The scrim

The band's recipe verbatim — not scaled, not translated. Direction 4's to-the-top layer is dropped: the seat sits at y 270–290, x 270–500, on ink under .97, and needs nothing. The longest 32px title ends by x≈665 — about 8% picture. The one marginal spot is a review lead's line 3: 58ch at 16px ends at x≈696, where the dissolve is 43% open under .70 — about 13% picture under the last word, where a band's line 3 ends at x≈532, before the box begins. The text shadow carries it.

The alternative I tried: the band's stops translated right by 112px, the text block's offset. On both leads it darkens the last word's ground a step and costs Grant's face and the dragon's brow the same step. Rejected.

## The two leads, side by side

**Sintel.** A: one face 1024px tall, chin cut, the dragon a shape under the scrim at x≈420, a warm cast under the words. A2: the dragon's head at x 750–1150 and Sintel's face at 1170–1620, both in the clear, the still's composition intact, the words on ink. The box gains the subject in the clear and the one rule; it loses the colour cast under the text and the picture's reach to the left edge. A's lead was a photograph with a headline on it; A2's is a picture beside a headline.

**You · Charade.** A: Hepburn right of centre, Grant a ghost at x≈320 behind the review. A2: the two-shot, Grant at x≈800 and Hepburn at 1370, the review on ink. The review lead is where the box wins outright — A put the words over the second face.

**Dominance.** The lead still leads: 340px of picture against 152 at the same width, the 160×240 poster, the 32px title. What it gives up is A's front-page feel — at 1920 A's lead was a different kind of object above a column of bands; A2's is the column's first band, taller. That is the point, and the cost.

**States 10 and 11.** The review lead is above. The no-artwork lead is A's, unchanged by construction — the inset tone has no image box — and now matches the with-artwork lead's ink left.

## The dark left

Nothing. The band is the same shape and the column is already fifteen of it. The poster's existing shadow (`0 10px 28px` black/55) is invisible on 13% ink, and a lighter one would be a frame. On a listing lead the void between poster and dissolve (y 130–270) is the fixed seat's doing; decorating it would call the void a problem, and the band says it is not.

## Rules touched

None new. Two rows of A's ledger change: *Direction 4's lead scrim* goes from Bent to Dropped, and A's decision 1 (lead full-bleed, band boxed) is reversed. A new arrival is A's, with one improvement: the old lead's still re-crops from 48% to 21% at the same x=560 — its subject stays put; in A it also moved 560px right.

## Trade-offs

- **1280 is the weak width**: a 620×349 postcard with 300px clear, against A's 51% slice.
- The last word of a review lead's line 3 sits on 13% picture.

## The one thing I am least sure of

**The 1280 lead.** At 1920 and above the box is the better crop on every still here, and one rule. At 1280 it is a small picture on a large dark card, and A's full-bleed lead — the thing this page removed — was best exactly there. If the owner works at the container width, A wins; at 1920, the reverse. The width decides it, not the rule.
