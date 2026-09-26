# Round 11 brief — backdrop and logo instead of poster and backdrop

**Date** 2026-09-26. **Starts from** Q6 (round 10's recommendation: the
dark ground, the flush columns, the hairline, the wide still). **Trigger**
the owner: "we're currently using the poster and the backdrop on the
feed.. i'm not sure but this may be causing some irritation for me. what if
we used the backdrop and the logo instead? what could we do with the ui
with that?"

## What the poster does on a band, and what it costs

It identifies the title at a glance through a familiar image; it is a
vertical element that gives the 224px band its height; it is the colour
accent on a dark row. It costs: a second picture of the same title beside
the first, in a different aspect and grade; its own printed title under
the band's typed title, so the name appears twice; a repeat of the rail,
where the same posters are the person's acts; and 118px of the text
zone's width. Three objects — tile, poster, still — compete in every band.

## What the logo brings

The title in its own lettering, which is what a poster's identity mostly
is, without the second picture. The app already renders a logo over a
backdrop in three places (the Home hero, the Coming Up marquee, the
collection rail), always with the typed name as the fallback, always
`text-on-image-lg`. Coverage in the owner's library: 27 of 30 movies and
14 of 14 series carry one; the Feed's artwork ladder
(`MediaCentaur.TitleArtwork.urls/3`) already returns `logo_url` for every
entry, and `FeedEntry` drops it. An unowned friend's title has a logo only
when the referenced cache holds one, so the Feed will be a mix and every
direction must draw the fallback well.

## The knobs

On Q6's page, in `round11.css`, built by `make-round-11` from G's state 1
with the poster removed from every band:

| Knob | Values | What it moves |
|---|---|---|
| The logo | none · headline · card · hero | gone with nothing in its place; line 2 on the ink; on the picture; the hero's order |
| Logo height | 56 · 72 · 96 | the box; headline and hero grow the band by it (192 + h) |
| Card placement | seam · corner | on the dissolve at the picture's left edge; bottom right over a foot gradient |
| Titles with a logo | some · all · none | four titles typed (the realistic mix); every one; every band typed |
| Round 10's knobs | ground · edges · hairline · the still | carried, so a direction can be judged on any page |

The wordmarks are stand-ins built from each band's own title text in the
fonts this machine has, one treatment per title, some tinted. They stand
for the logo PNGs the way the photo tile stood for a photo: the layout and
the mix are the subject, not the lettering. The showcase has one logo
across its titles because TMDB has none for most public-domain films; the
owner's library is the opposite case.

## The directions

| | The title is | Band | Still |
|---|---|---|---|
| R1 Backdrop only | typed, line 2 | 224 | wide |
| R2 Logo headline | the logo as line 2, on the ink | 264 | wide |
| R3 Title card | the logo on the picture, bottom right | 224 | wide |
| R4 Hero band | the logo first, the words under it | 264 | full |

The rail is not in this round: a person's card is their acts as posters
(UIDR-046), a different surface with a different subject.

## Deliverables

`R1`–`R4` pages with `REASONING.md`; `Q-logo-switchboard/index.html`
(both rounds' knobs live); `Q-logo-switchboard/compare.html` (Q6 and the
four at half size); `CRITIQUE-11.md`.
