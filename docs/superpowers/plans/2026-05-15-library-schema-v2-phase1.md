# Library Schema v2 — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Always invoke `automated-testing`, `ecto`, and `coding-guidelines` skills before touching code.

**Goal:** Apply low-risk foundation cleanups to the Library schema — typed fields, embedded cast/crew, MovieSeries metadata symmetry, subtitle-track extraction, and ExternalId-as-sole-source-of-truth — without changing the polymorphic structure. Phase 2 (`PlayableItem` reification) builds on this base.

**Architecture:** Pillar-1 schema work. Each task is a self-contained migration + schema + changeset + caller-update + commit. No projection changes (Pillar 2) and no PubSub topology changes (Pillar 3) — those land in later phases.

**Tech Stack:** Phoenix 1.7+, Ecto 3.12+, SQLite via ecto_sqlite3, ExMachina-style factories in `MediaCentarr.TestFactory`.

**Campaign reference:** [`campaigns/library-schema-v2.md`](../../../campaigns/library-schema-v2.md).

---

## Pre-flight

- [ ] Read [`campaigns/library-schema-v2.md`](../../../campaigns/library-schema-v2.md) start-to-finish.
- [ ] Confirm `mix precommit` is green on `main` before starting.
- [ ] `jj new` off `main` for the campaign branch.
- [ ] Skim [`docs/library.md`](../../library.md) — current shape to mutate.

## File Structure

Files this plan creates or modifies, by task. Keep responsibilities narrow.

| Task | Creates | Modifies |
|------|---------|----------|
| 1 | `lib/media_centarr/library/person.ex` | `lib/media_centarr/library/movie.ex`, `tv_series.ex`, `movie_series.ex`; `lib/media_centarr/library/inbound.ex`; `test/support/factory.ex`; cast-strip templates under `lib/media_centarr_web/components/library_detail/` |
| 2 | `priv/repo/migrations/<ts>_typed_date_published.exs` | Each container schema's `date_published` field; `lib/media_centarr_web/components/library_card/` (year display); `lib/media_centarr/format.ex` if a date helper is added |
| 3 | `priv/repo/migrations/<ts>_duration_seconds_integer.exs` | `lib/media_centarr/library/movie.ex`, `episode.ex`; `lib/media_centarr/format.ex` (`format_seconds/1` already exists); `lib/media_centarr/tmdb/mapper.ex` (parse ISO 8601 / minutes string → seconds) |
| 4 | `priv/repo/migrations/<ts>_movie_series_metadata_symmetry.exs` | `lib/media_centarr/library/movie_series.ex` schema + changeset; `lib/media_centarr/library/inbound.ex` `movie_series_attrs/1`; `lib/media_centarr/tmdb/collection_mapper.ex` (or wherever collection metadata is mapped) |
| 5 | `lib/media_centarr/subtitles/track.ex` *(promoted from embedded struct to schema)*; `priv/repo/migrations/<ts>_subtitle_tracks_table.exs` | `lib/media_centarr/library/watched_file.ex` (drop `subtitle_tracks` field); `lib/media_centarr/subtitles.ex` (CRUD); `lib/media_centarr/playback.ex` consumers |
| 6 | `lib/media_centarr/library/external_ids.ex` *(helper module — `put/3`, `get/2`)*; `priv/repo/migrations/<ts>_drop_redundant_tmdb_imdb_columns.exs` | Each container schema (drop columns); `lib/media_centarr/library/inbound.ex` (write `ExternalId` rows); `lib/media_centarr/library/type_resolver.ex` (`find_by_tmdb_id/1` reads `ExternalId`) |

---

## Task 1: `Library.Person` embedded schema for cast/crew

Today `cast` and `crew` are `{:array, :map}` on `Movie` and `TVSeries`. No type contract. Templates do `member["name"]` / `member["character"]` directly. We replace with an embedded schema.

**Files:**
- Create: `lib/media_centarr/library/person.ex`
- Create: `test/media_centarr/library/person_test.exs`
- Modify: `lib/media_centarr/library/movie.ex`, `lib/media_centarr/library/tv_series.ex`
- Modify: `lib/media_centarr/library/inbound.ex` (any `cast: cast_list` paths)
- Modify: `test/support/factory.ex`
- Modify: cast-strip + crew-row templates (e.g. `lib/media_centarr_web/components/library_detail/cast_strip.ex`)

