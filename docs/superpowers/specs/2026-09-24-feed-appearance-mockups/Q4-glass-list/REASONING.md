# Q4 · Glass list — reasoning

**Knobs** ground `app` · unit `glass` · edges `sheet` · hairline `on` · still `box` · dissolve 240.

## Style

The house idiom applied at the column: the Feed column and the rail are
each one `.glass-surface` — the translucent panel, the 1px border, the
shadow, the 12px blur — with 14px corners, and the rows sit on the panel
with a hairline between them. The stills fade into the glass. The page has
two surfaces, both the shape every other page's cards have.

## Decisions

* **A surface lighter than the page.** Glass at 20%/.45 over today's ground
  is the app's own answer to the inversion; it reads as a panel, not a hole.
* **Two panels, not eight.** The panel is the column; the unit is a row.
  Settings and Status compose this way.
* **The still inside the glass.** The picture fades to the panel's tone,
  not to the page's, so the row's right edge belongs to the panel.

## Requirements

* *Less boxes* — two panels replace eight units, and a panel is the app's
  vocabulary.
* *A good idea* — the most consistent with the rest of the app; a
  contributor would recognise it immediately.
* *Couch* — words on glass over 27% read as on Settings; the stills are
  the settled size.

## Trade-offs

Gains: nothing new in the design system; blur and border are the house
recipe. Costs: the least cinematic; the panel's border and lighter fill
make the Feed a card again at the column scale, and a 1845px-tall glass
panel for the rail is a large blur surface (the blur is on the panel, not
per row, so the cost is bounded). In the app: `.glass-surface` on
`.feed-column` and `.discovery-rail`, the units transparent, the scrim off,
the sheet rules.
