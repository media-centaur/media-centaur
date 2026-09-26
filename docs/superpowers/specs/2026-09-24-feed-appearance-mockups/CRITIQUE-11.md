# Round 11 critique — backdrop and logo instead of poster and backdrop

Rendered 2026-09-26 at 1920×1080 on Q6's page and read at half size on
`Q-logo-switchboard/compare.html` with Q6 beside them. Every direction
draws the realistic mix: four titles without a logo fall back to the typed
name, so the fallback is judged on every page.

## What the poster was doing to the band

Seen with the poster removed (R1), three things were true of Q6 that are
not true of R1. Every band carried two pictures of one title in two
aspects and two grades. The title appeared twice — printed on the poster
and typed beside it. And three objects competed at the band's left: the
tile, the poster, the still's edge. The rail repeats the posters a third
time. That is a plausible account of the irritation, and R1 is the test
of it: if R1 is calmer than Q6, the poster was the noise.

## The four, scored

| | The title | Band | Reading order | The mix | Verdict |
|---|---|---|---|---|---|
| **R1 Backdrop only** | typed, line 2 | 224 | who · what · said | uniform by construction | The floor and the test; emptier on a band without a review |
| **R2 Logo headline** | the logo as line 2, on ink | 264 | who · what · said | typed name at 34 in the same slot; coherent | **Recommended** |
| **R3 Title card** | the logo bottom right of the picture | 224 | who · said · then the title, last | the typed name in the same corner; coherent after the fix | Most cinematic; splits the sentence |
| **R4 Hero band** | the logo first, on the full still | 264 | what · who · said | typed name in the logo's place | Strongest presence; inverts the sentence |

## Findings

* **The logo as line 2 is the poster's job done better.** A poster's
  identity is mostly its lettering; the logo is that lettering without the
  second picture. R2 keeps the band's sentence exactly — who, which title,
  what they said — and only the title's typography changes.
* **The band has to grow for a headline logo.** 224 was the poster's
  height. A 72px logo over a two-line review and the seat needs 264; 56
  gives 248. At 1080 the fold shows three and a half bands instead of four.
  R3 avoids the growth by putting the logo on the picture, which is its one
  structural advantage.
* **The seam placement covers faces.** Rendered first for R3: the logo on
  the dissolve at the picture's left edge lands on the subject on most
  stills, because the crop rule centres the subject in the box. The bottom
  right over a foot gradient is where a still has the least to lose; the
  seam stays on the switchboard as the record.
* **The fallback goes where the logo goes.** In R3's first render a title
  without a logo kept its name on the left while the logos sat on the
  right, so the mix moved the title around the band. With the typed name
  in the corner over the same gradient, the corner is the title's place
  whatever its form. The same rule holds in R2 and R4 by construction.
* **The typed fallback wants 34px, not 28.** Beside a 50px wordmark the
  settled 28px title read as a caption.
* **Real logos will be louder than these stand-ins.** The wordmarks are
  restrained; TMDB logos carry colour, texture and odd aspect ratios. R2
  and R4 put twenty of them in a column; R3 puts them over pictures where
  a busy logo on a busy still is the least legible case. The logo box
  (contain, 72 tall, 440 wide) bounds the size but not the noise.

## Recommendation

**R2** — the logo as the headline on Q6's page. It answers the question
as asked: backdrop and logo, no poster, the sentence intact, readability
untouched, and a fallback that holds the column together. Take the 40px.

R3 is the alternative if the owner would rather keep 224 and wants the
picture to carry the title; the price is reading the title last. R1 is
what to ship if the owner's answer to the test is that the poster was the
problem and the logo is not needed. R4 is the page for one idiom across
Home and the Feed, and its inverted sentence is the reason not to.

The rail keeps its posters in every direction: a person's card is their
acts, and the poster is the act's subject there. Next to a poster-less
Feed it reads fine in every render; the owner should judge that on the
page rather than take it from here.

## In the app, for R2

`FeedEntry` gains `logo_url` from the ladder `ActivityArtwork` already
calls; `FeedBand` loses the poster `<img>` and its empty slot, gains the
logo `<img>` (`sized_image_url(url, 480)`, `object-contain object-left`,
a 72px box, the typed title as `:if={!@entry.logo_url}` in the same slot),
`--x-body` to 92, `--h` to 264; the story's variations pin a band with a
logo, a band without, and the no-artwork band. The spec's size table takes
the new column.