### Steps

- [ ] **Step 1: Write the failing test for `Library.Person.cast_changeset/1`**

```elixir
# test/media_centarr/library/person_test.exs
defmodule MediaCentarr.Library.PersonTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.Person

  test "casts a cast member from TMDB-shaped map" do
    attrs = %{
      "name" => "Sample Actor",
      "character" => "Hero",
      "order" => 0,
      "profile_path" => "/abc.jpg"
    }

    assert {:ok, %Person{name: "Sample Actor", character: "Hero", order: 0}} =
             Person.cast_member_changeset(attrs) |> Ecto.Changeset.apply_action(:insert)
  end

  test "casts a crew member with job/department" do
    attrs = %{
      "name" => "Sample Director",
      "job" => "Director",
      "department" => "Directing"
    }

    assert {:ok, %Person{job: "Director", department: "Directing"}} =
             Person.crew_member_changeset(attrs) |> Ecto.Changeset.apply_action(:insert)
  end
end
```

- [ ] **Step 2: Run the test — verify it fails**

```bash
mix test test/media_centarr/library/person_test.exs
```

Expected: `(UndefinedFunctionError) function MediaCentarr.Library.Person.cast_member_changeset/1 is undefined`.

- [ ] **Step 3: Implement `Library.Person`**

```elixir
# lib/media_centarr/library/person.ex
defmodule MediaCentarr.Library.Person do
  @moduledoc """
  Embedded schema for cast and crew members. Two changesets — one per
  role — since cast members have `character`/`order` and crew members
  have `job`/`department`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :character, :string
    field :order, :integer
    field :job, :string
    field :department, :string
    field :profile_path, :string
  end

  def cast_member_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :character, :order, :profile_path])
    |> validate_required([:name])
  end

  def crew_member_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :job, :department, :profile_path])
    |> validate_required([:name])
  end
end
```

- [ ] **Step 4: Run the test — verify it passes**

```bash
mix test test/media_centarr/library/person_test.exs
```

- [ ] **Step 5: Migrate `Movie` to `embeds_many :cast, Person, with: &Person.cast_member_changeset/2`**

```elixir
# lib/media_centarr/library/movie.ex — schema block changes only
- field :cast, {:array, :map}, default: []
- field :crew, {:array, :map}, default: []
+ embeds_many :cast, MediaCentarr.Library.Person, on_replace: :delete
+ embeds_many :crew, MediaCentarr.Library.Person, on_replace: :delete
```

And update the changeset:

```elixir
def create_changeset(attrs) do
  %__MODULE__{}
  |> cast(attrs, [:id, :name, ...])  # NOTE: remove :cast, :crew from the cast/2 list
  |> cast_embed(:cast, with: &MediaCentarr.Library.Person.cast_member_changeset/1)
  |> cast_embed(:crew, with: &MediaCentarr.Library.Person.crew_member_changeset/1)
  |> validate_required([:name])
  |> unique_constraint(:tmdb_id, name: :library_movies_tmdb_id_index)
end
```

Drop `coerce_cast_default/1` and `coerce_crew_default/1` — `embeds_many` defaults to `[]` natively.

- [ ] **Step 6: Repeat for `TVSeries`**

Mechanically identical to step 5 against `lib/media_centarr/library/tv_series.ex`.

- [ ] **Step 7: Update test factory**

In `test/support/factory.ex`, change any `build_cast/0` or `build_crew/0` helpers to return `%Person{}` structs instead of plain maps. Update `build_movie/1` / `build_tv_series/1` accordingly.

- [ ] **Step 8: Update consuming templates**

Any template that does `member["name"]` or `member["character"]` becomes `member.name` / `member.character`. Grep:

```bash
grep -rn '"character"\|"job"\|"department"\|"profile_path"' lib/media_centarr_web/ test/
```

Each hit converts from string-key access to struct field access.

- [ ] **Step 9: Run full test suite**

```bash
mix test
```

