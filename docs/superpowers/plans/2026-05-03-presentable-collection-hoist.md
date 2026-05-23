# Presentable Collection Hoist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop rendering single-movie MovieSeries collections as collection containers in browse-style surfaces; instead surface the child movie at top level while preserving the collection link as queryable metadata.

**Architecture:** The hoist rule lives in SQL — each surface fetches "multi-child movie_series (≥2 present children, keep)" and "singleton-collection movies (sole present child, surface as a Movie)" as two distinct queries instead of one undifferentiated MovieSeries fetch. Standalone Movies, TV series, and video objects are unchanged. Hoisted Movie records preload their `movie_series` association so detail views can render a "Part of: X" badge without nesting. A new `EntityShape.normalize/2` field `collection` exposes this in the rich shape; slim Home shapes can read it directly off the record.

**Tech Stack:** Elixir, Ecto (SQLite), Phoenix LiveView. Existing patterns: `where: exists(present_files_subquery)` for "files present" filtering; `Repo.preload/2` for batched associations.

---

## File Structure

**New files:**
- `lib/media_centaur/library/presentable_queries.ex` — composable Ecto query fragments for the hoist split.
- `test/media_centaur/library/presentable_queries_test.exs` — unit tests for the two query helpers.

**Modified files:**
- `lib/media_centaur/library/entity_shape.ex` — `normalize/2` adds `:collection` field.
- `lib/media_centaur/library/browser.ex` — `fetch_all_typed_entries/0`, `fetch_typed_entries_by_ids/1`. Drop `maybe_unwrap_single_movie/1`.
- `lib/media_centaur/library.ex` — `list_recently_added/1`, `list_in_progress/1`, `list_hero_candidates/1` plus their per-type fetchers.
- `test/media_centaur/library_browser_test.exs` — extend the N+1 regression guard with hoist coverage.
- `test/media_centaur/library_test.exs` — extend Home surface tests with hoist coverage.

---

## Conventions

This is a JJ repo. Use `jj describe -m "..."` to set the commit message on the working copy, then `jj new` to start the next change. Do **not** run `git commit`. Conventional-commit prefixes: `feat:`, `fix:`, `refactor:`, `test:`.

The project uses `mix precommit` as the gate. Each task ends with running the targeted test for the changed file. The full `mix precommit` runs once at the end.

---

### Task 1: Add `Library.PresentableQueries` with the two hoist-split query helpers

**Why first:** Every other change depends on these helpers. Building them in isolation with their own tests means every downstream surface gets correct, tested queries from the start.

**Files:**
- Create: `lib/media_centaur/library/presentable_queries.ex`
- Test: `test/media_centaur/library/presentable_queries_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/media_centaur/library/presentable_queries_test.exs
defmodule MediaCentaur.Library.PresentableQueriesTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Library.{Movie, MovieSeries, PresentableQueries}
  alias MediaCentaur.Repo

  import MediaCentaur.LibraryFixtures
  import MediaCentaur.WatcherFixtures

  describe "multi_child_movie_series/0" do
    test "returns movie_series with 2+ present children" do
      ms = movie_series_fixture(%{name: "Multi Collection"})
      m1 = movie_fixture(%{name: "M1", movie_series_id: ms.id})
      m2 = movie_fixture(%{name: "M2", movie_series_id: ms.id})
      _present_kf1 = known_file_fixture(%{file_path: "/m1.mkv", state: :present})
      _present_kf2 = known_file_fixture(%{file_path: "/m2.mkv", state: :present})
      _wf1 = watched_file_fixture(%{file_path: "/m1.mkv", movie_id: m1.id})
      _wf2 = watched_file_fixture(%{file_path: "/m2.mkv", movie_id: m2.id})

      results = PresentableQueries.multi_child_movie_series() |> Repo.all()

      assert Enum.map(results, & &1.id) == [ms.id]
    end

    test "excludes movie_series with exactly 1 present child" do
      ms = movie_series_fixture(%{name: "Singleton Collection"})
      m1 = movie_fixture(%{movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/only.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/only.mkv", movie_id: m1.id})

      assert PresentableQueries.multi_child_movie_series() |> Repo.all() == []
    end

    test "excludes movie_series whose extra children are absent" do
      ms = movie_series_fixture(%{})
      m1 = movie_fixture(%{movie_series_id: ms.id})
      m2 = movie_fixture(%{movie_series_id: ms.id})
      _kf_present = known_file_fixture(%{file_path: "/m1.mkv", state: :present})
      _kf_absent = known_file_fixture(%{file_path: "/m2.mkv", state: :absent})
      _wf1 = watched_file_fixture(%{file_path: "/m1.mkv", movie_id: m1.id})
      _wf2 = watched_file_fixture(%{file_path: "/m2.mkv", movie_id: m2.id})

      assert PresentableQueries.multi_child_movie_series() |> Repo.all() == []
    end
  end

  describe "singleton_collection_movies/0" do
    test "returns the child movie of a movie_series with exactly 1 present child" do
      ms = movie_series_fixture(%{name: "Mascot Collection"})
      child = movie_fixture(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      results = PresentableQueries.singleton_collection_movies() |> Repo.all()

      assert Enum.map(results, & &1.id) == [child.id]
    end

    test "excludes child movies whose movie_series has 2+ present children" do
      ms = movie_series_fixture(%{})
      m1 = movie_fixture(%{movie_series_id: ms.id})
      m2 = movie_fixture(%{movie_series_id: ms.id})
      _kf1 = known_file_fixture(%{file_path: "/m1.mkv", state: :present})
      _kf2 = known_file_fixture(%{file_path: "/m2.mkv", state: :present})
      _wf1 = watched_file_fixture(%{file_path: "/m1.mkv", movie_id: m1.id})
      _wf2 = watched_file_fixture(%{file_path: "/m2.mkv", movie_id: m2.id})

      assert PresentableQueries.singleton_collection_movies() |> Repo.all() == []
    end

    test "excludes standalone movies (no movie_series_id)" do
      standalone = movie_fixture(%{movie_series_id: nil})
      _kf = known_file_fixture(%{file_path: "/standalone.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/standalone.mkv", movie_id: standalone.id})

      assert PresentableQueries.singleton_collection_movies() |> Repo.all() == []
    end
  end

  describe "standalone_movies/0" do
    test "returns movies without a movie_series_id and with present files" do
      m = movie_fixture(%{movie_series_id: nil})
      _kf = known_file_fixture(%{file_path: "/m.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/m.mkv", movie_id: m.id})

      results = PresentableQueries.standalone_movies() |> Repo.all()
      assert Enum.map(results, & &1.id) == [m.id]
    end

    test "excludes movies belonging to a collection" do
      ms = movie_series_fixture(%{})
      m = movie_fixture(%{movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/m.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/m.mkv", movie_id: m.id})

      assert PresentableQueries.standalone_movies() |> Repo.all() == []
    end
  end
end
```

