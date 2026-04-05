# Decide: DrawerShell for Library Browse, or supersede UIDR-006

**Source:** design-audit 2026-04-06, DS7
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/live/library_live.ex`, `lib/media_centaur_web/components/`, `decisions/user-interface/2026-03-09-006-library-zone-architecture.md`

## Context

[UIDR-006](../decisions/user-interface/2026-03-09-006-library-zone-architecture.md) specifies that the Library Browse zone opens entity details in a right-docked **DrawerShell** (480px reserved column) so the user can keep scanning the poster grid while reading detail. The Continue Watching zone is supposed to use ModalShell (centered overlay).

The implementation at `library_live.ex:101-106` hard-codes `:modal` for both zones:

```elixir
{_, :watching} -> :modal
{_, :library} -> :modal
```

There is no `DrawerShell` component in `lib/media_centaur_web/components/` at all. Library Browse opens in a centered modal, same as Continue Watching, and has for some time.

This is a silent disagreement between an `accepted` UIDR and the code. Every future audit will keep re-flagging it until the two agree.

## What to do

Pick one direction — don't leave the disagreement in place.

**Option A — honor UIDR-006.** Build `MediaCentaurWeb.Components.DrawerShell` as a sibling of `ModalShell`, then wire `{_, :library} -> :drawer` in `library_live.ex`. Notes:

- The drawer is a right-docked panel reserving a 480px column (`hidden lg:block`); grid reflow on open/close must not happen, so the column needs to be reserved whenever the zone is `:library`, whether or not anything is selected.
- Reuse `DetailPanel` inside the drawer exactly as ModalShell does — the whole point of the shared component is that the shell swaps, not the content.
- The "Always-in-DOM modal pattern" rule from `CLAUDE.md` applies: the drawer panel should be mounted unconditionally and toggled via `data-state="open"/"closed"`, never `:if={}`.
- Update the input system's `data-detail-mode="drawer"` handling — `assets/js/input/config.js` already has `DRAWER` selector mapped to `[data-detail-mode='drawer'] [data-nav-item]`.
- Update the nav graph: library zone's `grid.right` should go to `drawer` (it already does, as a candidate).

**Option B — supersede UIDR-006.** Write a new UIDR (next number in sequence) titled something like "Library detail shells (ModalShell for all zones)". Explain why the drawer was tried and dropped — if the answer is "the drawer was never built and ModalShell works fine on both zones, the reserved-column drawback isn't worth the code," say that directly. Mark UIDR-006 `status: superseded` with a pointer to the new record. Update `DESIGN.md`'s Library section accordingly.

## Acceptance criteria

- Either DrawerShell ships and Library Browse opens in it, **or** UIDR-006 is superseded with a clear replacement.
- No silent disagreement between UIDR and code.
- `mix precommit` clean.
