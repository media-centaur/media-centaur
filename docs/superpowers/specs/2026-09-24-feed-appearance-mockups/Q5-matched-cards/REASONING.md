# Q5 · Matched cards — reasoning

**Knobs** ground `dark` · unit `ink` 13% · edges `cards` · hairline `off` · still `box` · dissolve 240.

## Style

The settled page with one change: Discovery's ground comes down to the
ink's tone. Every unit keeps its 12px corners and the 6px gap; at rest the
edges have almost nothing to show against, and under the cursor the lit
unit shows its shape as it does today.

## Decisions

* **Change the ground and nothing else.** The complaint is contrast, so
  remove the contrast; leave the structure the owner approved.
* **Keep the units discrete.** One action is one thing; a gapped card says
  so at rest and under the cursor. The sheet directions say it only under
  the cursor.

## Requirements

* *Less boxes* — the edges go quiet; the gaps remain as faint seams where
  the blob shows through.
* *A good idea* — the least change that answers the complaint; every
  measurement in G stands.
* *Couch* — unchanged.

## Trade-offs

Gains: one CSS rule (the Discovery scrim variant) and the campaign's spec
untouched. Costs: the least effective of the six at the stated goal — the
cards still read as cards, and the rail's especially, because the seams
between them stay visible. In the app: the `.page-side-dim` variant only.
