---
status: accepted
date: 2026-08-10
---
# Cursor treatment tiers — ring by default, soft fill where the ring collides

## Context and Problem Statement

The keyboard/gamepad cursor is one visual idea everywhere: a 2 px primary outline, offset 2 px, whose value is regularity. It works on boxed controls and bare typography alike. The zone tabs broke it: their active state is a primary underline directly in the ring's path, and every ring variant tried produced two parallel primary strokes reading as one smeared line.

## Decision Outcome

1. **The ring is the cursor**, on boxed controls and bare text alike. Re-tinting and radius tuning are ring variations within this tier.
2. **Soft fill is the secondary cursor type**, used only where the ring would visually collide with an element of the surface itself, such as a stroke-based active marker in its path: a flat low-opacity neutral fill behind the content (`base-content` at ~11 %, negative-inset pseudo, no layout shift) with the focused text brightened. Fill = where the cursor is; primary colour = what is active.
3. **Minimise tier 2.** A new tier-2 surface must name the concrete collision the ring cannot escape. "The ring looks heavy here" and "it's just text" are not sufficient.

Current tier-2 surfaces: the zone tab strips (`.zone-tab`) on Incoming, Review and Discovery.

Rejected: tuned rings (each rebuilt the collision elsewhere), corner brackets (a third cursor shape), a second underline (not couch-visible), spotlight glow (least calm, invites over-application).

### Consequences

* Two cursor types exist; the user learns a quieter second "you are here" signal, bounded by rule 3.