**Note for executor:** the existing `library_browser_test.exs` already creates fixtures via these helpers. If a helper is missing, look at how `library_browser_test.exs` builds its scenario and reuse the same pattern. Do not invent new fixture functions.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/library/presentable_queries_test.exs`
Expected: FAIL with "module PresentableQueries is not loaded".

- [ ] **Step 3: Implement the module**

```elixir
# lib/media_centaur/library/presentable_queries.ex
defmodule MediaCentaur.Library.PresentableQueries do
  @moduledoc """
  Composable Ecto query fragments that encode the "presentable" hoist rule
  for browse-style surfaces.

  ## The hoist rule

  TMDB collections (`MovieSeries`) are linked from `Movie.movie_series_id`
  whenever TMDB returns a `belongs_to_collection`. Browse surfaces should
  not render a collection container when only one of its movies is in the
  user's library — the user should see the movie directly, with the
  collection preserved as queryable metadata (the `movie_series` belongs_to
  association on the Movie).

  ## Three presentable kinds for movie-shaped rows

    * `standalone_movies/0` — `movie_series_id IS NULL`, present files only
    * `singleton_collection_movies/0` — sole present child of its
      `MovieSeries`; the row to surface in place of the collection container
    * `multi_child_movie_series/0` — `MovieSeries` with 2+ present children;
      the row to surface as a collection container

  Together they partition every Movie/MovieSeries the user sees at the top
  level. Each is a query fragment — callers compose `order_by`, `limit`, and
  `Repo.preload/2` per surface.

  All three exclude rows whose `WatchedFile`s do not have a corresponding
  `KnownFile` in `:present` state, matching the existing browse semantics.
  """
  import Ecto.Query

  alias MediaCentaur.Library.{Movie, MovieSeries}
  alias MediaCentaur.Watcher.KnownFile

  @doc """
  Standalone movies: `movie_series_id IS NULL`, with at least one present file.
  """
  def standalone_movies do
    from(m in Movie,
      as: :item,
      where: is_nil(m.movie_series_id),
      where: exists(present_files_subquery(:movie_id))
    )
  end

  @doc """
  Singleton-collection movies: a movie that is the sole present child of its
  `MovieSeries`. Use when the surface wants the child movie shown in place of
  a 1-movie collection container.
  """
  def singleton_collection_movies do
    from(m in Movie,
      as: :item,
      where: not is_nil(m.movie_series_id),
      where: exists(present_files_subquery(:movie_id)),
      where:
        fragment(
          """
          (SELECT COUNT(*)
             FROM library_movies AS m2
            WHERE m2.movie_series_id = ?
              AND EXISTS (
                SELECT 1
                  FROM library_watched_files AS wf
                  JOIN watcher_files AS kf ON kf.file_path = wf.file_path
                 WHERE wf.movie_id = m2.id AND kf.state = 'present'
              )
          ) = 1
          """,
          m.movie_series_id
        )
    )
  end

  @doc """
  Movie series with 2+ present children. Use when the surface wants a collection
  container row. (The 1-child case is delegated to `singleton_collection_movies/0`.)
  """
  def multi_child_movie_series do
    from(ms in MovieSeries,
      as: :item,
      where:
        fragment(
          """
          (SELECT COUNT(*)
             FROM library_movies AS m
            WHERE m.movie_series_id = ?
              AND EXISTS (
                SELECT 1
                  FROM library_watched_files AS wf
                  JOIN watcher_files AS kf ON kf.file_path = wf.file_path
                 WHERE wf.movie_id = m.id AND kf.state = 'present'
              )
          ) >= 2
          """,
          ms.id
        )
    )
  end

  defp present_files_subquery(fk_column) do
    from(wf in "library_watched_files",
      join: kf in KnownFile,
      on: kf.file_path == wf.file_path,
      where: field(wf, ^fk_column) == parent_as(:item).id and kf.state == :present,
      select: 1
    )
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centaur/library/presentable_queries_test.exs`
Expected: PASS — all three describe blocks green.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(library): add PresentableQueries for collection hoist"
jj new
```