Expected: green. If any test fails, the cast/crew was being passed in as `[%{"name" => ...}]` somewhere — `cast_embed` will accept that shape natively, so failures usually mean the *reader* changed and the writer is still producing maps. Trace the failing assertion.

- [ ] **Step 10: Run precommit**

```bash
mix precommit
```

- [ ] **Step 11: Commit**

```bash
jj describe -m "refactor(library): type cast/crew via Library.Person embedded schema"
jj new
```

---

## Task 2: Typed `date_published` (`:string` → `:date`)

Today every container stores `date_published` as `"YYYY-MM-DD"` strings. Filters, sorts, and year-extraction parse on every read. We promote to `:date`.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_typed_date_published.exs`
- Modify: `lib/media_centarr/library/movie.ex`, `tv_series.ex`, `movie_series.ex`, `video_object.ex`
- Modify: `lib/media_centarr/library/inbound.ex` (TMDB date mapping)
- Modify: templates using `entity.date_published` for year display

### Steps

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration typed_date_published
```

- [ ] **Step 2: Write migration**

```elixir
# priv/repo/migrations/<ts>_typed_date_published.exs
defmodule MediaCentarr.Repo.Migrations.TypedDatePublished do
  use Ecto.Migration

  def up do
    # SQLite supports ALTER COLUMN via table rewrite. Ecto's modify
    # generates the right SQL for sqlite3. Date strings already in
    # ISO-8601 (`YYYY-MM-DD`) parse cleanly via SQLite's `date()`.
    for table <- [:library_movies, :library_tv_series, :library_movie_series, :library_video_objects] do
      alter table(table) do
        modify :date_published, :date, from: :string
      end
    end
  end

  def down do
    for table <- [:library_movies, :library_tv_series, :library_movie_series, :library_video_objects] do
      alter table(table) do
        modify :date_published, :string, from: :date
      end
    end
  end
end
```

- [ ] **Step 3: Run migration on dev DB**

```bash
mix ecto.migrate
```

If parsing errors on existing data: drop the DB (`mix ecto.reset`) and rebuild via `mix seed.review` / `mix seed.showcase`. Showcase data is the only real seed; rebuilding it is cheap.

- [ ] **Step 4: Update schemas — `field :date_published, :date`**

Four files, mechanical:

```elixir
- field :date_published, :string
+ field :date_published, :date
```

- [ ] **Step 5: Update `Library.Inbound` TMDB date mapping**

Grep for where TMDB `release_date` / `first_air_date` strings are mapped to `date_published`. Convert via `Date.from_iso8601!/1` (TMDB always returns ISO-8601 or empty string; handle empty string as `nil`).

```elixir
defp parse_date(""), do: nil
defp parse_date(nil), do: nil
defp parse_date(iso) when is_binary(iso), do: Date.from_iso8601!(iso)
```

- [ ] **Step 6: Update display helpers**

Templates that did `String.slice(entity.date_published, 0, 4)` for year now do `entity.date_published && entity.date_published.year`. Add `MediaCentarr.Format.year/1` if used in 3+ places:

```elixir
# lib/media_centarr/format.ex
def year(nil), do: nil
def year(%Date{year: y}), do: y
```

- [ ] **Step 7: Run tests**

```bash
mix test
```

Expected failures: any test asserting on string date format. Update those assertions to use `~D[YYYY-MM-DD]` literals.

- [ ] **Step 8: Run precommit**

```bash
mix precommit
```

- [ ] **Step 9: Commit**

```bash
jj describe -m "refactor(library): type date_published as :date"
jj new
```

---

## Task 3: Typed `duration` (`:string` → `:integer` seconds)

Today `Movie.duration` and `Episode.duration` are `:string`. The actual stored format is ambiguous (sometimes "PT2H30M", sometimes "150", sometimes "150 min"). We canonicalise to integer seconds and rename to `duration_seconds`.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_duration_seconds_integer.exs`
- Modify: `lib/media_centarr/library/movie.ex`, `episode.ex`
- Modify: `lib/media_centarr/tmdb/mapper.ex` (or equivalent — convert minutes → seconds at the boundary)
- Modify: templates using `entity.duration` for display

### Steps

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration duration_seconds_integer
```

