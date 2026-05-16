# Library Schema v2 — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Invoke `automated-testing`, `ecto`, `otp-thinking`, and `coding-guidelines` skills before touching code.

**Goal:** Reify `MediaCentarr.Library.PlayableItem` as the canonical leaf — the thing the user presses Play on. Collapse the 3–5-FK polymorphic fanout on `WatchedFile`, `WatchProgress`, `Image`, `Extra`, `ExternalId` into either a single FK to PlayableItem (`WatchedFile`, `WatchProgress`) or a `(owner_type, owner_id)` discriminator (`Image`, `Extra`, `ExternalId`). Drop `content_url` from leaves. Eliminate `EntityShape.normalize/3` (PlayableItem IS the normalised shape).

**Architecture:** Pillar-1 structural redesign. The campaign target schema (`campaigns/library-schema-v2.md` "Target schema" section) is the spec. After Phase 2, every supporting table either keys to `playable_item_id` (file/progress/subtitle) or uses a single `(owner_type, owner_id)` polymorphic pair (image/extra/external_id). One container can host N playable items (unlocks director's cuts, multi-part episodes).

**Tech stack:** Phoenix 1.7+, Ecto 3.12+, SQLite via ecto_sqlite3. **No backwards compatibility required** — destructive migrations are free.

**Campaign reference:** [`campaigns/library-schema-v2.md`](../../../campaigns/library-schema-v2.md). Phase 1 complete; this plan executes Phase 2.

---

## Pre-flight

- [ ] Read campaign "Target schema" section so the end state is clear.
- [ ] Confirm `mix precommit` is green on main before starting.
- [ ] `jj new` off main for the campaign branch. Each task in this plan describes work that becomes one (possibly amended via `jj squash`) commit.
- [ ] Run `iex -S mix` once to sanity-check Phase 1 state (no `tmdb_id` on schemas, `Subtitles.Track` is a real schema, etc.).

## Phase 2 sub-task graph

```
A (PlayableItem schema + first writer)
  ├── B (Refit WatchedFile to playable_item_id)
  ├── C (Refit WatchProgress to playable_item_id)
  └── G (Inbound creates PlayableItems for all kinds)

D (Image polymorphic owner discriminator)        — independent of A
E (Extra polymorphic owner discriminator)        — independent of A
F (ExternalId polymorphic owner discriminator)   — independent of A

H (TypeResolver, EntityShape.normalize/3 delete, EntityCascade rewrite)
  — depends on A, B, C, G

I (Drop content_url from Movie/Episode/VideoObject)
  — depends on B (WatchedFile is sole file source)

J (Drop legacy library_entity_id columns; convert UI/release_tracking callers)
  — depends on A, G
```

**Execution order:** A → B → C → G → H → I → D → E → F → J. Polymorphic discriminator transforms (D, E, F) are deferred to late in the phase because they're independent of the PlayableItem work and each touches a single supporting schema. Doing them last keeps the main PlayableItem migration sequence linear.

---

## File Structure

| Sub-task | Creates | Modifies |
|----------|---------|----------|
| A | `lib/media_centarr/library/playable_item.ex`, `priv/repo/migrations/<ts>_create_playable_items.exs`, `test/media_centarr/library/playable_item_test.exs` | `lib/media_centarr/library.ex` (CRUD + boundary export); `lib/media_centarr/library/movie.ex`/`episode.ex`/`video_object.ex` (has_many) |
| B | `priv/repo/migrations/<ts>_refit_watched_file_to_playable_item.exs` | `lib/media_centarr/library/watched_file.ex` (drop 4 FKs, add 1; delete `owner_id/1`); every caller of `WatchedFile.owner_id/1`; backfill writes in `Library.Inbound` |
| C | `priv/repo/migrations/<ts>_refit_watch_progress_to_playable_item.exs` | `lib/media_centarr/library/watch_progress.ex` (drop 3 FKs, add 1, unique); `Library.WatchProgress.create_changeset/1` API; every caller of `wp.movie_id`/`wp.episode_id`/`wp.video_object_id` |
| D | `priv/repo/migrations/<ts>_image_polymorphic_owner.exs` | `lib/media_centarr/library/image.ex` (drop 5 FKs, add `(owner_type, owner_id)`); image-readers/writers; unique index on `(owner_type, owner_id, role)` |
| E | `priv/repo/migrations/<ts>_extra_polymorphic_owner.exs` | `lib/media_centarr/library/extra.ex` (drop multi FKs, add `(owner_type, owner_id)`); Extra writers/readers |
| F | `priv/repo/migrations/<ts>_external_id_polymorphic_owner.exs` | `lib/media_centarr/library/external_id.ex` (drop 4 FKs, add `(owner_type, owner_id)`); `Library.ExternalIds.put/3` + `get/2` + `find_owner/2` + `Library.find_*_by_tmdb_id/1`; unique-constraint declarations match new index |
| G | — | `lib/media_centarr/library/inbound.ex` (movie/episode/video_object/series-child ingest creates PlayableItem rows); `lib/media_centarr/library/file_event_handler.ex` (cascade uses PlayableItem) |
| H | — | `lib/media_centarr/library/type_resolver.ex` (resolve by PlayableItem id); `lib/media_centarr/library/entity_shape.ex` (delete `normalize/3` + module if empty); `lib/media_centarr/library/entity_cascade.ex` (rewrite cascade order: playable_items → supporting → containers); every consumer of `EntityShape.normalize/3` |
| I | `priv/repo/migrations/<ts>_drop_content_url_from_leaves.exs` | `lib/media_centarr/library/movie.ex`/`episode.ex`/`video_object.ex` (drop `content_url`); LiveView playback handlers and `Playback.*` consumers read `WatchedFile.file_path` |
| J | `priv/repo/migrations/<ts>_drop_legacy_library_entity_id_columns.exs` | `lib/media_centarr/release_tracking.ex` (column rename: `library_entity_id` → `playable_item_id`); `lib/media_centarr_web/components/upcoming_cards.ex`; `lib/media_centarr_web/live/upcoming_live.ex` |

---

## Task A — `PlayableItem` schema + first writer

The foundation. Other tasks reference `playable_item_id` so this must land first.

**Files:**
- Create `lib/media_centarr/library/playable_item.ex`
- Create `priv/repo/migrations/<ts>_create_playable_items.exs`
- Create `test/media_centarr/library/playable_item_test.exs`
- Modify `lib/media_centarr/library.ex` (CRUD + boundary export)
- Modify `lib/media_centarr/library/movie.ex`, `episode.ex`, `video_object.ex` (`has_many :playable_items`)

### Steps

- [ ] **A.1 Write failing test** in `test/media_centarr/library/playable_item_test.exs`:

```elixir
defmodule MediaCentarr.Library.PlayableItemTest do
  use MediaCentarr.DataCase, async: true

  alias MediaCentarr.Library.{Movie, PlayableItem}
  alias MediaCentarr.TestFactory

  describe "create_changeset/1" do
    test "round-trips a movie playable item" do
      movie = TestFactory.create_standalone_movie()

      {:ok, item} =
        %{
          container_type: :movie,
          container_id: movie.id,
          position: 1,
          duration_seconds: 7200,
          name: nil
        }
        |> PlayableItem.create_changeset()
        |> MediaCentarr.Repo.insert()

      assert item.container_type == :movie
      assert item.container_id == movie.id
      assert item.position == 1
      assert item.duration_seconds == 7200
    end

    test "validates container_type is in enum" do
      changeset =
        PlayableItem.create_changeset(%{
          container_type: :bogus,
          container_id: Ecto.UUID.generate(),
          position: 1
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).container_type
    end
  end
end
```

- [ ] **A.2 Run test — verify it fails** with undefined module.

- [ ] **A.3 Generate migration**:

```bash
mix ecto.gen.migration create_playable_items
```

Migration shape:

```elixir
defmodule MediaCentarr.Repo.Migrations.CreatePlayableItems do
  use Ecto.Migration

  def change do
    create table(:library_playable_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :container_type, :string, null: false
      add :container_id, :binary_id, null: false
      add :position, :integer
      add :duration_seconds, :integer
      add :name, :string
      timestamps()
    end

    create index(:library_playable_items, [:container_type, :container_id])
  end
end
```

Note container_type/container_id uses a discriminator pair (campaign decision 2026-05-15). No FK enforcement at DB level — app-level integrity at the write seam.

- [ ] **A.4 Run migration on both DBs**:

```bash
mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
```

- [ ] **A.5 Implement `Library.PlayableItem`**:

```elixir
defmodule MediaCentarr.Library.PlayableItem do
  @moduledoc """
  The user-visible playable leaf — the thing pressed Play on. One container
  (Movie / Episode / VideoObject) can host multiple PlayableItems for
  director's cuts, multi-part episodes, etc.

  Container is identified by `(container_type, container_id)` discriminator
  pair — see campaign decision 2026-05-15 for why discriminator rather
  than per-type FKs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @type container_type :: :movie | :episode | :video_object

  schema "library_playable_items" do
    field :container_type, Ecto.Enum, values: [:movie, :episode, :video_object]
    field :container_id, Ecto.UUID
    field :position, :integer
    field :duration_seconds, :integer
    field :name, :string

    timestamps()
  end

  @doc "Builds the canonical insert/update changeset."
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:container_type, :container_id, :position, :duration_seconds, :name])
    |> validate_required([:container_type, :container_id])
  end
end
```

- [ ] **A.6 Add `Library` CRUD + boundary export**:

```elixir
# in lib/media_centarr/library.ex — add to exports if Boundary is in use
# and add helpers:

def create_playable_item(attrs) do
  attrs
  |> PlayableItem.create_changeset()
  |> Repo.insert()
end

def fetch_playable_item(id) do
  case Repo.get(PlayableItem, id) do
    nil -> {:error, :not_found}
    item -> {:ok, item}
  end
end

def list_playable_items_for(container_type, container_id) do
  from(p in PlayableItem,
    where: p.container_type == ^container_type and p.container_id == ^container_id,
    order_by: [asc: p.position]
  )
  |> Repo.all()
end
```

- [ ] **A.7 Add `has_many :playable_items` associations** on `Movie`, `Episode`, `VideoObject`:

```elixir
# Movie schema:
has_many :playable_items, MediaCentarr.Library.PlayableItem,
  foreign_key: :container_id,
  where: [container_type: :movie]

# Episode schema:
has_many :playable_items, MediaCentarr.Library.PlayableItem,
  foreign_key: :container_id,
  where: [container_type: :episode]

# VideoObject schema:
has_many :playable_items, MediaCentarr.Library.PlayableItem,
  foreign_key: :container_id,
  where: [container_type: :video_object]
```

The `where: [container_type: ...]` filter is Ecto's polymorphic-association idiom. Test it actually preloads correctly in a follow-up assertion.

- [ ] **A.8 Update test factory** to add `create_playable_item/1` and `create_playable_item_for_movie/1`.

- [ ] **A.9 Run tests** — `mix test test/media_centarr/library/playable_item_test.exs`. Expected: green.

- [ ] **A.10 `mix precommit`** — must pass cleanly. Zero warnings.

- [ ] **A.11 Commit**:

```bash
jj describe -m "feat(library): introduce PlayableItem as the canonical leaf"
```

---

## Task B — Refit `WatchedFile` to `playable_item_id`

Drop the 4 FK columns (`movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id`) and `owner_id/1` coalescer. Add `playable_item_id`. Backfill existing WatchedFile rows by computing the right PlayableItem (one-per-leaf during migration; ingest will create more later in Task G).

**Migration shape:**

```elixir
def up do
  alter table(:library_watched_files) do
    add :playable_item_id, references(:library_playable_items, type: :binary_id, on_delete: :delete_all)
  end

  # Backfill: for each WatchedFile, look up its leaf container and create
  # a PlayableItem if one doesn't exist; link the WatchedFile.
  execute &backfill_playable_items_from_watched_files/0

  # Now safe to drop old FKs
  alter table(:library_watched_files) do
    remove :movie_id
    remove :tv_series_id
    remove :movie_series_id
    remove :video_object_id
  end

  create index(:library_watched_files, [:playable_item_id])
end
```

The backfill function must:
1. For each row with `movie_id` set: ensure a PlayableItem exists with `container_type: :movie, container_id: movie_id, position: 1`. Use INSERT ... ON CONFLICT DO NOTHING semantics on a unique `(container_type, container_id, position)` index (added in Task A migration as a future-friendly index — add it now if it wasn't there).
2. For each row with `tv_series_id` set: this WatchedFile is for an episode. Need to identify which Episode by joining through Season → TVSeries → file_path matching. This is the trickiest backfill.
3. For each row with `movie_series_id` set: same complexity as `tv_series_id` (need to identify which child Movie).
4. For each row with `video_object_id` set: create PlayableItem of type `:video_object`.

**The TV/movie-series backfill is non-trivial.** Read existing data carefully — if the existing tables store the relationship `WatchedFile → (TVSeries → Season → Episode) by file_path match`, the backfill needs to find the Episode by joining `library_episodes.content_url == wf.file_path`. Use the existing `EpisodeList.find_episode_by_path/2` or similar context function if it exists, else write a one-shot helper inside the migration.

**Risk:** If a WatchedFile in dev/showcase points at a path that no longer maps to any Episode (orphan), the backfill creates a PlayableItem of type `:movie` for the TVSeries id — clearly wrong. Either skip such rows (delete the orphan WatchedFile) or fail the migration loudly. Use judgment per actual data shape; the campaign says destructive migrations are OK so deleting orphans is fine.

After this task, `WatchedFile` schema is:

```elixir
schema "library_watched_files" do
  field :file_path, :string
  field :watch_dir, :string
  belongs_to :playable_item, MediaCentarr.Library.PlayableItem
  timestamps()
end
```

And `WatchedFile.owner_id/1` is **deleted**.

Detailed TDD steps follow the Task A pattern: write failing test, generate migration, run, update schema, update consumers, run precommit, commit.

Commit message: `refactor(library): refit WatchedFile to single playable_item_id`

---

## Task C — Refit `WatchProgress` to `playable_item_id`

Mirror of Task B for `library_watch_progress`. Drop `movie_id`, `episode_id`, `video_object_id`. Add `playable_item_id`, unique-indexed (one progress row per playable item).

The doc `(season=0, episode=0)` overload disappears — it was a hack for the standalone-movie case under the old schema. Now: standalone movie has one PlayableItem; episode has one PlayableItem; movie-series-child has one PlayableItem; each has its own WatchProgress row.

**Migration shape:** add `playable_item_id`, backfill from existing FK columns by joining to PlayableItem via `(container_type, container_id)` = (`:movie`, movie_id) etc., drop old columns, add unique index.

Commit message: `refactor(library): refit WatchProgress to single playable_item_id`

---

## Task G — `Library.Inbound` creates `PlayableItem` rows

After Tasks A/B/C, the schema accommodates PlayableItem but ingest still treats containers as the unit. Rewire Inbound:

- Movie ingest (standalone): create Movie + PlayableItem(`:movie`, movie.id, position: 1).
- Episode ingest: create Episode + PlayableItem(`:episode`, episode.id, position: episode.episode_number).
- Video-object ingest: create VideoObject + PlayableItem(`:video_object`, vo.id, position: 1).
- Movie-series-child ingest: create Movie (with `movie_series_id` set) + PlayableItem(`:movie`, movie.id, position: position-in-series).

The Inbound `link_file/2` flow becomes: resolve container → ensure PlayableItem → create WatchedFile keyed to `playable_item_id` → persist subtitle tracks.

Race-loss recovery: PlayableItem creation can fail on `(container_type, container_id, position)` uniqueness (if you added that constraint in A — recommended for write-side idempotency). Handle similarly to ExternalId race-loss in Phase 1 Task 6.

Commit message: `refactor(library): Inbound writes PlayableItem rows for every leaf ingest`

---

## Task H — Resolver / EntityShape / Cascade

Three coordinated rewrites:

**`TypeResolver`** — today resolves a UUID to a container by trying 4 tables in order. Rewrite to resolve a UUID through `PlayableItem`: lookup by id, follow `(container_type, container_id)` to the container. Add a separate `resolve_container/1` for the rarer case of starting from a container UUID.

**`EntityShape.normalize/3`** — delete. PlayableItem IS the normalised shape (it carries `name`, `duration_seconds`, `position`, container info). Update every consumer to read from PlayableItem + preloaded container.

**`EntityCascade.destroy!/1`** — rewrite cascade order:
```
playable_items (for the container)
  → watched_files (delete by playable_item_id)
  → watch_progress (delete by playable_item_id)
  → subtitle_tracks (delete by watched_file_id; subtitles_tracks.watched_file_id has on_delete: :delete_all)
  → images (delete by owner_id / owner_type — Task D)
  → extras (delete by owner_id / owner_type — Task E)
  → external_ids (delete by owner_id / owner_type — Task F)
  → playable_items (delete the PlayableItem rows themselves)
  → container (delete the Movie/TVSeries/MovieSeries/VideoObject)
```

If Tasks D/E/F haven't landed yet at this point in the sequence, the cascade still works against the per-FK polymorphism — write the cascade in a way that's resilient to either shape, OR commit this task AFTER D/E/F.

**Order suggestion:** swap H and D/E/F in the sequence — do D/E/F before H. Updated order: A → B → C → G → D → E → F → H → I → J.

Commit message: `refactor(library): TypeResolver/EntityShape/EntityCascade — pivot on PlayableItem`

---

## Task I — Drop `content_url` from leaves

After Task B, `WatchedFile.file_path` is the sole source of truth for the path on disk. Drop `content_url` from `Movie`, `Episode`, `VideoObject`. Update every consumer (Playback handlers, LiveView "Play" buttons) to read via WatchedFile.

Today's flow: detail panel "Play" button uses `entity.content_url`. After: `playable_item |> Library.list_watched_files_for_playable_item/1 |> List.first() |> Map.get(:file_path)`. Cleaner: a `Library.playable_file_path/1` helper that returns the present-on-disk file path (or nil if all WatchedFiles are absent).

Commit message: `refactor(library): drop content_url from leaves — WatchedFile is sole file source`

---

## Task D — Image polymorphic owner discriminator

Drop `movie_id`, `episode_id`, `tv_series_id`, `movie_series_id`, `video_object_id` from `library_images`. Add `owner_type :string` + `owner_id :binary_id`. Owner types: `:movie | :tv_series | :movie_series | :video_object | :episode | :playable_item` (per campaign target).

Unique index `(owner_type, owner_id, role)` enforces "one image per role per owner."

Backfill from existing FKs: each Image row migrates to `(owner_type, owner_id)` based on which FK is set.

After: `Library.Image.create_changeset/1` takes `owner_type` + `owner_id` instead of N nullable FKs.

Helpers to update: every reader that did `image.movie_id`/`image.episode_id`/etc. Centralise into a `Library.Images.put/4` and `Library.Images.list_for/2` if not already.

Commit message: `refactor(library): Image uses (owner_type, owner_id) discriminator`

---

## Task E — Extra polymorphic owner discriminator

Mirror of Task D for `library_extras`. Owner types: `:movie | :tv_series | :movie_series | :season`.

Commit message: `refactor(library): Extra uses (owner_type, owner_id) discriminator`

---

## Task F — ExternalId polymorphic owner discriminator

Mirror of Task D for `library_external_ids`. Owner types: `:movie | :tv_series | :movie_series | :video_object`.

Replace the four partial unique indexes from Phase 1 Task 6 with one: `unique_index(:library_external_ids, [:source, :external_id, :owner_type])`. **Note:** TMDB Movie #12345 and TMDB TVSeries #12345 are legitimately different — the `owner_type` column completes the uniqueness tuple.

Update `Library.ExternalIds.put/3`, `get/2`, `find_owner/2` to use the discriminator. Simplify `Library.find_movie_by_tmdb_id/1` and friends (they get cleaner — no per-type partial-index reasoning required).

Update `ExternalId.create_changeset/1` `unique_constraint` to the new single name.

Commit message: `refactor(library): ExternalId uses (owner_type, owner_id) discriminator`

---

## Task J — Drop legacy `library_entity_id` columns

`release_tracking_items.library_entity_id` and similar legacy columns are documented in `docs/library.md` as "legacy-named columns, correct values" — UUIDs pointing at type-specific tables but never enforced as FKs.

After Phase 2, the UUIDs they hold should point at PlayableItem (the canonical UUID for "a playable thing"). Rename the column AND rewire the consumers.

**Files touched:**
- Migration that renames the column AND backfills the values to point at PlayableItem (lookup by `(container_type, container_id) = (release.media_type, release.library_entity_id)` → fetch PlayableItem).
- `lib/media_centarr/release_tracking.ex` — column rename, helper rename (`find_last_library_episode` → `find_last_episode_playable_item` or similar)
- `lib/media_centarr_web/components/upcoming_cards.ex` — link generation
- `lib/media_centarr_web/live/upcoming_live.ex` — playable lookup

Commit message: `refactor(release_tracking): library_entity_id → playable_item_id`

---

## Workflow per task

Each task above gets a fresh subagent dispatch following the Phase 1 pattern:
1. Implementer subagent (general-purpose) — TDD, run precommit, commit (no `jj new`).
2. Combined spec + quality reviewer subagent (general-purpose) — verify spec compliance, evaluate quality, flag issues by Critical / Important / Minor.
3. If issues, fix subagent — apply specific fixes, `jj squash` into the task's commit.

**Per task budget:** ~30 minutes from dispatch to completion based on Phase 1 averages. Phase 2 has 10 tasks (A through J), so ~5 hours of subagent time.

## Pre-existing flake awareness

Phase 1 surfaced these — they re-run cleanly. Re-run if observed during Phase 2; only block on NEW failures:
- `AcquisitionLivePursuitModalTest` — DBConnection.OwnershipError on cleanup
- `PageSmokeTest /history` — mount budget threshold
- `ErrorReports.BucketsTest` — PubSub-ordering cross-test leak
- `Watcher.FilePresence` — sandbox-owner race
- `ConsoleLiveTest` — PubSub-ordering, observed once

## Conventions

- **Jujutsu:** always `-m` flags. The `jj` skill memory rule covers this.
- **No real show titles in code:** placeholders only (`Sample Show`, `Movie A`, `Sample.Show.S01E01.1080p.WEB-DL.mkv`).
- **`# Follow-up:` not `# TODO:`:** Credo strict rejects TODO tags.
- **Quality bar:** extract reusable units as part of the change; collapse third-use-case patterns; don't take the quickest path that skips structure.
- **No raw SQL inspection of state:** use context functions. DDL on indexes during migration backfills is fine.
- **Architectural fixes, not symptom covers:** if a backfill is hard because the old data shape is ambiguous, fix the data shape (delete orphans) rather than working around it in app code.

## Completion criteria

- `Library.PlayableItem` exists and is the canonical leaf.
- `WatchedFile`, `WatchProgress` carry single `playable_item_id` FK.
- `Image`, `Extra`, `ExternalId` use `(owner_type, owner_id)` discriminators with corresponding unique indexes.
- `WatchedFile.owner_id/1` deleted.
- `EntityShape.normalize/3` deleted; consumers re-targeted to PlayableItem.
- `content_url` removed from `Movie`, `Episode`, `VideoObject`.
- `library_entity_id` columns renamed to `playable_item_id` with values backfilled to PlayableItem UUIDs.
- `Library.Inbound` writes PlayableItem rows for every leaf ingest.
- `Library.EntityCascade` rewritten with new ordering.
- `mix precommit` green at every commit boundary. All baselines stable.
- ADR drafted documenting PlayableItem reification (alongside ADR-029 data-decoupling).
- Campaign file updated: Phase 2 marked complete; Phase 3 follow-ups listed.

## Post-Phase 2

- Phase 3 plan written JIT against the new Phase 2 state.
- Wiki: update `docs/library.md` to reflect the new shape (PlayableItem section, drop the polymorphic-fanout discussion, update Module Reference table).
- `decisions/architecture/2026-MM-DD-NNN-playable-item-reification.md` written.
- Showcase DB binary updated with new structure.

## Self-Review Checklist

- Every task ends with a clear commit message.
- File-structure table at top names creates vs modifies per task.
- TDD code in Task A is concrete and complete; subsequent tasks may abbreviate to "follow Task A pattern" + the task-specific changes.
- No "TBD"/placeholder text.
- Sub-task dependency graph at the top reflects the actual execution order.
- Migration risk hot-spots flagged (Task B's TV-series/movie-series backfill).
- Backwards-compat-free posture is consistent (destructive migrations, deleted helpers, no transition tolerance).
