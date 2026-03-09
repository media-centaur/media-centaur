---
status: accepted
date: 2026-03-09
---
# Library two-zone layout with zone-dependent detail shells

## Context and Problem Statement

The original library page was a single flat grid mixing all entities with no distinction between in-progress content and the full catalog. Users had to scroll through everything to find what they were watching. The detail view was embedded inline, causing grid reflow.

## Decision Outcome

Chosen option: "Two-zone tabbed layout with ModalShell and DrawerShell", because it separates the "pick up where I left off" workflow from full catalog browsing, and each zone gets the detail presentation best suited to its use case.

- **Continue Watching zone** (default): Backdrop cards for in-progress entities. Detail opens in a centered **ModalShell** (overlay with backdrop blur) since the CW grid is sparse and doesn't benefit from side-by-side viewing.
- **Library Browse zone**: Poster grid with toolbar (type tabs, sort, text filter). Detail opens in a right-docked **DrawerShell** (480px reserved column) so users can browse the grid while viewing details. The column is always reserved to prevent grid reflow on open/close.
- **DetailPanel** is a shared function component rendered inside both shells — same content, different presentation wrapper.
- Zone switching uses `push_patch` within the same LiveView, preserving loaded data across tab changes.

### Consequences

* Good, because Continue Watching surfaces the most relevant content immediately
* Good, because the drawer's reserved space prevents disorienting grid reflow
* Good, because a single LiveView with `push_patch` avoids redundant data loading
* Good, because DetailPanel is reusable across both shells without duplication
* Bad, because the reserved 480px drawer column reduces grid space on smaller screens (mitigated with `hidden lg:block`)
