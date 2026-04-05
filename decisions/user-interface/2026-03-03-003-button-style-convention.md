---
status: accepted
date: 2026-03-03
last-updated: 2026-04-06
---
# Button style convention

## Context and Problem Statement

Solid-fill semantic buttons (`btn-success`, `btn-info`) washed out button text against glassmorphism surfaces. There was no consistent rule for when to use solid vs ghost vs soft button variants, leading to visual inconsistency across pages.

Two distinct destructive-action patterns had also emerged in practice: inline gestures (trash icons on file rows) that should disappear when not in use, and dangerous primary actions (Delete in a confirmation modal, Clear Database in the Danger Zone) that the user explicitly reached for and expects to find prominent. The original rule treated both the same and had to be amended once six sites diverged from it.

## Decision Outcome

Chosen option: "soft + semantic color for dangerous primary actions, ghost for inline/dismiss, solid only for primary CTA", because soft buttons keep text readable on glass surfaces while letting color carry the danger signal.

Rules:

1. **Action buttons** (approve, search, select, scan): `btn-soft` with semantic color (`btn-soft btn-success`, `btn-soft btn-info`).
2. **Dangerous primary actions** (Clear Database, Delete, Rematch, Stop Tracking, any button the user *deliberately reached for* where color is part of the warning): `btn-soft` with semantic color — `btn-soft btn-error` for irreversible/destructive, `btn-soft btn-warning` for risky-but-recoverable. Color carries the warning; `btn-soft` keeps the text readable on glass.
3. **Inline/dismiss actions** (trash icon in a file row, Cancel in a confirmation modal, a close `×`): `btn-ghost`, optionally with a semantic text tint (`text-error`) for destructive gestures. Minimal visual weight — these should recede until the user hovers.
4. **Solid-fill buttons**: acceptable only for `btn-primary` (theme accent) where a single dominant call-to-action is needed (e.g. form submit on the Review search panel).

Never use solid-fill `btn-success` / `btn-info` / `btn-warning` / `btn-error` without `btn-soft` — the saturated background washes out the text on glassmorphism surfaces.

### Consequences

* Good, because button text remains readable against glass surfaces
* Good, because the four-tier system (soft-action / soft-dangerous / ghost-inline / solid-primary) matches the patterns that actually ship
* Good, because dangerous CTAs in Danger Zones stay visible enough to be found
* Bad, because `btn-soft` is a daisyUI-specific class, coupling the convention to the component library
* Bad, because "dangerous primary" and "inline/dismiss" are a judgment call at the edges; rule of thumb is "did the user click a button to get here, or is this button on the page by default?"