- [ ] **Step 2: Write migration with column rename**

```elixir
defmodule MediaCentarr.Repo.Migrations.DurationSecondsInteger do
  use Ecto.Migration

  def up do
    # SQLite: drop column, add typed column. Existing data is
    # rebuildable from TMDB; ALTER+CAST would need a custom parser
    # across ambiguous formats.
    alter table(:library_movies) do
      remove :duration
      add :duration_seconds, :integer
    end

    alter table(:library_episodes) do
      remove :duration
      add :duration_seconds, :integer
    end
  end

  def down do
    alter table(:library_movies) do
      remove :duration_seconds
      add :duration, :string
    end

    alter table(:library_episodes) do
      remove :duration_seconds
      add :duration, :string
    end
  end
end
```

- [ ] **Step 3: Run migration on dev DB**

```bash
mix ecto.migrate
```

Re-seed if needed.

- [ ] **Step 4: Update schemas**

```elixir
# lib/media_centarr/library/movie.ex
- field :duration, :string
+ field :duration_seconds, :integer
```

Same in `episode.ex`. Update `create_changeset/1` and `set_content_url_changeset/2` field lists.

- [ ] **Step 5: Update TMDB mapper to emit seconds**

Find the mapper (likely `lib/media_centarr/tmdb/mapper.ex` or pipeline equivalent). TMDB returns `runtime: 120` (minutes). Map to `duration_seconds: 120 * 60`. For episodes (`runtime: 42`), `duration_seconds: 42 * 60`.

- [ ] **Step 6: Update display call sites**

`MediaCentarr.Format.format_seconds/1` (lib/media_centarr/format.ex:11) already takes seconds — display call sites that previously did string parsing now go through it directly:

```elixir
- entity.duration |> parse_iso_duration() |> format()
+ MediaCentarr.Format.format_seconds(entity.duration_seconds)
```

Grep for `entity.duration\b` (word boundary excludes `duration_seconds`) and convert each call site.

- [ ] **Step 7: Run tests**

```bash
mix test
```

- [ ] **Step 8: Run precommit**

```bash
mix precommit
```

- [ ] **Step 9: Commit**

```bash
jj describe -m "refactor(library): canonicalise duration as integer seconds"
jj new
```

---

## Task 4: `MovieSeries` metadata symmetry with `TVSeries`

`TVSeries` carries `tagline`, `original_language`, `studio`, `country_code`, `status`, `cast`, `crew`, `vote_count`. `MovieSeries` carries none of them. Detail pages for collections can't render the same shape as series pages. Fix by adding the missing fields.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_movie_series_metadata_symmetry.exs`
- Modify: `lib/media_centarr/library/movie_series.ex`
- Modify: `lib/media_centarr/library/inbound.ex` — `movie_series_attrs/1` mapping
- Modify: TMDB collection mapper (find via `grep "tmdb_collection\|collection_id" lib/media_centarr/tmdb/`)

### Steps

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration movie_series_metadata_symmetry
```

- [ ] **Step 2: Write migration**

```elixir
defmodule MediaCentarr.Repo.Migrations.MovieSeriesMetadataSymmetry do
  use Ecto.Migration

  def change do
    alter table(:library_movie_series) do
      add :tagline, :string
      add :original_language, :string
      add :studio, :string
      add :country_code, :string
      add :vote_count, :integer
      add :status, :string  # will become Ecto.Enum at the schema layer
      # cast / crew: stored as :map columns to back embeds_many
      add :cast, :map
      add :crew, :map
    end
  end
end
```

Note SQLite stores `:map` columns as JSON text. `embeds_many` reads/writes through Ecto's JSON serialisation cleanly.

- [ ] **Step 3: Run migration**

```bash
mix ecto.migrate
```

- [ ] **Step 4: Update `Library.MovieSeries` schema**

```elixir
schema "library_movie_series" do
  field :name, :string
  field :description, :string
  field :date_published, :date  # already typed in Task 2
  field :genres, {:array, :string}
  field :url, :string
  field :aggregate_rating_value, :float
  field :vote_count, :integer
  field :tagline, :string
  field :original_language, :string
  field :studio, :string
  field :country_code, :string
  field :status, Ecto.Enum, values: [:released, :ongoing, :ended]

  embeds_many :cast, MediaCentarr.Library.Person, on_replace: :delete
  embeds_many :crew, MediaCentarr.Library.Person, on_replace: :delete

  # ... existing has_many associations unchanged
  timestamps()
