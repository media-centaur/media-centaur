# Q1 · Dark sheet — reasoning

**Knobs** ground `dark` · unit `ink` 13% · edges `sheet` · hairline `on` · still `box` · dissolve 240.

## Style

The settled band on a page that has come down to meet it. Discovery's ground
is the app's, with the vertical dim starting at the top instead of a third of
the way down, so the page sits at about 15% with the two blobs faint. The
bands are flush in one column with the column's 12px corners; a hairline at
white/8 runs between them across the text zone and fades out over the
dissolve so it never scores a picture. The rail is one column of people the
same way, its hairlines inset to the card's padding.

## Decisions

* **The ground comes down rather than the unit coming up.** The ink was
  chosen so the words read; lifting the unit toward 27% would wash them.
  Darkening the page costs nothing the band has.
* **Flush, not gapped.** With the ground near the ink, a 6px gap is a faint
  seam and a corner a faint notch — leftovers. Merging the units removes the
  eight rectangles and leaves two columns.
* **The hairline stays.** Where two dark stills meet (Metropolis under
  Charade) the column would otherwise read as one field; the hairline keeps
  the list's rhythm without a box.
* **The lit unit shows its shape.** Hover and cursor lift the ground 13 → 16%
  and draw the 3px ring; inside a flush sheet the ring is square-cornered.
  That is the one moment a band is a rectangle, and it is the moment it
  should be.

## Requirements

* *Less "bunches of dark boxes"* — the boxes have nothing to show against.
* *Every option a good idea* — nothing in the band's anatomy or readability
  changes; the risk is only tonal.
* *Couch* — unchanged from G; the darker page is easier on a TV.

## Trade-offs

Gains: the settled design intact, one CSS change to the page's scrim plus the
sheet rules. Costs: Discovery becomes a darker page than its neighbours
(Home is already different, with artwork); the ground's blue blob is nearly
gone. In the app: a `.page-side-dim` variant for Discovery, `gap: 0` and no
per-unit radius on `.feed-column` and `.discovery-rail`, a `::before`
hairline on `.feed-band + .feed-band` and `.person-card + .person-card`.
