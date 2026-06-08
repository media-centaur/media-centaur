# Upgrade history on the Status → Updates drill-in

**Date:** 2026-06-08
**Status:** approved (design)

## Problem

The Status page's **Updates** subsystem drill-in shows the running version, the
last check, and auto-install state — but no record of *past* upgrades. A user
who has been running Media Centaur for months has no way to see which versions
they have run and when each one started running.

The SelfUpdate subsystem stores only the *last-known* release (`update.latest_known`)
and the *last* check timestamp (`update.last_check_at`). Nothing records the
transition from one running version to the next.

## Goal

Add an **upgrade history** to the `self_update_widget` (the Updates Activity
widget on `/status`): a newest-first list of versions the app has run, each with
the date it was first seen running. Detail per entry is intentionally minimal —
**version + date** (no build SHA, no notes link).

## Capture: boot-time version detection

A new module `MediaCentaur.SelfUpdate.History` owns the log. On each boot,
`SelfUpdate.boot!/0` calls `History.record_boot_version/0`, which:

1. Reads the newest recorded entry.
2. Compares its `version` against `MediaCentaur.Version.current_version/0`.
3. Appends a new entry `%{version, recorded_at}` **only** when the running
   version differs (or the log is empty).

This is **path-agnostic**: it records an upgrade regardless of whether it came
from the in-app "Update now" button, a manual reinstall, or the installer
script, because it keys off the version actually running rather than off any one
apply code path.

`boot!/0` is already prod-gated (`SelfUpdate.enabled?/0` is true only in `:prod`).
That is correct: dev builds rebuild from source and must not pollute the log.
On the **first prod boot after this ships**, the log is empty, so the current
version is recorded as entry #1. History therefore begins at the version where
this feature lands — there is no backfill of versions run before it existed, and
that is acceptable.

`recorded_at` is the boot-observation time — i.e. when the app first started
running that version, which is effectively the upgrade moment (within boot
latency). This is the honest "date" for an upgrade event; it is deliberately not
the release's build date.

### Testability

`record_boot_version/0` delegates to `record_boot_version/1` taking an explicit
version string, so tests drive version transitions without manipulating the
compiled app version. The prod gate lives in `application.ex` (where `boot!/0`
is already conditionally called), not inside `History`, so the module itself is
environment-agnostic and unit-testable under the DataCase sandbox.

## Storage: `Settings.Entry`, key `update.history`

Consistent with how the subsystem already persists `latest_known` and
`last_check_at` — no dedicated table. Value shape:

```elixir
%{
  "entries" => [
    %{"version" => "0.83.0", "recorded_at" => "2026-06-08T12:00:00Z"},
    %{"version" => "0.82.1", "recorded_at" => "2026-05-20T09:00:00Z"}
    # … newest-first
  ]
}
```

- **Newest-first** ordering, so the UI renders the list directly.
- **Capped at 50 entries** — append drops the oldest beyond the cap. A small,
  append-only display log; 50 versions is more history than any UI needs.
- Appends happen only at boot, which is single-threaded for this call, so there
  is no concurrent-write race to guard.

`recorded_at` is stored ISO8601; `list/0` decodes to `DateTime`.

**Alternative considered — a dedicated `update_history` Ecto table.** More
queryable, but a migration + schema is overkill for a tiny, append-only,
display-only log, and it would break the subsystem's "everything in
`Settings.Entry`" pattern. Rejected.

## Read path (ADR-051)

The history is loaded into an assign once, at mount, in `assign_self_update/1`
(alongside `last_check_at`), with a default in `assign_defaults/1`, then passed
through `activity_bundle/1` to the widget.

This is **not** to keep the render path free of DB queries — ADR-051 retired
that "no DB on the render/mount path" rule for local reads (it caused
first-paint flashes, and a local SQLite read is one user's millisecond). The
reason to hold it in an assign is simply that the history changes only at boot,
so re-reading it inside `activity_bundle/1` (which runs on every re-render/diff)
would be pointless work. Because it comes from an assign, the `select_subsystem`
patch that opens the drill-in renders it without any flash.

It does not need refreshing on `{:check_complete, …}` (a check never changes
history); a one-time mount read is sufficient, and an in-session upgrade would
restart the BEAM and drop the LiveView anyway.

## Public API

```elixir
SelfUpdate.upgrade_history() :: [%{version: String.t(), recorded_at: DateTime.t()}]
```

Delegates to `History.list/0`. Newest-first, possibly empty.

## Display: `self_update_widget`

New typed attr on `MediaCentaurWeb.ActivityWidgetComponents.self_update_widget/1`:

```elixir
attr :history, :list, default: [],
  doc: "upgrade history, newest-first: [%{version, recorded_at}]"
```

A new **History** section renders below the "Automatic install" line: a compact
list, newest-first, each row showing `vX.Y.Z` on the left and the date
(e.g. `Jun 7, 2026`, via `Calendar.strftime/2`) on the right. When `history` is
empty the section is omitted entirely (no empty-state copy needed — a fresh
install simply has no history yet).

## Testing

- **`MediaCentaur.SelfUpdate.History`** (DataCase):
  - records the current version when the log is empty
  - records a new entry when the version changed
  - is a no-op (no duplicate) when the version is unchanged
  - caps the stored list at 50, dropping the oldest
  - `list/0` returns newest-first `DateTime`-decoded entries
- **`self_update_widget`**: a storybook variation with a populated `history`
  and one with `history: []`; the existing render/compile storybook tests
  enforce MC0009 coverage.
- **Story** updated in the same change (MC0009): `storybook/status/self_update_widget.story.exs`
  gains a `history` attr in its variations.

## Out of scope

- Build SHA / built-at per entry (chose version + date only).
- Links to per-release GitHub notes.
- Backfilling versions run before this feature shipped.
- A dedicated history table / queryable history beyond the 50-entry display log.