end
```

Update changesets — add new fields to the `cast/2` list, add `cast_embed/2` calls.

- [ ] **Step 5: Update `Library.Inbound` MovieSeries mapping**

The TMDB collection endpoint returns less metadata than a movie endpoint — fill what TMDB provides, leave the rest `nil`. Cast/crew on collections are aggregated from member films; for now write empty lists and revisit if a UI need arises.

- [ ] **Step 6: Run tests**

```bash
mix test
```

- [ ] **Step 7: Run precommit**

```bash
mix precommit
```

- [ ] **Step 8: Commit**

```bash
jj describe -m "feat(library): MovieSeries metadata symmetry with TVSeries"
jj new
```

---

## Task 5: Extract `subtitle_tracks` from `WatchedFile` into its own table

`WatchedFile.subtitle_tracks` is `{:array, :map}` storing `Subtitles.Track`-shaped data. The Subtitles context owns the conversion. Cross-context data in another context's column is the smell — move to its own table inside `Subtitles`.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_subtitle_tracks_table.exs`
- Modify: `lib/media_centarr/subtitles/track.ex` — promote from plain struct to Ecto schema
- Modify: `lib/media_centarr/subtitles.ex` — CRUD functions
- Modify: `lib/media_centarr/library/watched_file.ex` — drop `subtitle_tracks` field
- Modify: every consumer of `watched_file.subtitle_tracks` (grep finds them — Playback, UI selectors)

### Steps

- [ ] **Step 1: Write failing test in `Subtitles`**

```elixir
# test/media_centarr/subtitles_test.exs
test "list_tracks_for_file/1 returns tracks linked to a WatchedFile" do
  watched_file = insert(:watched_file)

  {:ok, track} =
    Subtitles.create_track(%{
      watched_file_id: watched_file.id,
      kind: :embedded,
      language: "en",
      source: "stream:1"
    })

  assert Subtitles.list_tracks_for_file(watched_file.id) == [track]
end
```

- [ ] **Step 2: Generate migration**

```bash
mix ecto.gen.migration subtitle_tracks_table
```

- [ ] **Step 3: Write migration**

```elixir
defmodule MediaCentarr.Repo.Migrations.SubtitleTracksTable do
  use Ecto.Migration

  def change do
    create table(:subtitles_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :watched_file_id, references(:library_watched_files, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false  # :embedded | :sidecar
      add :language, :string
      add :source, :string, null: false
      timestamps()
    end

    create index(:subtitles_tracks, [:watched_file_id])

    alter table(:library_watched_files) do
      remove :subtitle_tracks
    end
  end
end
```

- [ ] **Step 4: Promote `Subtitles.Track` to an Ecto schema**

```elixir
# lib/media_centarr/subtitles/track.ex
defmodule MediaCentarr.Subtitles.Track do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "subtitles_tracks" do
    field :kind, Ecto.Enum, values: [:embedded, :sidecar]
    field :language, :string
    field :source, :string

    belongs_to :watched_file, MediaCentarr.Library.WatchedFile

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:watched_file_id, :kind, :language, :source])
    |> validate_required([:watched_file_id, :kind, :source])
  end
end
```

The old `to_map`/`from_map` helpers delete — the map round-trip is gone.

- [ ] **Step 5: Add `Subtitles` CRUD**

```elixir
# lib/media_centarr/subtitles.ex
def create_track(attrs) do
  attrs
  |> Track.create_changeset()
  |> Repo.insert()
end

def list_tracks_for_file(watched_file_id) do
  from(t in Track, where: t.watched_file_id == ^watched_file_id)
  |> Repo.all()
end

def replace_tracks_for_file(watched_file_id, tracks) do
  Repo.transaction(fn ->
    Repo.delete_all(from t in Track, where: t.watched_file_id == ^watched_file_id)
    Enum.map(tracks, fn attrs ->
      attrs
      |> Map.put(:watched_file_id, watched_file_id)
      |> create_track()
    end)
  end)
end
```

