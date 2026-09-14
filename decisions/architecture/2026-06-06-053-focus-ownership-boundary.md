---
status: accepted
date: 2026-06-06
---
# Input system reconciles only the focus it owns; unmanaged surfaces cede

## Context and Problem Statement

After every LiveView patch the input system re-asserts the cursor onto the fresh DOM, inferring "focus was lost" from the absence of a focused nav item. That inference conflated a real drop to `<body>`, which the system owns and must restore, with focus resting on an element outside every managed nav region, which it does not own. A plain overlay's search field lost the cursor mid-typing on every async re-render.

## Decision Outcome

1. **The reconciler re-asserts only the focus it owns.** Before restoring, it asks `reader.hasForeignFocus()` and cedes when the answer is yes.
2. **Focus is foreign when a live element outside `[data-nav-item]` and `[data-nav-zone]` holds it, or the element captures its own keys.** `<body>`, `<html>` and no active element are not foreign: that is a real drop the system recovers.
3. **Registering every overlay as a managed, focus-trapped context is deferred, not rejected.** Revisit when more than one or two rich overlays need the treatment, or when gamepad users need to drive an unmanaged overlay's contents.

### Consequences

* The guard is strictly subtractive: it only prevents focus moves, so managed keyboard and gamepad navigation is untouched.
* An unmanaged overlay remains gamepad-inert; its contents are not navigable until it is registered.
