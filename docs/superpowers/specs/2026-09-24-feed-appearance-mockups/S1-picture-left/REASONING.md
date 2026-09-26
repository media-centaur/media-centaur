# S1 · Picture left — reasoning

**Knobs** picture `inset` · time `edge` · logo `headline` (72) · on Q6's page.

## Style

The settled anatomy with one substitution. Where the poster stood — at the
tile's right, in the band's left third — the still, as a 16:9 thumbnail
showing the whole frame (391×220 in the 264 band), with the poster's
radius, hairline outline and shadow. Then the words: who did what, the
logo, the review. The time at the band's right edge on the first line,
where every list puts it. No scrim, no mask, no dissolve: the band is a
row with a picture in it, on ink.

## Decisions

* **The picture takes the poster's slot.** The settled order — tile,
  picture, words — is kept exactly; only the picture's shape changes from
  2:3 to 16:9. The author mark stays first.
* **The whole frame.** A 16:9 box at the band's height shows the frame
  entire, so the crop rule, the adjacent-band offset, the mask and the
  scrim are gone. Two adjacent bands of one title show the same frame,
  honestly.
* **The time at the edge.** The zone no longer ends at 700; the words run
  to the band's edge and the time sits where the rail's ago sits, top
  right.
* **A reading measure.** The review is capped at 640px so a line does not
  run the band's width.

## Requirements

* *Not the image on the right* — the picture is at the left, in the slot
  the eye already reads second.
* *Not the time in the middle* — the time is at the edge.
* *A good idea* — the fewest moving parts of any round: no crop, no scrim,
  no dissolve, one picture, one title.

## Trade-offs

Gains: the calmest band of the campaign; the frame whole; the settled
reading order; the crop machinery deleted. Costs: the band's right half is
ink with only the time on it when a band has no review; the still is
smaller than Q6's and the page is less cinematic; the picture is not a
photograph fading out of the dark but a thumbnail with an edge. In the
app: the backdrop `<img>` moves to the poster's position at 16:9, the mask
and scrim rules go, the time's anchor moves to the band's right, and
`FeedEntry.offset_crop?` and its projection logic are deleted.
