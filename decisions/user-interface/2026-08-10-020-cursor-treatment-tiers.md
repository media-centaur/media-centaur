---
status: accepted
date: 2026-08-10
---
# Cursor treatment tiers — ring by default, soft fill where the ring collides

## Context and Problem Statement

The keyboard/gamepad cursor is one visual idea everywhere: a 2px primary
outline, offset 2px ([UIDR-018] governs where it goes; this record governs
what it looks like). Its value is regularity — the user reads "blue ring =
cursor" without thinking, on every page. It works on bare typography too:
the detail page's action row (the Manage gear and its siblings) carries the
standard ring on essentially bare controls, comfortably.

The Incoming zone tabs broke it — not because they are text, but because of
what sits next to the text: their *active* state is already a primary-blue
underline, directly in the ring's path. Three ring variants were tried and
all failed the same way: the ring's bottom edge runs parallel to the active
underline a few pixels away — two primary 2px strokes reading as one smeared
double line — and geometry tuning (larger standoff, pill radius, a bordered
pseudo stopping above the underline) just rebuilt the collision in a new
place while the type sat ever less comfortably inside the growing box. The
failure is a **collision between the ring and a visual element of the
surface itself**, and no offset resolves two strokes that must occupy the
same neighbourhood.

So a few surfaces cannot carry the standard cursor. The question is what
they carry instead, and how to keep that from eroding the regularity that
makes the cursor work.

## Decision Outcome

**Two tiers, and a strong default.**

1. **The ring is the cursor** — on boxed controls and bare typography alike.
   Re-tinting (the subsystem tiles' gold) and geometry tuning (the
   library-tabs' hugging radius) are ring variations, not departures; they
   stay within tier 1.

2. **Soft fill is the secondary cursor type.** Where the ring would
   *visually collide* with an element of the surface itself — the known case
   being a stroke-based state marker in the ring's path, like the subnav's
   active underline — the cursor is instead a flat, low-opacity neutral fill
   pooled behind the content (`base-content` at ~11%, negative-inset pseudo,
   no layout shift), with the focused text brightened. No stroke — so
   nothing can collide. The two signals then occupy separate channels:
   **fill = where the cursor is; primary color = what is active.**

3. **Minimize tier 2.** Regularity and predictability are the UX; every
   deviation spends them. A new tier-2 surface must name the concrete
   collision the ring cannot escape. "The ring looks heavy here" is not
   sufficient, and neither is "it's just text" — the ring is fine on text.

Current tier-2 surfaces: the zone tabs (`.zone-tab` — Incoming, Review, and
home zones).

## Considered and rejected

From a four-direction brainstorm against the zone tabs:

* **Tuned rings** (bigger offset; pill radius; word-wrapping bordered pseudo
  that stops above the underline) — each rebuilt the stroke-on-stroke
  collision in a new place, at growing cost to how the type sat in the box.
* **Corner brackets** (game-menu ticks) — solves the collision and is
  controller-native, but introduces a third cursor shape; adopting it only
  here maximizes irregularity, adopting it everywhere is a redesign.
* **Cursor-as-second-underline** — purest typographically, weakest at ten
  feet; a 2px neutral line is not a couch-visible cursor.
* **Spotlight glow + scale** — strongest at distance but the least calm, and
  glow as a cursor idiom invites over-application.

## Consequences

* Good, because a contributor hitting an awkward ring has a decided answer:
  first exhaust tier 1 (re-tint, re-radius), and only reach for the soft
  fill on a named, concrete collision — instead of inventing a fourth
  treatment.
* Good, because the channel split (fill = cursor, color = state) composes
  with any stroke-based active marker without geometry negotiation.
* Bad, because two cursor types exist at all; the user now learns a second
  (if quieter) "you are here" signal. Accepted, bounded by rule 3.

[UIDR-018]: 2026-08-07-018-focus-cursor-and-scroll.md
