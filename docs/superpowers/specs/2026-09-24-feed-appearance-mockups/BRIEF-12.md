# Round 12 brief — where the picture sits and where the time sits

**Date** 2026-09-26. **Starts from** R2 (round 11's recommendation: Q6's
page, the poster gone, the logo as the headline). **Trigger** the owner:
"i hate the timestamp being in the middle of the row and the image on the
right tbh".

## One cause

The still's box begins at the text zone's edge (x = 700), so the text zone
ends there and the time, right-aligned to the zone, lands mid-band. The
time can only go to the band's right edge if that edge is ground the time
can sit on — which means the picture moves.

## The knobs

On R2's page, in `round12.css`, built by `make-round-12` from round 11's
markup:

| Knob | Values | What it moves |
|---|---|---|
| The picture | box · inset · flush · full | the settled right box; a 16:9 thumbnail in the poster's slot at the tile's right; the still at the band's left edge at full height, the tile after it; the still under the whole band |
| The time | zone · edge | right-aligned at 700; the band's right edge, 20px in, on line 1's height |
| Rounds 10–11 | ground · edges · hairline · logo · logo height · mix | carried |

With the picture on the left the still is drawn whole: a 16:9 box at the
band's height shows the entire frame. Nothing is cropped, so the crop rule,
the 38% offset for adjacent bands of one title, the mask and the scrim all
fall away. The review's measure is capped at 640px, since a line the width
of the band is no favour to a reader.

## The directions

| | Picture | Tile | Time | Band |
|---|---|---|---|---|
| S1 Picture left | 16:9 thumbnail in the poster's slot, 391×220 | first, at x = 20 | right edge | 264 (the logo headline) |
| S2 Picture flush | the band's left end, 469×264 | after the picture | right edge | 264 |
| S3 Full bleed, time at the edge | under the whole band | first | top right over a right-edge vignette | 264 |
| S4 Picture left, typed title | 320×180 | first | right edge | 224 (no logo) |

S4 is S1 without the logo, so the composition can be judged apart from the
round-11 question.

## Deliverables

`S1`–`S4` pages with `REASONING.md`; `Q-place-switchboard/index.html`
(rounds 10–12's knobs live); `Q-place-switchboard/compare.html` (R2 beside
the four at half size); `CRITIQUE-12.md`.