---

### Task 2: Extend `EntityShape.normalize/2` with `:collection` field

**Why:** Hoisted Movies need to expose their parent MovieSeries metadata so detail views can render a "Part of: X collection" badge without nesting. The rich-shape contract is the right place to surface this — slim Home shapes can read `record.movie_series` directly when they need it.

**Files:**
- Modify: `lib/media_centaur/library/entity_shape.ex`
- Test: `test/media_centaur/library/entity_shape_test.exs` (create if missing)

- [ ] **Step 1: Check whether the test file exists**

Run: `ls test/media_centaur/library/entity_shape_test.exs 2>/dev/null && echo found || echo missing`

If missing, create it with the standard header:
```elixir
defmodule MediaCentaur.Library.EntityShapeTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Library.EntityShape
end
```

- [ ] **Step 2: Write the failing tests (append to the describe stack)**

```elixir
  describe "normalize/2 with :collection field" do
    test "movie with preloaded movie_series populates :collection" do
      ms = %MediaCentaur.Library.MovieSeries{
        id: "ms-uuid",
        name: "Mascot Collection"
      }

      record = %MediaCentaur.Library.Movie{
        id: "m-uuid",
        name: "Mascot Cosmos",
        movie_series_id: "ms-uuid",
        movie_series: ms,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      result = EntityShape.normalize(record, :movie)

      assert result.collection == %{id: "ms-uuid", name: "Mascot Collection"}
    end

    test "standalone movie has nil :collection" do
      record = %MediaCentaur.Library.Movie{
        id: "m-uuid",
        name: "Standalone",
        movie_series_id: nil,
        movie_series: nil,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :movie).collection == nil
    end

    test "non-movie types have nil :collection" do
      record = %MediaCentaur.Library.TVSeries{
        id: "tv-uuid",
        name: "Show",
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :tv_series).collection == nil
    end

    test "movie with movie_series_id but unloaded association has nil :collection" do
      record = %MediaCentaur.Library.Movie{
        id: "m-uuid",
        name: "Mascot Cosmos",
        movie_series_id: "ms-uuid",
        movie_series: %Ecto.Association.NotLoaded{},
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :movie).collection == nil
    end
  end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/media_centaur/library/entity_shape_test.exs`
Expected: FAIL — `result.collection` is missing or `nil` in the positive case.

- [ ] **Step 4: Modify `normalize/2`**

In `lib/media_centaur/library/entity_shape.ex`, add a `collection: collection_from(record, type)` field to the map returned by `normalize/2`, and add a private helper:

```elixir
  defp collection_from(%{movie_series: %{id: id, name: name}}, :movie),
    do: %{id: id, name: name}

  defp collection_from(_record, _type), do: nil
```

The pattern only matches when `movie_series` is loaded as a struct (not `%Ecto.Association.NotLoaded{}` and not `nil`). Place the field after `:status` or near other metadata-style fields in the existing `normalize/2` map.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/media_centaur/library/entity_shape_test.exs`
Expected: PASS — all four cases green.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(library): add :collection field to EntityShape.normalize"
jj new
```

---

### Task 3: Refactor `Browser.fetch_all_typed_entries/0` to use PresentableQueries

**Why:** The library grid is the foundational consumer. Switching it first means we can validate the hoist behavior end-to-end before touching the Home page surfaces. The existing `maybe_unwrap_single_movie/1` becomes redundant and is removed; the entity id bug (using MovieSeries id while claiming `type: :movie`) is fixed because hoisted rows are real Movie records.

**Files:**
- Modify: `lib/media_centaur/library/browser.ex`
- Test: `test/media_centaur/library_browser_test.exs`

- [ ] **Step 1: Read the existing N+1 regression test to understand the contract**

Run: `cat test/media_centaur/library_browser_test.exs | head -80`

