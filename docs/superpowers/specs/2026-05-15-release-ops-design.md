# Release Ops: First-Class End-User Data Migrations

**Status:** approved design, ready for implementation plan
**Author:** Shawn McCool (with Claude)
**Date:** 2026-05-15

## Problem

End-user data needs occasional one-shot operations on upgrade — backfills,
shape repairs, config-key renames, stale-state cleanups. Today these
piggyback on Ecto schema migrations, which causes two distinct failure
modes:

1. **Dev-marks-done trap.** `mix ecto.migrate` from a dev session against
   a shared DB inserts a `schema_migrations` row. When the *release*
   later upgrades, Ecto sees the migration as already applied and skips
   it. The end user is left with un-repaired data. We hit this with the
   `WatchedFile.movie_series_id → movie_id` repair: it was marked
   applied via dev tooling, then a real ingest on prod left a row in
   the old shape, and the migration didn't fire to clean it up.

2. **Race against the supervision tree.** Even when a fix runs at boot,
   it competes with Phoenix / Broadway / watcher / PubSub subscribers
   coming up. Subsystems may observe half-migrated data, latch onto
   stale state, and end up in a "poopy" state that only resolves on a
   second restart. The first boot after upgrade should *deterministically*
   produce a healthy system, not require a manual second restart.

Both failures share a root cause: **data operations are wedged into a
mechanism (Ecto migrations) designed for schema convergence, not for
end-user-data lifecycle**. Schema migrations are designed to converge
the schema to a target shape; data operations need additional
guarantees the schema migration mechanism doesn't provide.

## Goal

Make end-user data migrations a first-class concept with its own
mechanism, contract, and tracking. Specifically:

- A dev `mix ecto.migrate` cannot mark an end-user-data operation as
  done.
- On first boot after upgrade, all data operations complete *before*
  the supervision tree starts. No subsystem can observe partial state.
- Failed operations halt boot loudly rather than silently leaving
  half-migrated data and proceeding to a broken-looking app.
- The mechanism is general enough to cover not just data repairs but
  any one-shot release operation that fits the same shape (config
  renames, stale-job cleanups, etc.).

## Non-Goals

Explicit out-of-scope items for v1, to keep the surface tight:

- **UI surface in the in-app updater.** Stdout logs are sufficient.
- **"Skip this op" escape hatch.** An operator can edit the
  `release_ops` table manually in the rare case they need to bypass.
- **Concurrent operations.** Sequential is simpler and we have no
  throughput requirement.
- **Filesystem operations.** Not blocked structurally, but not the
  focus of v1. Per-op contract notes that rollback only covers DB
  writes.
- **Boot-time invariant checks** (e.g., "no orphan WatchedFiles").
  Separate concern; the user said no.
- **Generalised "boot stages."** Same answer; the user said no.

## Design

### Boot sequence

```
release start
  ├─ run schema migrations (Ecto, existing)
  ├─ run release ops (new, sequential, halt on failure)
  └─ start supervision tree (Phoenix, Broadway, watcher, …)
```

Release ops are the new gate. Until they finish, the supervision tree
doesn't start — no subscriber, no LiveView, no pipeline can observe
half-migrated state. This eliminates the race described in the problem
statement.

### Components

| Component | Responsibility | Location |
|---|---|---|
| `MediaCentarr.ReleaseOp` | Behaviour. Defines the contract every op implements. | `lib/media_centarr/release_op.ex` |
| `MediaCentarr.ReleaseOps` | Discovery + runner + table queries. | `lib/media_centarr/release_ops.ex` |
| `release_ops` table | Tracking: `name TEXT PRIMARY KEY, applied_at, runtime_ms, status`. **Separate from `schema_migrations`** so `mix ecto.migrate` from dev cannot shadow it. | new Ecto migration |
| `priv/release_ops/*.exs` | Individual op files. Auto-discovered, ordered by timestamp prefix. | `priv/release_ops/` |
| `MediaCentarr.Release` | Extended to call `ReleaseOps.run_all/0` after `Ecto.Migrator.up`. | `lib/media_centarr/release.ex` |
| `Mix.Tasks.MediaCentarr.ReleaseOps` | Dev task — same runner code path driven by Mix instead of release boot. | `lib/mix/tasks/media_centarr.release_ops.ex` |

### Op file shape

Mirrors Ecto migrations so the mental model is instantly legible:

```elixir
# priv/release_ops/20260515000000_repoint_collection_child_watched_files.exs
defmodule MediaCentarr.ReleaseOps.RepointCollectionChildWatchedFiles do
  use MediaCentarr.ReleaseOp

  @impl true
  def description, do: "Repoint collection-child WatchedFiles from MovieSeries to Movie"

  @impl true
  def run do
    # Idempotent — re-running is a no-op once the data is clean.
    # Returns :ok or {:error, reason}.
  end
end
```

The behaviour declares two callbacks:

- `run/0` — required, returns `:ok | {:error, term}`.
- `description/0` — optional, human-readable string for logs.

### Per-op runner flow

