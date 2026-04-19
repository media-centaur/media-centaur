# Watch-dir runtime configuration

**Date:** 2026-04-19
**Status:** Approved — ready for implementation plan
**Supersedes:** Current TOML-only `watch_dirs` configuration

## Summary

Move watch-directory configuration out of the TOML config file into the in-app
Settings UI. The file watcher subsystem becomes dynamic: it runs no watcher
processes until at least one directory is configured, spins one up when a
directory is added, and tears one down when a directory is removed — all
without restarting the app. The add/edit dialog provides strong live validation
so users can confirm a path is usable before saving.

## Motivation

Today `watch_dirs` is a TOML-only setting. Changing it requires editing
`~/.config/media-centarr/media-centarr.toml` and restarting the process. This
is friction for users and, more importantly, misclassifies "which media
directories exist" as a deploy-time concern rather than a runtime one. It also
means a fresh install always has a meaningless placeholder path in the
shipped config, and the UI has no way to help the user pick a correct path.

## Goals

- TOML-free runtime changes to the watch-dir list.
- Fresh install has no configured dirs (watcher effectively off).
- Adding a dir live-starts a watcher; removing one live-stops it.
- The add/edit dialog gives rich inline feedback so misconfigurations are
  caught before save.
- No changes required at the 11 existing `Config.watch_dirs/0` call sites.

## Non-goals

- Removing a watch dir does **not** delete its library entries. Cleanup of
  orphaned entries remains a separate operation (existing "Clear Database"
  flow).
- No new rescan flow is built — existing Watcher + Pipeline behavior handles
  a freshly-started watcher seeing a populated directory.
- No server-side directory browser UI. Plain text input with validation only.
- The showcase override TOML (`MEDIA_CENTARR_CONFIG_OVERRIDE=…showcase.toml`)
  still works unchanged — the migration runs against the showcase instance's
  isolated DB.

## Design

### 1. Data model

Watch dirs live in a single `Settings.Entry` with key `config:watch_dirs`. The
value is a list of maps:

```elixir
%{
  "id" => "9f2b…",                # UUID, stable for the lifetime of the entry
  "dir" => "/mnt/videos/Movies",   # canonicalised absolute path
  "images_dir" => nil,             # optional absolute path; nil = use the
                                   # project's default image location under
                                   # data/images/ (current per-entity layout)
  "name" => nil                    # optional display label
}
```

**Why a list inside one entry** (rather than one `Settings.Entry` per dir):

- Matches how `Config` already shapes map-valued entries.
- A single read is atomic — no risk of observing a half-updated list.
- The PubSub signal on change is unambiguous.

**Why a UUID `id`:** the watcher registry and the UI reference entries by `id`,
so editing `dir` (which would otherwise be the natural key) does not orphan
anything and cleanly maps to a terminate-old + start-new action.

### 2. Source of truth and migration

- `MediaCentarr.Config.watch_dirs/0` keeps its current signature. Its
  implementation switches to read the `config:watch_dirs` Settings entry
  instead of parsing TOML.
- **None of the 11 existing callers change.**
- On application boot, if the `config:watch_dirs` Settings entry is absent,
  read the TOML `watch_dirs` (if any), assign UUIDs, and write a single
  `Settings.Entry`. After that first write, the TOML key is never read again.
  The migration is idempotent — a re-run is a no-op.
- `defaults/media-centarr.toml` loses the documented `watch_dirs` block. A
  pointer comment replaces it: "configured via the app — Settings → Library."
- `defaults/media-centarr-showcase.toml` is unchanged. The first boot of a
  showcase instance runs the same TOML → Settings migration against the
  showcase's isolated DB.

### 3. Runtime wiring

- `MediaCentarr.Watcher.Supervisor` remains always-started. With zero dirs
  configured it idles with zero children — `DynamicSupervisor` cost is
  negligible, and "off" is accurately modelled as "no children."
- New function: `MediaCentarr.Watcher.Supervisor.reconcile/1` takes the new
  list of watch-dir maps and computes a minimal set of actions:
  - **Added** id → start a new watcher child keyed by that id.
  - **Removed** id → terminate that child.
  - Id present in both lists but `dir` or `images_dir` changed → terminate old,
    start new.
  - Id present in both with only a `name` change → no-op for the watcher
    (the name is UI-only).
- `Config` emits `{:config_updated, :watch_dirs, new_list}` on write.
  `Watcher.Supervisor` subscribes at start and calls `reconcile/1` on each
  event.
- The registry key for watcher children becomes the entry's `id` (UUID), not
  the `dir` string.

### 4. Validation (live, in the add/edit dialog)

All validation runs in a pure module `MediaCentarr.Watcher.DirValidator`.
Filesystem primitives are injected so tests run `async: true` without touching
real disk. The dialog invokes the validator on a 500 ms debounce as the user
types and renders per-field status (green / amber / red + one-line message).