Identify the existing describe block "query count (N+1 regression guard)" — the new tests will sit alongside it.

- [ ] **Step 2: Add failing tests for hoist behavior**

Append to `test/media_centaur/library_browser_test.exs`:

```elixir
  describe "collection hoist" do
    test "single-child movie_series surfaces as the child Movie with Movie.id" do
      ms = movie_series_fixture(%{name: "Mascot Collection"})
      child = movie_fixture(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      entries = MediaCentaur.Library.Browser.fetch_all_typed_entries()
      mario = Enum.find(entries, fn e -> e.entity.name == "Mascot Cosmos" end)

      assert mario != nil
      assert mario.entity.type == :movie
      assert mario.entity.id == child.id
      assert mario.entity.collection == %{id: ms.id, name: "Mascot Collection"}

      refute Enum.any?(entries, fn e -> e.entity.name == "Mascot Collection" end)
    end

    test "multi-child movie_series remains a collection container" do
      ms = movie_series_fixture(%{name: "Trilogy"})
      m1 = movie_fixture(%{name: "Part 1", movie_series_id: ms.id})
      m2 = movie_fixture(%{name: "Part 2", movie_series_id: ms.id})
      for {m, path} <- [{m1, "/p1.mkv"}, {m2, "/p2.mkv"}] do
        _kf = known_file_fixture(%{file_path: path, state: :present})
        _wf = watched_file_fixture(%{file_path: path, movie_id: m.id})
      end

      entries = MediaCentaur.Library.Browser.fetch_all_typed_entries()
      trilogy = Enum.find(entries, fn e -> e.entity.name == "Trilogy" end)

      assert trilogy != nil
      assert trilogy.entity.type == :movie_series
      assert trilogy.entity.id == ms.id
      assert length(trilogy.entity.movies) == 2
    end

    test "fetch_typed_entries_by_ids resolves a Movie.id for a hoisted singleton" do
      ms = movie_series_fixture(%{})
      child = movie_fixture(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      {[entry], gone} =
        MediaCentaur.Library.Browser.fetch_typed_entries_by_ids([child.id])

      assert MapSet.size(gone) == 0
      assert entry.entity.type == :movie
      assert entry.entity.id == child.id
    end

    test "fetch_typed_entries_by_ids reports the MovieSeries id as gone when the collection is hoisted away" do
      ms = movie_series_fixture(%{})
      child = movie_fixture(%{movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      {entries, gone} =
        MediaCentaur.Library.Browser.fetch_typed_entries_by_ids([ms.id])

      assert entries == []
      assert MapSet.member?(gone, ms.id)
    end
  end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/media_centaur/library_browser_test.exs --only describe:"collection hoist"`
Expected: FAIL — entries still show "Mascot Collection" or use the MovieSeries id.

If the `--only` filter syntax doesn't match, omit it and run the file; the new failures will be obvious in the output.

- [ ] **Step 4: Refactor `Browser` to use the new queries**

In `lib/media_centaur/library/browser.ex`, replace the four list-style fetchers with five (movies split into standalone + hoisted):

Replace the body of `fetch_all_typed_entries/0`:

```elixir
  def fetch_all_typed_entries do
    standalone_movies = fetch_standalone_movies()
    hoisted_movies = fetch_hoisted_movies()
    tv_series = fetch_all_tv_series()
    movie_series = fetch_all_movie_series()
    video_objects = fetch_all_video_objects()

    entries =
      standalone_movies ++ hoisted_movies ++ tv_series ++ movie_series ++ video_objects

    Log.info(
      :library,
      "loaded #{length(entries)} typed entries for browser " <>
        "(#{length(standalone_movies)} standalone movies, " <>
        "#{length(hoisted_movies)} hoisted-collection movies, " <>
        "#{length(tv_series)} tv, " <>
        "#{length(movie_series)} multi-child movie series, " <>
        "#{length(video_objects)} video objects)"
    )

    entries
    |> Enum.map(&build_typed_entry/1)
    |> Enum.sort_by(fn entry -> String.downcase(entry.entity.name || "") end)
  end
```

Replace `fetch_standalone_movies/0` to use `PresentableQueries`:

```elixir
  defp fetch_standalone_movies do
    PresentableQueries.standalone_movies()
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
  end
```

Add `fetch_hoisted_movies/0`:

```elixir
  defp fetch_hoisted_movies do
    PresentableQueries.singleton_collection_movies()
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress, :movie_series])
  end
```

Replace `fetch_all_movie_series/0`:

```elixir
  defp fetch_all_movie_series do
    PresentableQueries.multi_child_movie_series()
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      movies: [:images, :watch_progress]
    ])
  end
```

Apply the same pattern to `fetch_typed_entries_by_ids/1`. Add filtering by id list before `Repo.all()`:

