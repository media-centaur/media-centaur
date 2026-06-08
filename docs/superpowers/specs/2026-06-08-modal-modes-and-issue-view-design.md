# Modal dismissal modes + the ephemeral Issue view

**Date:** 2026-06-08
**Status:** Approved, in implementation

## Problem

The app has two kinds of modal, but only by accident:

- **Ephemeral** — click outside or press Escape and it's gone. Good, lightweight UI;
  the overwhelming majority of modals (`ModalShell`, `TrackModal`, `PursuitModal`,
  the Settings watch-dir dialog).
- **Persistent** — stays open until the user makes an explicit choice, because
  dismissing it would lose work or in-progress input (`ReportModal`, the report
  wizard).

There is no shared `<.modal>` seam. Each modal hand-rolls `modal-backdrop` /
`modal-panel`, and the ephemeral-vs-persistent choice is *implicit* in whether the
author remembered to put `phx-click={@on_close}` on the backdrop. The distinction
is real design intent that lives nowhere in the code.

Separately: the Status page lists incidents ("issues") but there is no way to
**inspect** one. The only action on a row is "Report this" — you must report an
issue to even see what it contains. Users need to understand a problem before
deciding to report it.

## Design

### Part 1 — One modal seam, mode named at the call site

New component `MediaCentaurWeb.Components.Modal` is the **only** place
`modal-backdrop` / `modal-panel` may appear (enforced by Credo).

```heex
<.modal id="error-report-modal" open={@open} dismiss={:persistent} on_close="report_cancel">
  ...panel content (default slot)...
</.modal>
```

The deliberate distinction is a single **required** attr, `dismiss`:

| `dismiss`     | Backdrop click | Escape | Exit path               |
|---------------|----------------|--------|-------------------------|
| `:ephemeral`  | closes         | closes | also explicit buttons   |
| `:persistent` | no-op          | no-op  | explicit buttons only   |

`dismiss` is required — a modal cannot be mounted without naming its kind. The
component derives all dismissal wiring from that one value, so the two behaviors
can never drift apart or be half-applied.

**Behavior change:** `:persistent` ignores **Escape** as well as backdrop click.
Escape is a casual exit; "don't lose the user's progress" means no casual exits.
This changes `ReportModal`, which currently closes on Escape — it keeps its
explicit "No, don't send" / "Close" buttons (both keyboard/gamepad-reachable).

**Attrs**

- `id` — required.
- `open` — boolean, default `false`. Drives `data-state="open"/"closed"`.
- `dismiss` — `:ephemeral | :persistent`, **required**.
- `on_close` — string event. Required for `:ephemeral`; ignored for `:persistent`.
- `size` — `:md` (default, `.modal-panel`) or `:sm` (`.modal-panel-sm`).
- `panel_class` — extra classes on the panel (e.g. ReportModal's
  `flex flex-col max-h-[88vh]`).
- `:rest` — global attrs forwarded onto the **backdrop** (ModalShell's
  `data-detail-mode` / `data-detail-view` hooks).
- default slot — panel body.

The panel always carries `phx-click={%Phoenix.LiveView.JS{}}` to stop propagation
(harmless for `:persistent`, which has no backdrop handler anyway).

**Migration** — every modal moves onto the seam:

| Modal                          | mode          | note                                   |
|--------------------------------|---------------|----------------------------------------|
| `ModalShell`                   | `:ephemeral`  | forwards `data-detail-*` via `:rest`   |
| `TrackModal`                   | `:ephemeral`  |                                        |
| `Acquisition.PursuitModal`     | `:ephemeral`  |                                        |
| `ReportModal`                  | `:persistent` | drops Escape-to-cancel                 |
| Settings `watch_dir_dialog`    | `:ephemeral`  | removes the lone MC0006 `phx-click-away` deviation |

### Part 2 — Ephemeral Issue view

Clicking an incident **row body** opens an ephemeral `<.modal>` showing everything
known about that `ErrorReports.Bucket`:

- **Header** — severity dot + `display_title`; subsystem glyph + name.
- **Meta** — `count`× occurrences; first-seen → last-seen (relative + absolute).
- **Context** — `HealthBoard.description(component)`: plain-language description of
  what the subsystem does, so the issue isn't naked jargon.
- **Technical detail** — `sample_entries` as a timestamped log list (the data
  currently buried in the drill-in's collapsed "View technical logs").
- **Footer** — **Report this** (primary), **Dismiss**, **Close**.

**Row + flow changes**

- The incident **row body becomes the click target** → opens the issue view. The
  dismiss **X stays on the row** for fast triage (stops propagation).
- **"Report this" moves off the row** into the issue view footer. The row gets
  quieter (title + meta + X). Reporting becomes a deliberate act from inside the
  issue you've just read.
- **Issue view → wizard handoff:** "Report this" closes the ephemeral issue view
  and opens the `:persistent` report wizard pre-loaded with that bucket — the
  existing `open_error_report_modal` path.

**State:** `StatusLive` gains a `:selected_incident` assign (fingerprint or bucket);
the `IssueView` modal renders in the overlays slot when present.

## Enforcement & artifacts

- **Credo check** — `modal-backdrop` string literal may appear only in `modal.ex`
  (and the check's own test fixtures). Forces all modals through the seam.
  Existing MC0006 (`phx-click-away` on `modal-panel`) stays as cheap defense.
- **ADR** — `decisions/user-interface/` records the two-mode rule and when to use
  each.
- **Stories** — `<.modal>` story with both `dismiss` modes; `IssueView` story with
  severity / log-sample variations (MC0009).
- **Tests** — `status_live_test`: row-click → issue view → report handoff →
  dismiss. Component render tests for both new components.

## Non-goals

- No per-bucket AI/plain-language summaries beyond the subsystem description.
- No change to how incidents are detected, bucketed, or persisted.
- No new modal sizes beyond `:md` / `:sm`.

## Reversibility

Additive: a new component plus mechanical migrations. Mode is a single attr; the
issue view is a new surface that doesn't alter the report pipeline. Reverting is
unwinding the migration commits.
