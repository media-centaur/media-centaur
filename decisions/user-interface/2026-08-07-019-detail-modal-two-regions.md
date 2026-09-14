---
status: accepted
date: 2026-08-07
amended: 2026-08-08
---
# The detail modal navigates as two regions, and BACK peels containment

## Context and Problem Statement

The detail modal carries Play, More info and Manage above the body of the title (seasons and episodes, a collection's films, extras). It navigated as one flat list of every focusable element in DOM order: reaching an episode meant stepping past the buttons and every row, leaving the list meant closing the modal, left and right were spent on "up" and "step into the row", and BACK closed the modal from anywhere.

## Decision Outcome

1. **Two regions, two nav zones.** `detail_actions` is the command row (Play / More info / Manage; left and right move between them and stop at the ends). `detail_list` is the body. Declared in the markup with `data-nav-zone`.
2. **Down enters the body at its highlighted item**: seeded from the episode Play would play (`[data-resume-target]`), thereafter wherever the cursor was last left. The memory is scoped to one opening.
3. **BACK leaves the region you are in.** From anywhere in the body one press lands on Play; from Play the next closes the modal. BACK is answered once, by walking containment: an overlay region's declared `back` edge → sub-focus exit → overlay dismissal → primary-menu exit → nothing.
4. **In the body, left and right are depth.** `aria-expanded` is the disclosure signal and a `data-nav-group` ancestor marks the disclosure's extent.

   | Cursor on | RIGHT | LEFT |
   |---|---|---|
   | Collapsed season | expand | — |
   | Expanded season | — | collapse |
   | Episode | step into its controls | collapse the season, landing on its header |
   | An episode's controls | next control | previous, then out to the row |

5. **UP at the top of a body region follows a graph `up` edge** (amended 2026-08-08): the episode tree climbs through `manage_tools` when Manage shows, else to the action row; the cast grid (`detail_cast`, a spatial SHELF) climbs the same way. BACK stays the one-press way out; UP is the one-row way up.
6. **Manage has its own regions** (amended 2026-08-08): `manage_tools` is a TOOLBAR (Delete all, Rematch, Refresh artwork, ID links; left/right along it, down past it, up to the action row) and the folder ledger is its own `manage_list` TREE, separate from `detail_list` so ledger activity never overwrites the episode list's remembered position.
7. **An overlay declares its navigation model or stays a flat list.** `data-nav-overlay="detail"` names the input-config entry carrying the regions; the overlay's topology is merged over the page's while open. A confirm dialog or small form keeps the flat behaviour.

### Consequences

* The list-wide "Show details" toggle is deliberately not a nav item (mouse only); it belongs with the other list-wide controls in Manage and is still to move.
* The `data-nav-*` attributes must be right in the template for the modal to navigate at all; `library_live_test.exs` asserts them.
