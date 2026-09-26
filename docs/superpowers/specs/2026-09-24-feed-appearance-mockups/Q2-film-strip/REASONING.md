# Q2 · Film strip — reasoning

**Knobs** ground `ink` · unit `ink` 13% · edges `sheet` · hairline `off` · still `wide` · dissolve 240.

## Style

The page is the ink, flat with the blobs at a whisper. The bands are flush
with no hairline: one band ends where the next picture begins. The still
begins under the title's tail (x = 400, 836 wide) instead of at the text
zone's edge, so the frame is drawn at a larger scale — a 48% slice of its
height against the settled 74% — and a hint of it shows through the scrim
behind the words. The column reads as a reel.

## Decisions

* **The picture separates the bands.** With the page at ink there is no
  edge to draw; the change of still is the boundary. Where two adjacent
  bands share a title the 38% crop offset already makes them differ.
* **Wide, not full.** The full-bleed still (1236, a 32% slice) was rendered
  and kept on the switchboard: it cuts faces at the settled 30% crop
  (Sintel's forehead, Cary Grant gone). At 836 every fixture still frames
  its subject and the words keep a .93 scrim at their left, .86 at the time.
* **No hairline.** A hairline here would be a scanline across a photograph;
  the reel is the point.

## Requirements

* *Less boxes* — there is nothing but pictures and words on one dark page.
* *A good idea* — this is the direction the round 5 critique meant by "bands
  under the house scrim as the page"; the shipped page put them on the page
  instead.
* *Couch* — a bigger frame reads better from three metres; the words sit on
  ≥ .86 ink with the text shadow. A band without artwork stands out as a
  flat field, as it does today.

## Trade-offs

Gains: the most presence of the six; the "holy crap" candidate. Costs: the
words sit on a faint picture (7–14% through the scrim), so the text shadow
is doing real work; where two dark stills meet the boundary is soft, which
the no-hairline choice accepts; a flat ink page loses the app's blobs. In
the app: `--bx: 400px` and a reshaped `.feed-band-scrim`, the page ground
at `--ink`, the sheet rules without the hairline.