```elixir
  def fetch_typed_entries_by_ids(ids) do
    id_list = if is_list(ids), do: ids, else: MapSet.to_list(ids)

    movies = fetch_standalone_movies_by_ids(id_list)
    hoisted = fetch_hoisted_movies_by_ids(id_list)
    tv = fetch_tv_series_by_ids(id_list)
    ms = fetch_movie_series_by_ids(id_list)
    vo = fetch_video_objects_by_ids(id_list)

    entries =
      Enum.map(movies ++ hoisted ++ tv ++ ms ++ vo, &build_typed_entry/1)

    present_ids = MapSet.new(entries, fn entry -> entry.entity.id end)
    requested = MapSet.new(id_list)
    gone_ids = MapSet.difference(requested, present_ids)

    {entries, gone_ids}
  end

  defp fetch_standalone_movies_by_ids(ids) do
    from([m] in PresentableQueries.standalone_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
  end

  defp fetch_hoisted_movies_by_ids(ids) do
    from([m] in PresentableQueries.singleton_collection_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress, :movie_series])
  end

  defp fetch_movie_series_by_ids(ids) do
    from([ms] in PresentableQueries.multi_child_movie_series(), where: ms.id in ^ids)
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      movies: [:images, :watch_progress]
    ])
  end
```

The `from([m] in q, where: ...)` syntax requires the upstream query to declare `as: :item` (which `PresentableQueries` already does). If Ecto rejects the bind name, use `from(m in subquery(q), where: m.id in ^ids)` instead — verify by running the test.

Delete `maybe_unwrap_single_movie/1` and its callsite in `build_entry_from_normalized/2`:

```elixir
  defp build_entry_from_normalized(entity, progress_records) do
    entity = pre_sort_children(entity)

    summary = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: summary, progress_records: progress_records}
  end
```

Also delete the `maybe_unwrap_single_movie/1` function. Add the alias:

```elixir
  alias MediaCentaur.Library.{EntityShape, Movie, MovieSeries, PresentableQueries, TVSeries, VideoObject}
```

(Delete the now-unused `import Ecto.Query` if and only if `from(...)` no longer appears in the file. Most by_ids fetchers still need it — keep the import.)

The TV-series and video-object fetchers (`fetch_all_tv_series/0`, `fetch_tv_series_by_ids/1`, `fetch_all_video_objects/0`, `fetch_video_objects_by_ids/1`) keep their existing implementations — only the movie/movie-series paths change.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/media_centaur/library_browser_test.exs`
Expected: PASS — all existing tests still green, plus the four new hoist tests.

- [ ] **Step 6: Update the existing N+1 regression guard if its expected count changed**

If the query-count assertion fails because we now issue one extra query (the hoisted-movies fetch + its preloads), update the constant. Justify the bump in a code comment: hoisted-movies branch adds one Repo.all + four preloads = 5 queries.

Run: `mix test test/media_centaur/library_browser_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
jj describe -m "refactor(library): use PresentableQueries in Browser; drop maybe_unwrap_single_movie"
jj new
```

---

### Task 4: Refactor `Library.list_recently_added/1` to hoist singletons

**Why:** This is the surface that triggered the original bug report — Home's "Recently added" carousel shows "The Sample Mascot Collection" instead of "The Sample Mascot Cosmos Movie". The fix mirrors Task 3 but for the slim Home shape.

**Files:**
- Modify: `lib/media_centaur/library.ex` (around line 861)
- Test: `test/media_centaur/library_test.exs`

- [ ] **Step 1: Write failing tests**

Append to `test/media_centaur/library_test.exs` (or create a `describe "list_recently_added/1 hoist"` block):

```elixir
  describe "list_recently_added/1 collection hoist" do
    test "single-child movie_series surfaces as the child movie" do
      ms = movie_series_fixture(%{name: "Mascot Collection"})
      child = movie_fixture(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      results = MediaCentaur.Library.list_recently_added(limit: 50)

      mario = Enum.find(results, fn r -> r.name == "Mascot Cosmos" end)
      assert mario != nil
      assert mario.id == child.id

      refute Enum.any?(results, fn r -> r.name == "Mascot Collection" end)
    end

    test "multi-child movie_series stays as a collection row" do
      ms = movie_series_fixture(%{name: "Trilogy"})
      for {name, path} <- [{"Part 1", "/p1.mkv"}, {"Part 2", "/p2.mkv"}] do
        m = movie_fixture(%{name: name, movie_series_id: ms.id})
        _kf = known_file_fixture(%{file_path: path, state: :present})
        _wf = watched_file_fixture(%{file_path: path, movie_id: m.id})
      end

      results = MediaCentaur.Library.list_recently_added(limit: 50)
      trilogy = Enum.find(results, fn r -> r.name == "Trilogy" end)

      assert trilogy != nil
      assert trilogy.id == ms.id
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centaur/library_test.exs`
Expected: FAIL — "Mascot Collection" still surfaces; "Mascot Cosmos" missing.

- [ ] **Step 3: Modify `list_recently_added/1` and its fetchers**

In `lib/media_centaur/library.ex`, change `list_recently_added/1`:

```elixir
  def list_recently_added(opts \\ []) do
    limit = Keyword.get(opts, :limit, 16)

    movies = fetch_recently_added_movies(limit)
    hoisted = fetch_recently_added_hoisted_movies(limit)
    tv_series = fetch_recently_added_tv_series(limit)
    movie_series = fetch_recently_added_movie_series(limit)
    video_objects = fetch_recently_added_video_objects(limit)

    (movies ++ hoisted ++ tv_series ++ movie_series ++ video_objects)
    |> Enum.sort_by(& &1.__inserted_at__, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :__inserted_at__))
  end