```
fetch unapplied ops (sorted by name)
for each op:
  insert release_ops row (status=:running)         ← outside transaction
  Repo.transaction(fn ->                            ← op's work
    case op_module.run() do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
  on {:ok, :ok}        → update row (status=:applied, runtime_ms)  ← outside
  on {:error, reason}  → update row (status=:failed) + raise → boot halts
  on raise inside run/0 → caught, update row (status=:failed) + reraise
```

Bookkeeping writes (`:running`, `:applied`, `:failed`) happen **outside**
the op's transaction so a rollback can't lose the audit trail. The op's
writes happen **inside** so a failure can't leave half-migrated data.

**Guarantee:** after each op, the DB is either fully advanced (op
applied) or fully untouched (op failed, will retry on next boot).

A `:failed` row means the op was attempted and didn't complete. On the
next boot the runner picks it up again as if unapplied. The op's
idempotency contract protects against partial execution.

### Op contract

Hard rules every op must follow:

- **Idempotent.** Re-running on a clean state must be a no-op. The
  runner skips ops already recorded as `:applied`, but if a row is
  manually deleted or the previous run failed mid-flight, `run/0` will
  be invoked again — and must do no harm.
- **Returns `:ok | {:error, reason}`** — `{:error, _}` is the rollback
  signal to the runner.
- **Does not manage its own transaction.** The runner owns the
  transaction; nested transactions would defeat the rollback contract.
- **Pure DB side effects (for now).** Non-DB side effects (filesystem,
  external HTTP) aren't structurally blocked, but the transaction
  doesn't roll them back, and the op author is responsible for making
  them idempotent and safe-to-partially-apply.

### Visibility

Plain stdout logging during boot:

```
[release_ops] applying 20260515000000 RepointCollectionChildWatchedFiles…
[release_ops] applied 20260515000000 in 142ms
```

Same channel the user already sees Ecto migration output on. The
in-app updater surfaces these via the existing log forwarding; no new
UI surface needed for v1.

### Dev workflow

`mix media_centarr.release_ops` invokes the runner against the dev DB.
Same code path as the release boot, just driven by Mix instead of
`release.ex`. Idempotent; safe to run repeatedly.

The dev-marks-done trap **structurally cannot recur** with this design:
release ops live in `priv/release_ops/`, not `priv/repo/migrations/`,
and Ecto's migrator never touches the `release_ops` table. A dev
`mix ecto.migrate` doesn't know release ops exist.

### Boundaries

- `MediaCentarr.ReleaseOps` lives at the app's top level.
  `use Boundary, deps: [Ecto.Migrator, MediaCentarr.Repo]`.
- Each op module declares its own boundary deps (`MediaCentarr.Library`,
  `MediaCentarr.Acquisition`, etc.). Ops are explicit about which
  contexts they touch — same modularity discipline as the rest of the
  codebase.

## Existing migration (the WatchedFile fix)

`priv/repo/migrations/20260515000000_repoint_collection_child_watched_files.exs`
stays where it is. It already ran on the user's prod DB; rewriting it
as a release op now would force a second run that hits zero rows on
their DB but might do work on other users' DBs that don't have it
applied yet. Leave it as a one-off and start the release ops mechanism
with the **next** fix.

## Testing

- **Each op is a regular module.** Test it directly with
  `use MediaCentarr.DataCase, async: false`: set up DB state, call
  `MyOp.run()`, assert post-state. No runner involved.
- **Runner has its own tests.** Cover:
  - discovery (correct ordering by timestamp prefix)
  - tracking (rows inserted/updated correctly across all statuses)
  - failure (op transaction rolls back, row marked `:failed`,
    exception propagates so boot halts)
  - idempotency (re-running with an `:applied` row in the table no-ops
    fast)
  - transactional rollback (an op that writes and then returns
    `{:error, _}` leaves zero writes committed)
- **Stub op modules** for runner tests live in
  `test/support/release_ops/` — never under `priv/release_ops/` (would
  be auto-discovered and run on real boots).

## Anti-goals (re-stated as warnings)

- Don't allow ops to start their own transactions. The runner owns the
  transaction.
- Don't allow ops to be marked `:applied` without `run/0` having
  returned `:ok`. The bookkeeping must reflect reality.
- Don't allow concurrent op execution. Sequential ordering is the
  invariant.
- Don't share the `schema_migrations` table. The trap that motivated
  this whole effort is "same table, different intent."

## Open questions

None at design time. Implementation plan will address:

- Exact SQL for the `release_ops` table (column types, indexes — likely
  none needed beyond the primary key on `name`).
- Exact discovery mechanism (`File.ls!/1` on `priv/release_ops/`, parse
  filenames, `Code.require_file/1` each, then enumerate via
  `MediaCentarr.ReleaseOp` behaviour callback registration). Mirrors
  Ecto's `Migrator` closely.
- How the in-app updater surfaces a halted boot due to release-op
  failure (probably: existing systemd-failed-service behavior is
  sufficient for v1; the next-update attempt picks up the failed row
  and retries).
