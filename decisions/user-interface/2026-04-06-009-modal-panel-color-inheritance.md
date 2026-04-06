---
status: accepted
date: 2026-04-06
---
# Modal panels must set explicit text color

## Context and Problem Statement

The TrackModal component rendered correctly structured HTML but all text was invisible against the dark background. The shared `.modal-panel` CSS class set `background-color: var(--color-base-100)` but did not set `color`, relying on inheritance from the page body. Because `.modal-backdrop` uses `backdrop-filter` and sits in a stacking context with `opacity` transitions, the inherited text color was lost — leaving child text invisible.

The existing ModalShell happened to work because its child component (DetailPanel) used explicit color classes on every element, masking the same underlying bug.

## Decision Outcome

Chosen option: "Set `color: var(--color-base-content)` on `.modal-panel` in `app.css`", because it fixes the root cause at the shared infrastructure level rather than requiring every modal to add explicit text colors to each element.

All modals that use `.modal-panel` (ModalShell, TrackModal, and any future modals) now inherit correct text color automatically. Individual components should not need `text-base-content` overrides on their children.

### Consequences

* Good, because new modals get correct text rendering without any extra work
* Good, because existing ModalShell behavior is unchanged (explicit classes override inherited color)
* Good, because it follows the principle of fixing shared infrastructure rather than patching individual components