- [ ] **Step 6: Drop `subtitle_tracks` field from `Library.WatchedFile`**

```elixir
# lib/media_centarr/library/watched_file.ex
# Remove the field declaration and the moduledoc comment about subtitle_tracks.
# Add: has_many :subtitle_tracks, MediaCentarr.Subtitles.Track, foreign_key: :watched_file_id
```

Update `link_file_changeset/1` and `/2` to drop `:subtitle_tracks` from the cast list.

- [ ] **Step 7: Migrate every reader from `wf.subtitle_tracks` (list of maps) to `Subtitles.list_tracks_for_file(wf.id)`**

```bash
grep -rn 'subtitle_tracks' lib/ test/ --exclude-dir=deps
```

Each hit converts. Playback selectors likely use `language` filtering — same shape, struct access instead of map access.

- [ ] **Step 8: Migrate every writer from "put list of maps on WatchedFile" to `Subtitles.replace_tracks_for_file/2`**

The pipeline detector (`Subtitles.Detector` or similar) produces tracks. Pipeline → Library → write replaces the inline `:subtitle_tracks` attr with a follow-up `Subtitles.replace_tracks_for_file/2` call after the WatchedFile is created.

- [ ] **Step 9: Run tests**

```bash
mix test
```

- [ ] **Step 10: Run precommit**

```bash
mix precommit
```

- [ ] **Step 11: Commit**

```bash
jj describe -m "refactor(subtitles): own subtitle_tracks table; drop WatchedFile.subtitle_tracks"
jj new
```

---

## Task 6: Drop redundant `tmdb_id` / `imdb_id` columns; `ExternalId` is sole source

Today: `Movie.tmdb_id`, `Movie.imdb_id`, etc. exist as columns *and* `ExternalId` rows exist with `source: "tmdb"` / `"imdb"`. Two sources of truth, both updated by `Inbound`. Drop the columns.

**Files:**
- Create: `lib/media_centarr/library/external_ids.ex` — helper for canonical reads/writes
- Create: `priv/repo/migrations/<timestamp>_drop_redundant_tmdb_imdb_columns.exs`
- Modify: `lib/media_centarr/library/movie.ex`, `tv_series.ex`, `movie_series.ex`, `video_object.ex`
- Modify: `lib/media_centarr/library/inbound.ex` — write only via `ExternalIds.put/3`
- Modify: `lib/media_centarr/library/type_resolver.ex` — `find_by_tmdb_id/1`
- Modify: every call site of `record.tmdb_id` / `record.imdb_id`

### Steps

- [ ] **Step 1: Write failing test for `ExternalIds.put/3` and `get/2`**

```elixir
# test/media_centarr/library/external_ids_test.exs
defmodule MediaCentarr.Library.ExternalIdsTest do
  use MediaCentarr.DataCase, async: true

  alias MediaCentarr.Library.ExternalIds
  alias MediaCentarr.TestFactory

  test "put/3 inserts a new ExternalId row" do
    movie = TestFactory.create_movie()
    assert {:ok, row} = ExternalIds.put(:tmdb, movie, "12345")
    assert row.source == "tmdb"
    assert row.external_id == "12345"
    assert row.movie_id == movie.id
  end

  test "get/2 fetches by source from a loaded record" do
    movie = TestFactory.create_movie()
    {:ok, _} = ExternalIds.put(:tmdb, movie, "12345")
    movie = MediaCentarr.Repo.preload(movie, :external_ids)
    assert ExternalIds.get(movie, :tmdb) == "12345"
  end
end
```

- [ ] **Step 2: Implement `ExternalIds`**

