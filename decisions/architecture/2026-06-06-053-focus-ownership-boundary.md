---
status: accepted
date: 2026-06-06
---
# Input system reconciles only the focus it owns; unmanaged surfaces cede

## Context and Problem Statement

The input system owns "where the cursor is" as state and re-asserts it onto the
fresh DOM after every LiveView patch (`_reconcileFocus`, `_ensureCursorStart` —
see `docs/input-system.md` → Post-patch focus reconciliation). The reconciler
infers "focus was lost, restore it" from `getCurrentFocusedItem() === null`.

That inference conflates two genuinely different situations:

1. Focus *was* on a managed nav item and a patch dropped it to `<body>` — the
   system owns this; restoring is correct (the `stream(:grid, …, reset: true)`
   regression this code was written for).
2. Focus *moved* to a real element outside every managed context — the system
   does not own this; it should leave it alone.

Both report no current nav item, so the reconciler restored in case 2 as well.
The visible failure: the **Track-new-release modal** is a plain `data-state`
overlay (not a `data-detail-mode` context), so it is invisible to the input
system, whose context stays on the page behind it. A user clicks the modal's
search field; ~1–2 s later an async re-render lands (suggestions load, search
results, any PubSub tick); the reconciler runs, sees "no nav item focused", and
yanks focus onto a page `.release-row`. The cursor leaves the field mid-typing.

This is one instance of a class: any focus surface the input system neither
**owns** nor **cedes to**.

## Considered Options

* **A — Editable-leaf guard.** Cede when `document.activeElement` is a text
  input / textarea / contenteditable. Fixes the typing symptom; ~5 lines.
  *Rejected:* it is a leaf-type proxy. It leaves the *same* modal's non-editable
  controls (suggestion cards, "Track" buttons, scope radios) exposed to the
  identical steal, and would needlessly cede for a *managed* filter input that
  lives inside a nav zone.
* **B — Focus-ownership by containment (chosen).** Cede when focus lives on a
  real element outside every managed nav region. Same footprint as A, but the
  signal is containment, not tag: protects the whole overlay, still restores on
  a genuine `<body>` drop, and does not interfere with managed inputs.
* **C — First-class managed contexts.** Register every overlay as an
  input-system context (focus-trapped, gamepad-navigable). Fully cohesive — no
  unmanaged focus surface can exist — but it is a *feature*: it imposes nav-grid
  semantics on free-form forms and must be built per overlay.

## Decision Outcome

Chosen option: **B**, because it models the actual invariant —
*the reconciler re-asserts only the focus the system owns* — at the same cost as
the symptom patch, and it has present value (it protects the existing modal's
buttons and cards, not just its search field).

The predicate is `reader.hasForeignFocus()`: focus is foreign when a live
element outside `[data-nav-item]` / `[data-nav-zone]` holds it, or the element
captures its own keys. `<body>` / `<html>` / no-activeElement are *not* foreign
(that is a real focus drop the system recovers).

**Option C is deliberately deferred, not rejected.** Revisit it when either
trigger fires: (a) more than one or two rich overlays accrue that need this
treatment, or (b) gamepad users need to drive modal content (today they can open
the Track modal but cannot navigate its results). Until then, an unmanaged
overlay simply benefits from B's cession for free.

### Consequences

* Good — closes the whole "unmanaged focus surface steals focus on re-render"
  class, not just the typing instance; protects every text field and overlay
  control on a nav-managed page.
* Good — strictly subtractive: the guard only *prevents* focus moves, never adds
  them. Normal keyboard/gamepad nav is untouched (nav items are never foreign),
  pinned by the existing 480+ input-system tests plus the `hasForeignFocus`
  containment tests and the "still restores on a body drop" complement test.
* Bad — the Track modal (and any future unmanaged overlay) remains
  gamepad-inert: opening works, but its contents are not navigable until/unless
  Option C is taken. Recorded as the deferred follow-up above.
