---
status: accepted
date: 2026-06-08
---
# Modals declare an ephemeral or persistent dismissal mode through one seam

## Context and Problem Statement

The app has ephemeral modals (click outside or Escape closes them: detail, pursuit, search, most confirmations) and persistent ones (open until an explicit choice, because a casual dismissal loses work: the report wizard). Every modal hand-rolled `modal-backdrop` / `modal-panel`, and the distinction lived in whether the author remembered `phx-click={@on_close}` on the backdrop.

## Decision Outcome

1. `MediaCentaurWeb.Components.Modal` (`<.modal>`) is the only place `modal-backdrop` / `modal-panel` may appear (MC0020).
2. `dismiss` is a **required** attr and all dismissal wiring derives from it.

   | `dismiss` | Backdrop click | Escape | Exit path |
   |---|---|---|---|
   | `:ephemeral` | closes | closes | also explicit buttons |
   | `:persistent` | no-op | no-op | explicit buttons only |

3. A persistent modal ignores Escape as well: no casual exits when progress is at stake.

### Consequences

* A stateful `live_component` cannot be the `<.modal>` root; its wrapper lives in the parent LiveView's overlays and the component supplies the panel content.
