---
status: accepted
date: 2026-06-08
---
# Modals declare an ephemeral or persistent dismissal mode through one seam

## Context and Problem Statement

The app has two kinds of modal, but historically only by accident:

* **Ephemeral** — click outside or press Escape and it closes. The lightweight,
  common case (entity detail, pursuit detail, TMDB track search, most
  confirmations).
* **Persistent** — stays open until the user makes an explicit choice, because a
  casual dismissal would lose in-progress work (the report wizard).

There was no shared modal component. Every modal hand-rolled
`modal-backdrop` / `modal-panel`, and the ephemeral-vs-persistent choice was
*implicit* in whether the author remembered to put `phx-click={@on_close}` on
the backdrop. That made the distinction — real, deliberate design intent — live
nowhere in the code, and let dismissal wiring drift (an Escape binding with no
backdrop click, a `phx-click-away` on the panel that the MC0006 check exists to
catch).

## Decision Outcome

Introduce a single seam, `MediaCentaurWeb.Components.Modal` (`<.modal>`), the only
place `modal-backdrop` / `modal-panel` may appear (enforced by **MC0020**). It is
distilled from our best existing modals (`ModalShell` / `PursuitModal`): the panel
is always rendered in the DOM and toggled via `data-state`, keeping the
`backdrop-filter` compositing layer warm (no first-frame blur jank).

The ephemeral-vs-persistent distinction is a **required** `dismiss` attr:

| `dismiss`     | Backdrop click | Escape | Exit path             |
|---------------|----------------|--------|-----------------------|
| `:ephemeral`  | closes         | closes | also explicit buttons |
| `:persistent` | no-op          | no-op  | explicit buttons only |

Making `dismiss` required is the formalization: a modal cannot be mounted without
naming its kind, and all dismissal wiring is derived from that one value, so the
two behaviors can never be half-applied.

A persistent modal ignores **Escape** as well as backdrop click — Escape is a
casual exit, and "don't lose the user's progress" means no casual exits. This
changed the report wizard, which previously closed on Escape; it now relies on
its explicit "No, don't send" / "Close" buttons (both keyboard/gamepad-reachable).

### Consequences

* Good, because modal dismissal behavior is declared once, at the call site, and
  cannot silently drift.
* Good, because every modal inherits the warm-compositing behavior of our best
  modal rather than a stripped-down reimplementation.
* Good, because routing all modals through one seam eliminated the lone
  `phx-click-away`-on-panel deviation MC0006 was guarding against.
* Neutral, because a stateful `live_component` (the report wizard) cannot be the
  `<.modal>` root directly — a function-component call is not a single static
  root tag — so its `<.modal>` wrapper lives in the parent LiveView's overlays
  and the component supplies only the panel content.
* Bad (minor), because persistent modals now ignore Escape, which a few users may
  expect to dismiss any dialog; explicit controls remain the deliberate trade.