```

Replace `fetch_recently_added_movies/1` to use `PresentableQueries.standalone_movies/0`:

```elixir
  defp fetch_recently_added_movies(limit) do
    from([m] in PresentableQueries.standalone_movies(),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end
```

Add `fetch_recently_added_hoisted_movies/1`:

```elixir
  defp fetch_recently_added_hoisted_movies(limit) do
    from([m] in PresentableQueries.singleton_collection_movies(),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end
```

Replace `fetch_recently_added_movie_series/1` to use `PresentableQueries.multi_child_movie_series/0`:

```elixir
  defp fetch_recently_added_movie_series(limit) do
    from([ms] in PresentableQueries.multi_child_movie_series(),
      order_by: [{:desc, ms.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end
```

Add the alias at the top of `library.ex`:

```elixir
  alias MediaCentaur.Library.{..., PresentableQueries, ...}
```

(`shape_recently_added_record/1` is already type-agnostic — it reads `:id`, `:name`, `:date_published`, `:images`, `:inserted_at` from any record. No changes needed there.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centaur/library_test.exs`
Expected: PASS for the new hoist describe; existing recently_added tests still green.

- [ ] **Step 5: Commit**

```bash
jj describe -m "refactor(library): hoist singleton collections in list_recently_added"
jj new
```

---

### Task 5: Refactor `Library.list_in_progress/1` to hoist singletons

**Why:** The "Continue watching" carousel uses the rich shape (`%{entity, progress, progress_records}`) plus `shape_in_progress_row/1`. Its in-progress fetchers are paginated by `last_watched_at` rather than `inserted_at`, so the singleton-hoist branch is added analogously but with the right ordering.

**Files:**
- Modify: `lib/media_centaur/library.ex` (around lines 835, 1107, 1255, 1315)
- Test: `test/media_centaur/library_test.exs`

- [ ] **Step 1: Write failing tests**

Append to `test/media_centaur/library_test.exs`:

```elixir
  describe "list_in_progress/1 collection hoist" do
    test "single-child movie_series with in-progress child surfaces as the child movie" do
      ms = movie_series_fixture(%{name: "Mascot Collection"})
      child = movie_fixture(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})
      _wp =
        watch_progress_fixture(%{
          movie_id: child.id,
          position_seconds: 100,
          duration_seconds: 1000,
          completed: false,
          last_watched_at: ~U[2026-05-03 00:00:00Z]
        })

      results = MediaCentaur.Library.list_in_progress(limit: 50)
      mario = Enum.find(results, fn r -> r.entity_name == "Mascot Cosmos" end)

      assert mario != nil
      assert mario.entity_id == child.id

      refute Enum.any?(results, fn r -> r.entity_name == "Mascot Collection" end)
    end
  end
```

(Use whatever `watch_progress_fixture/1` helper the existing in-progress tests use — adjust the field names if the fixture takes different keys.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centaur/library_test.exs`
Expected: FAIL.

- [ ] **Step 3: Modify `list_in_progress/1` and its fetchers**

In `lib/media_centaur/library.ex`, change `list_in_progress/1`:

```elixir
  def list_in_progress(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movie_entries = fetch_in_progress_movies(limit)
    hoisted_entries = fetch_in_progress_hoisted_movies(limit)
    tv_series_entries = fetch_in_progress_tv_series(limit)
    video_object_entries = fetch_in_progress_video_objects(limit)
    movie_series_entries = fetch_in_progress_movie_series(limit)

    (movie_entries ++ hoisted_entries ++ tv_series_entries ++ video_object_entries ++ movie_series_entries)
    |> Enum.sort_by(
      fn entry -> entry_last_watched_at(entry) || @epoch_datetime end,
      {:desc, DateTime}
    )
    |> Enum.take(limit)
    |> Enum.map(&shape_in_progress_row/1)
  end
```

Read the existing `fetch_in_progress_movies/1` (around line 1107) to learn its preloads and entity-wrap pattern. Add `fetch_in_progress_hoisted_movies/1` next to it that mirrors the structure but uses `PresentableQueries.singleton_collection_movies/0` as its base query and additionally preloads `:movie_series` (so `EntityShape.normalize/2` can populate `:collection`).

Update `fetch_in_progress_movies/1` itself to use `PresentableQueries.standalone_movies/0` (compose `where:` and `order_by:` on top of it).

Update `fetch_in_progress_movie_series/1` to use `PresentableQueries.multi_child_movie_series/0` as its base.

(Read each existing fetcher carefully — they share scaffolding. The diff per fetcher is replacing the bare `from(m in Movie, ...)` head with `from([m] in PresentableQueries.<helper>(), ...)`. Keep the where/order/preload tail intact.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centaur/library_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj describe -m "refactor(library): hoist singleton collections in list_in_progress"
jj new
```

---

### Task 6: Refactor `Library.list_hero_candidates/1` to hoist singletons

**Why:** The Home hero rotation pulls from the same four type-specific tables. A 1-movie "collection" qualifying as a hero candidate would surface a `MovieSeries` that the hero card renders as a collection — same bug, same fix.

**Files:**
- Modify: `lib/media_centaur/library.ex` (around line 965)
- Test: `test/media_centaur/library_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
  describe "list_hero_candidates/1 collection hoist" do
    test "single-child movie_series surfaces as the child movie" do
      ms = movie_series_fixture(%{name: "Mascot Collection"})
      child =
        movie_fixture(%{
          name: "Mascot Cosmos",
          description: "A long description.",
          movie_series_id: ms.id
        })

      _kf = known_file_fixture(%{file_path: "/mario.mkv", state: :present})
      _wf = watched_file_fixture(%{file_path: "/mario.mkv", movie_id: child.id})

      _backdrop =
        image_fixture(%{
          movie_id: child.id,
          role: "backdrop",
          content_url: "/path/to/backdrop.jpg"
        })

      results = MediaCentaur.Library.list_hero_candidates(limit: 50)
      mario = Enum.find(results, fn r -> r.name == "Mascot Cosmos" end)

      assert mario != nil
      refute Enum.any?(results, fn r -> r.name == "Mascot Collection" end)
    end
  end
```

(Reuse whichever fixture function creates Image rows in `library_test.exs`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/library_test.exs`
Expected: FAIL.

- [ ] **Step 3: Modify `list_hero_candidates/1` and its fetchers**

In `lib/media_centaur/library.ex`:

```elixir
  def list_hero_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movies = fetch_hero_candidates_movies(limit)
    hoisted = fetch_hero_candidates_hoisted_movies(limit)
    tv_series = fetch_hero_candidates_tv_series(limit)
    movie_series = fetch_hero_candidates_movie_series(limit)
    video_objects = fetch_hero_candidates_video_objects(limit)

    Enum.take(movies ++ hoisted ++ tv_series ++ movie_series ++ video_objects, limit)
  end
```

Read the existing `fetch_hero_candidates_movies/1` (around line 978) and `fetch_hero_candidates_movie_series/1`. Each composes a backdrop-existence check + non-empty-description check. The pattern repeats; replicate it for hoisted movies using `PresentableQueries.singleton_collection_movies/0` as the base.

Switch `fetch_hero_candidates_movies/1` to use `PresentableQueries.standalone_movies/0` and `fetch_hero_candidates_movie_series/1` to use `PresentableQueries.multi_child_movie_series/0`. The backdrop/description filters are layered on top via `where:`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centaur/library_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj describe -m "refactor(library): hoist singleton collections in list_hero_candidates"
jj new
```

---

### Task 7: Verify Mario in production data renders as expected

**Why:** Catch end-to-end issues that unit tests can't see — image preload fields populated correctly, the LiveView grid stream actually renders the new entity, the modal opens with the Movie's id, etc.

**Files:** None — verification only. Use `~/scripts/mc-rpc` against the running production node.

- [ ] **Step 1: Verify Browser hoist returns the Movie's id**

Run:
```bash
~/scripts/mc-rpc '
alias MediaCentaur.Library.Browser

entries = Browser.fetch_all_typed_entries()
mario = Enum.find(entries, fn e -> String.contains?(String.downcase(e.entity.name || ""), "mario") end)
IO.inspect(Map.take(mario.entity, [:id, :type, :name, :collection]))
'
```

Expected output:
```
%{id: "<MOVIE_UUID, NOT MOVIE_SERIES_UUID>", type: :movie, name: "The Sample Mascot Cosmos Movie", collection: %{id: "<ms_uuid>", name: "The Sample Mascot Collection"}}
```

The `id` must be the Movie's id (`7fea1baa-8e53-41c2-8f17-1007073ae76f`), not the MovieSeries id (`e7f01f3c-...`).

- [ ] **Step 2: Verify list_recently_added returns the Movie**

Run:
```bash
~/scripts/mc-rpc '
results = MediaCentaur.Library.list_recently_added(limit: 50)
mario = Enum.filter(results, fn e -> String.contains?(String.downcase(e.name || ""), "mario") end)
for e <- mario, do: IO.inspect(e)
'
```

Expected: at most one entry, named "The Sample Mascot Cosmos Movie", with the Movie's id. No "The Sample Mascot Collection" row.

- [ ] **Step 3: If either assertion fails, debug before continuing**

Read the relevant fetcher; check whether `PresentableQueries.singleton_collection_movies/0` is returning the row. If the SQL `fragment(...)` is rejected by SQLite, log the generated query via `Ecto.Adapters.SQL.to_sql(:all, Repo, query)` and adjust the literal SQL until SQLite accepts it.

- [ ] **Step 4: No commit — this is a verification gate, not a code change.**

---

### Task 8: Audit Upcoming and WatchHistory for MovieSeries leakage

**Why:** Both surfaces persist `entity_id` (UpcomingLive uses `ReleaseTracking`; WatchHistory has its own event table). If they store MovieSeries ids that no longer correspond to a top-level browse entity, the UI may dead-link or misrender. Better to confirm now than discover later.

**Files:** None — audit only.

- [ ] **Step 1: Inspect ReleaseTracking item types**

Run:
```bash
~/scripts/mc-rpc '
import Ecto.Query
alias MediaCentaur.Repo
alias MediaCentaur.ReleaseTracking.Item

result =
  from(i in Item, group_by: i.tmdb_type, select: {i.tmdb_type, count(i.id)})
  |> Repo.all()

IO.inspect(result, label: "tracking items by type")
'
```

If `tmdb_type` includes `"collection"` or anything that maps to MovieSeries, document it. If not (just `"movie"` and `"tv"`), Upcoming is unaffected.

- [ ] **Step 2: Inspect WatchHistory event entity_types**

Run:
```bash
~/scripts/mc-rpc '
import Ecto.Query
alias MediaCentaur.Repo
alias MediaCentaur.WatchHistory.Event

result =
  from(e in Event, group_by: e.entity_type, select: {e.entity_type, count(e.id)})
  |> Repo.all()

IO.inspect(result, label: "watch history events by entity_type")
'
```

If `entity_type` includes `:movie_series`, then watch history rows reference MovieSeries ids. After the hoist, clicking such a row would still load the MovieSeries via `load_modal_entry`, which `fetch_typed_entries_by_ids` will report as gone (because the singleton MovieSeries no longer surfaces). Document any rows found.

- [ ] **Step 3: Decide remediation**

If either audit returns rows referencing single-child MovieSeries ids, the user must decide:
  (a) Translate at the boundary — when WatchHistory loads a row whose entity is a hoisted MovieSeries, resolve it to the child Movie's id and load that.
  (b) Backfill — write a one-time migration that updates entity_id for affected events.

If both audits return clean results (no MovieSeries-typed rows or no hoisted MovieSeries among them), no remediation needed. Document the outcome.

- [ ] **Step 4: No commit — audit only. Capture findings in conversation summary.**

---

### Task 9: `mix precommit` and final verification

**Why:** The full quality gate. Catches any compile warnings, formatter drift, Credo issues, sobelow alerts, or test failures introduced by the refactor.

**Files:** None — verification only.

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: PASS — zero warnings, zero failures.

If failures appear, address each one. Per project policy, every warning is a bug — including unused vars/aliases.

- [ ] **Step 2: Manually verify the Home page in the browser**

Confirm:
1. Visit `http://127.0.0.1:1080/`. The "Recently added" carousel includes "The Sample Mascot Cosmos Movie" — not "The Sample Mascot Collection".
2. The "Continue watching" carousel (if Mario has progress) shows the movie name, not the collection.
3. Click the Mario tile — the modal opens to the Movie detail. The detail panel shows a "Part of: The Sample Mascot Collection" badge if Task 2's `:collection` field is being read by the panel (note: badge rendering is out of scope for this plan; we just guarantee the data is available).
4. Visit `/library`. Mario shows once, top-level, with the Movie's name. No collection wrapper.

- [ ] **Step 3: Commit final precommit output (if any formatter drift)**

If `mix precommit` made any auto-fixes, commit them:

```bash
jj describe -m "chore(library): formatter cleanup after presentable hoist"
jj new
```

Otherwise, no commit needed.

- [ ] **Step 4: The plan is complete.**

---

## Notes for the executor

- The codebase is JJ-managed. After completing a task's commits with `jj describe`, run `jj new` to create an empty change for the next task.
- Skip `git commit`. Skip `git add`. JJ tracks files automatically.
- The `PresentableQueries` module composes via `as: :item` Ecto bindings — when extending a query in a calling site, use `from([m] in PresentableQueries.standalone_movies(), ...)`. If Ecto rejects the bind alias, fall back to `subquery(...)`.
- The N+1 regression test in `library_browser_test.exs` will need its expected query count bumped by ~5 (one new fetcher's `Repo.all` + four preloads). Document the bump in a comment.
- All tests must use `MediaCentaur.DataCase` and existing fixture helpers. Do not invent new fixtures unless the existing helpers truly cannot express the scenario.
- Do not edit the wiki (`../media-centaur.wiki/`) for this change — it has no user-visible feature surface beyond "the library now shows Mario as a movie." The bug fix is invisible from the user's mental model.
