---
status: accepted
date: 2026-03-03
---
# Button style convention

## Context and Problem Statement

Solid-fill semantic buttons (`btn-success`, `btn-info`) washed out button text against glassmorphism surfaces. There was no consistent rule for when to use solid vs ghost vs soft button variants, leading to visual inconsistency across pages.

## Decision Outcome

Chosen option: "soft variants for actions, ghost for dismiss, solid only for primary CTA", because soft buttons provide readable colored text on a subtle tinted background without competing for attention.

Rules:

1. **Action buttons** (approve, search, select): `btn-soft` with semantic color (`btn-soft btn-success`, `btn-soft btn-info`).
2. **Destructive/dismiss actions**: `btn-ghost` — minimal visual weight for secondary or negative actions.
3. **Solid-fill buttons**: acceptable only for `btn-primary` (theme accent) where a single dominant call-to-action is needed (e.g. form submit).

### Consequences

* Good, because button text remains readable against glass surfaces
* Good, because the three-tier system (soft/ghost/solid-primary) provides clear visual hierarchy
* Bad, because `btn-soft` is a daisyUI-specific class, coupling the convention to the component library