```elixir
# lib/media_centarr/library/external_ids.ex
defmodule MediaCentarr.Library.ExternalIds do
  @moduledoc """
  Canonical accessors for external identifiers across containers.

  Reads always go through a preloaded `:external_ids` association.
  Writes always go through `put/3` — never inline on the container
  changeset.
  """

  alias MediaCentarr.Library.ExternalId
  alias MediaCentarr.Repo

  @sources ~w(tmdb imdb tvdb tmdb_collection)a

  def put(source, container, external_id) when source in @sources do
    attrs =
      %{source: Atom.to_string(source), external_id: external_id}
      |> Map.put(owner_fk(container), container.id)

    attrs
    |> ExternalId.create_changeset()
    |> Repo.insert(on_conflict: :nothing)
  end

  def get(%{external_ids: ids}, source) when source in @sources do
    source_str = Atom.to_string(source)
    Enum.find_value(ids, fn %{source: s, external_id: v} -> s == source_str && v end)
  end

  defp owner_fk(%MediaCentarr.Library.Movie{}), do: :movie_id
  defp owner_fk(%MediaCentarr.Library.TVSeries{}), do: :tv_series_id
  defp owner_fk(%MediaCentarr.Library.MovieSeries{}), do: :movie_series_id
  defp owner_fk(%MediaCentarr.Library.VideoObject{}), do: :video_object_id
end
```

(In Phase 2, `owner_fk/1` collapses to `{:owner_type, type_atom}` + `:owner_id`. Phase 1 keeps the per-type FKs.)

- [ ] **Step 3: Run tests — verify pass**

```bash
mix test test/media_centarr/library/external_ids_test.exs
```

- [ ] **Step 4: Migrate every Inbound write path**

In `lib/media_centarr/library/inbound.ex`, find every place that writes `tmdb_id`/`imdb_id` on a container changeset. Remove from the changeset attrs map; emit `ExternalIds.put(:tmdb, record, tmdb_id)` after the insert.

```elixir
# Before:
attrs = %{name: ..., tmdb_id: "12345", imdb_id: "tt9876"}
{:ok, movie} = Library.create_movie(attrs)

# After:
attrs = %{name: ...}
{:ok, movie} = Library.create_movie(attrs)
ExternalIds.put(:tmdb, movie, "12345")
if imdb_id, do: ExternalIds.put(:imdb, movie, imdb_id)
```

- [ ] **Step 5: Migrate `find_by_tmdb_id/1` helpers**

```elixir
# lib/media_centarr/library/type_resolver.ex (or wherever lookups live)
def find_movie_by_tmdb_id(tmdb_id) do
  from(m in Movie,
    join: e in assoc(m, :external_ids),
    where: e.source == "tmdb" and e.external_id == ^tmdb_id,
    where: is_nil(m.movie_series_id)  # only standalone movies for this lookup
  )
  |> Repo.one()
end
```

Same shape for `find_tv_series_by_tmdb_id/1` etc. Note: these lookups need to be efficient — add a composite index on `library_external_ids (source, external_id)` if one doesn't exist.

- [ ] **Step 6: Write the column-drop migration**

```bash
mix ecto.gen.migration drop_redundant_tmdb_imdb_columns
```

```elixir
defmodule MediaCentarr.Repo.Migrations.DropRedundantTmdbImdbColumns do
  use Ecto.Migration

  def up do
    # Drop the unique indexes first
    drop_if_exists index(:library_movies, [:tmdb_id], name: :library_movies_tmdb_id_index)
    drop_if_exists index(:library_tv_series, [:tmdb_id], name: :library_tv_series_tmdb_id_index)
    drop_if_exists index(:library_movie_series, [:tmdb_id], name: :library_movie_series_tmdb_id_index)
    drop_if_exists index(:library_video_objects, [:tmdb_id], name: :library_video_objects_tmdb_id_index)

    alter table(:library_movies) do
      remove :tmdb_id
      remove :imdb_id
    end

    alter table(:library_tv_series) do
      remove :tmdb_id
      remove :imdb_id
    end

    alter table(:library_movie_series) do
      remove :tmdb_id
    end

    alter table(:library_video_objects) do
      remove :tmdb_id
    end

    # Ensure ExternalId lookups stay fast
    create_if_not_exists index(:library_external_ids, [:source, :external_id])
  end

  def down do
    # Destructive; no rollback. ExternalId is the source of truth post-migration.
    raise Ecto.MigrationError, "drop_redundant_tmdb_imdb_columns is not reversible"
  end
end
```