**On `dir`:**

1. Path exists.
2. Is a directory (not a file or symlink-to-file).
3. Readable by the app (`File.stat/1` + `File.ls/1` probe).
4. Not a duplicate of an already-configured dir. When editing an existing
   entry, that entry's own id is excluded from the comparison set so saving
   it unchanged is not a "duplicate."
5. Not nested inside, and does not contain, an already-configured dir
   (canonicalise both sides, compare path segments). Same edit-self exclusion
   applies.
6. Mount awareness: if the path crosses a mount point not currently mounted,
   show a warning but allow save (configuring ahead of time is legitimate).
7. Preview: once valid, show top-level counts — "Found N video files,
   M subdirectories."

**On `images_dir` (only evaluated when set):**

8. Exists, or its parent is writable (so the dir can be created on save).
9. Not inside any configured watch dir (prevents image cache from being
   scanned as media).

**On `name`:**

10. Unique among configured dirs (empty is fine — falls back to `dir` for
    display).
11. Trimmed, ≤60 characters.

Save is blocked while any field has an **error**. Warnings (e.g. unmounted
volume) do not block save.

### 5. UI

**Settings page placement:** existing `library` section gets a new "Watch
Directories" card above the existing extras/skip fields. The card shows the
current list as rows — `name` (or `dir` fallback) as the primary label, `dir`
and optional `images_dir` as secondary lines, plus edit and delete actions.

**Empty state on the Library home page** (unchanged link target): the existing
"Configure library" button at `/settings?section=library` keeps working.
Additionally, `/settings?section=library&add_watch_dir=1` deep-links directly
to the add dialog so a fresh user lands on the right screen in one click.

**Add/Edit dialog** (same modal for both flows, rendered with the
always-in-DOM pattern per UIDR-009):

- Fields: `dir`, `name`, disclosure → `images_dir`.
- Live validation per field, with status icon and one-line message.
- Preview section appears once `dir` is valid.
- Save is disabled while any field has an error.
- Cancel dismisses without writing.

**Delete confirmation:** inline confirm using the project's existing
destructive-action pattern. Copy clarifies: "This stops future scanning.
Existing library entries stay until you run Clear Database."

### 6. Testing

- **`DirValidator` pure tests** (`async: true`): one test per validation rule,
  covering valid and invalid cases for each. Filesystem ops are injected so
  tests don't hit the real disk.
- **`WatcherSupervisor.reconcile/1` action-calculator tests** (`async: true`):
  pure function on `(old_list, new_list)` returning
  `%{to_start: …, to_stop: …, to_replace: …}`. Exhaustive coverage of add,
  remove, dir-change, images-dir-change, name-only-change.
- **`Config.watch_dirs/0` round-trip** via `DataCase`: write Settings entry,
  read through `Config`, confirm shape unchanged for callers.
- **TOML migration test** via `DataCase`: starting with no `config:watch_dirs`
  entry and a synthetic TOML, run the migration, assert the entry exists with
  UUIDs and matching dirs; run migration again, assert no duplicate writes.
- **Settings LiveView integration test**: add, edit, delete, duplicate
  rejected, nested rejected, save-disabled-while-invalid.
- No assertions on rendered HTML. All non-trivial dialog logic lives in an
  extracted helper module (ADR-030).

## Rollout

- One git change covering the Settings entry, the `Config.watch_dirs/0`
  implementation switch, the `Watcher.Supervisor` reconcile logic, the
  migration, the validator, the settings UI, and the tests.
- No user-facing deployment gymnastics: existing TOML entries migrate on
  first boot of the new version. After that, edits go through the UI.
- Wiki pages to update in the same unit of work: `Configuration-File.md`
  (remove `watch_dirs` from the TOML reference), `Adding-Your-Library.md`
  (flip to the UI flow), `Settings-Reference.md` (document the new card).

## Risks

- **Migration failure on upgrade.** If TOML → Settings migration fails (e.g.
  the user's TOML is malformed), the user ends up with zero dirs configured
  and no obvious recovery path. Mitigation: log the TOML parse error
  explicitly through `MediaCentarr.Log`, and surface a banner on the settings
  page "Existing watch_dirs could not be migrated — see the console."
- **Nested-dir false negatives.** Symlinks can make two paths appear
  non-nested when they physically alias. Mitigation: canonicalise both sides
  with `Path.expand/1` + `File.read_link/1` resolution before comparing. Not
  a new risk — the current code has the same exposure.
- **Live-apply race.** A user saves, watcher starts, user saves again
  immediately — two reconcile events in flight. Mitigation: reconcile is
  idempotent on input state, and `Watcher.Supervisor` serialises its own
  reconcile handler (it's a single process).

## Open questions

None. All structural decisions were made during brainstorming and are locked
unless the user redirects during planning.