- [ ] **Step 7: Run migration and rebuild dev / showcase DBs**

```bash
mix ecto.reset
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.reset
```

- [ ] **Step 8: Drop the columns from each schema**

```elixir
# lib/media_centarr/library/movie.ex
- field :tmdb_id, :string
- field :imdb_id, :string
```

Same in tv_series.ex, movie_series.ex, video_object.ex (no `imdb_id` on movie_series / video_object today).

Update `create_changeset/1` to drop `:tmdb_id`, `:imdb_id` from `cast/3` field lists, and drop the `unique_constraint(:tmdb_id, ...)` lines.

- [ ] **Step 9: Find and update every reader**

```bash
grep -rn '\.tmdb_id\|\.imdb_id' lib/ test/ --exclude-dir=deps
```

Each hit converts to `ExternalIds.get(record, :tmdb)` / `ExternalIds.get(record, :imdb)`. Preload `:external_ids` on the read paths that need IDs.

- [ ] **Step 10: Race-loss recovery in `Inbound`**

`Library.Inbound`'s race-loss handler currently detects `:tmdb_id` unique-constraint violations on the container's own column. After this task, the violation surfaces on `library_external_ids` instead. Update the matcher:

```elixir
# Before:
if Keyword.has_key?(errors, :tmdb_id) do ...

# After:
# The container insert succeeds (no tmdb_id column to conflict on);
# the ExternalIds.put/3 call returns {:error, changeset} on conflict
# with the `(source, external_id, owner_type)` unique index. Handle
# at the ExternalIds.put/3 call site.
```

Adjust the unique index on `library_external_ids` to include the owner type discriminator (Phase 2 detail — for Phase 1 add a partial index per-owner-FK or live with looser uniqueness; document the chosen approach in the task commit).

- [ ] **Step 11: Run full test suite (3× via `--repeat-until-failure`)**

```bash
mix test --repeat-until-failure 3
```

Inbound is the integration hot-spot. Repeat-until-failure flushes order-dependent flakes.

- [ ] **Step 12: Run precommit**

```bash
mix precommit
```

- [ ] **Step 13: Commit**

```bash
jj describe -m "refactor(library): ExternalId is sole source for TMDB/IMDB ids"
jj new
```

---

## Post-Phase 1

- [ ] Update [`docs/library.md`](../../library.md): drop references to `tmdb_id`/`imdb_id` columns, `subtitle_tracks` on WatchedFile, stringly-typed dates/durations. Document `Library.Person` and `Library.ExternalIds`.
- [ ] Update [`campaigns/library-schema-v2.md`](../../../campaigns/library-schema-v2.md) Status section: Phase 1 complete, link to commits, note any deferred items.
- [ ] Update the wiki:
  - `Library-Browsing.md` if user-visible field display changed (year format, runtime format).
  - `Configuration-File.md` is unaffected.
- [ ] Run `scripts/profile` to baseline — Phase 1 shouldn't change perf measurably; confirm no regression before starting Phase 2.
- [ ] Write `decisions/architecture/2026-MM-DD-NNN-typed-pillar1-fields.md` if any decision warrants record (probably one ADR covering the typing + ExternalId-sole-source moves; the Person embedded schema and the SubtitleTrack move are mechanical and don't warrant separate ADRs).
- [ ] `jj describe -m "..."` + `jj new` after each task. Do **not** squash into one commit — each task should be revertible independently.

## Self-Review Checklist

- [ ] Every task has explicit file paths, code blocks, and `jj` commit guidance.
- [ ] No "TBD"/"placeholder"/"add validation"/"handle edge cases" wording.
- [ ] Function signatures match across tasks (`ExternalIds.put/3`, `get/2`).
- [ ] Each task ends with `mix precommit` + commit before the next starts.
- [ ] Pillar 2 projections are untouched in Phase 1 — none of these tasks should require re-pointing `Library.Views.*`. (They re-read through the same context functions; only the underlying shape changes.)
- [ ] Phase 1 leaves the project in a shippable state — at no commit boundary is `main` broken.
