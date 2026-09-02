# Title Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One app-wide TMDB title value (`MediaCentaur.TMDB.Title`) replaces `ReleaseTracking.TitleResult` and the watchlist's flat snapshot columns, rendered by one shared `title_summary` component with one poster ladder.

**Architecture:** `TMDB.Title` is an Ecto embedded schema in the TMDB adapter context; TMDB title search moves next to it (`TMDB.TitleSearch`). The `tracked?` decoration becomes a web-layer ref set (`ReleaseTracking.tracked_refs/0` → `tracked_refs` attr), like `watchlisted_refs`/`in_library_refs` already are. Watchlist rows embed the title (`embeds_one :title`), with a paired schema migration + idempotent data-migration backfill; the flat columns are dropped in a later release.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto embedded schemas on SQLite (`:map` column = JSON text), Phoenix Storybook (MC0009), `TmdbStubs` (`Req.Test`) for TMDB.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — unification decisions 1–5. This plan is layer 1a; the Discovery page (tab strip, `show_discovery`, `/discovery` routes) is plan 1b.

**House rules that bite here:** test-first (`automated-testing` skill); zero warnings; no real titles in fixtures; every component under `lib/media_centaur_web/components/**` needs a story (MC0009); loose attr types need `doc:` (MC0008); `<img>` carries `loading="eager" decoding="sync"` (MC0016) and local artwork goes through `sized_image_url/2` (MC0028); schema migrations never mutate rows (MC0015) — backfills are data migrations; commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `lib/media_centaur/tmdb/title.ex` | `TMDB.Title` embedded schema, `changeset/2`, `new!/1`, `ref/1` |
| Create | `lib/media_centaur/tmdb/title_search.ex` | `TMDB.TitleSearch.search/1` — multi/year search → `[Title.t()]` (moved from `ReleaseTracking.Acquisition`) |
| Modify | `lib/media_centaur/tmdb.ex` | export `Title`, `TitleSearch` |
| Delete | `lib/media_centaur/release_tracking/title_result.ex` | replaced |
| Modify | `lib/media_centaur/release_tracking/acquisition.ex` | drop search; `track_from_search/2` unchanged in behavior |
| Modify | `lib/media_centaur/release_tracking.ex` | drop `search_tmdb/1` + `TitleResult` export; add `tracked_refs/0` |
| Create | `lib/media_centaur_web/components/tmdb/title_summary.ex` | `title_summary/1` — poster thumb + identity line + secondary line |
| Modify | `lib/media_centaur_web/live_helpers.ex` | `title_poster_url/1` — the one poster ladder |
| Modify | `lib/media_centaur_web/components/acquisition/media_results.ex` | `Title` rows, `tracked_refs` attr, uses `title_summary` |
| Modify | `lib/media_centaur_web/live/incoming_live.ex` | search via `TitleSearch`, `tracked_refs` assign |
| Modify | `lib/media_centaur_web/live/incoming_live/plan_logic.ex` | `%Title{}` identity |
| Modify | `lib/media_centaur_web/components/acquisition/plan_modal.ex` | alias only |
| Create | `priv/repo/migrations/20260902120000_add_title_embed_to_watchlist_items.exs` | `add :title, :map` |
| Create | `priv/repo/data_migrations/20260902120100_backfill_watchlist_title_embed.exs` | JSON backfill from flat columns |
| Modify | `lib/media_centaur/discovery/watchlist_item.ex` | `embeds_one :title`; `create_changeset(title, attrs)` |
| Modify | `lib/media_centaur/discovery.ex` | `add_to_watchlist(%Title{}, attrs)`; Boundary dep on TMDB |
| Modify | `lib/media_centaur_web/components/discovery/watchlist_row.ex` | reads `item.title`, uses `title_summary` |
| Modify | `lib/media_centaur_web/live/watchlist_live.ex` | poster via `title_poster_url/1`, track via `item.title` |
| Modify | `lib/media_centaur_web/live/entity_modal.ex` | builds a `Title` for library subjects |
| Create/Modify | stories: `storybook/tmdb/_tmdb.index.exs`, `storybook/tmdb/title_summary.story.exs`, `storybook/acquisition/media_results.story.exs`, `storybook/acquisition/plan_modal.story.exs`, `storybook/discovery/watchlist_row.story.exs` | contracts |
| Create/Move | tests: `test/media_centaur/tmdb/title_test.exs`, `test/media_centaur/tmdb/title_search_test.exs`; update `release_tracking_test.exs`, `discovery_test.exs`, `watchlist_live_test.exs`, `media_results_test.exs`, `plan_logic_test.exs` | |

---

### Task 1: `MediaCentaur.TMDB.Title`

**Files:**
- Create: `lib/media_centaur/tmdb/title.ex`
- Modify: `lib/media_centaur/tmdb.ex:2-4`
- Test: `test/media_centaur/tmdb/title_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.TMDB.TitleTest do
  @moduledoc """
  Locks the contract of the app-wide TMDB title value: identity
  `(tmdb_id, media_type)` plus a render snapshot. `new!/1` is the
  enforced constructor — a missing identity or name crashes at the data
  layer instead of rendering a broken row.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Title

  describe "new!/1" do
    test "builds a title from identity + name, everything else nil" do
      title = Title.new!(%{tmdb_id: 1234, media_type: :movie, name: "Sample Movie"})

      assert %Title{tmdb_id: 1234, media_type: :movie, name: "Sample Movie"} = title
      assert title.year == nil
      assert title.release_date == nil
      assert title.poster_path == nil
      assert title.backdrop_path == nil
      assert title.overview == nil
    end

    test "carries the render snapshot when given" do
      title =
        Title.new!(%{
          tmdb_id: 1234,
          media_type: :tv_series,
          name: "Sample Show",
          year: "2010",
          release_date: ~D[2010-06-16],
          poster_path: "/abc.jpg",
          backdrop_path: "/bg.jpg",
          overview: "A sample overview."
        })

      assert title.year == "2010"
      assert title.release_date == ~D[2010-06-16]
      assert title.poster_path == "/abc.jpg"
      assert title.backdrop_path == "/bg.jpg"
      assert title.overview == "A sample overview."
    end

    test "raises when tmdb_id, media_type, or name is missing" do
      assert_raise ArgumentError, fn -> Title.new!(%{media_type: :movie, name: "Sample Movie"}) end
      assert_raise ArgumentError, fn -> Title.new!(%{tmdb_id: 1234, name: "Sample Movie"}) end
      assert_raise ArgumentError, fn -> Title.new!(%{tmdb_id: 1234, media_type: :movie}) end
    end

    test "rejects an unknown media_type" do
      assert_raise ArgumentError, fn ->
        Title.new!(%{tmdb_id: 1234, media_type: :book, name: "Sample"})
      end
    end
  end

  describe "changeset/2" do
    test "casts the whole snapshot and requires the identity + name" do
      changeset = Title.changeset(%Title{}, %{})
      refute changeset.valid?
      assert Keyword.keys(changeset.errors) == [:tmdb_id, :media_type, :name]
    end
  end

  describe "ref/1" do
    test "is the {tmdb_id, media_type} pair" do
      assert Title.ref(Title.new!(%{tmdb_id: 7, media_type: :movie, name: "Sample Movie")) == {7, :movie}
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/media_centaur/tmdb/title_test.exs`
Expected: compile error — `MediaCentaur.TMDB.Title` is not available.

- [ ] **Step 3: Write the schema**

Create `lib/media_centaur/tmdb/title.ex`:

```elixir
defmodule MediaCentaur.TMDB.Title do
  @moduledoc """
  The app-wide TMDB title value — a movie or show referenced by TMDB
  identity, whether or not the library owns it: search hits, tracked
  items, watchlist items, recommendations.

  Identity is `(tmdb_id, media_type)`; TMDB's movie and TV id spaces
  overlap, so neither half is enough alone. The remaining fields are a
  *render snapshot* cached at build time so any surface can paint the
  title without a TMDB call. `poster_path`/`backdrop_path` are TMDB
  paths, not URLs — `MediaCentaurWeb.LiveHelpers.title_poster_url/1`
  resolves them.

  No per-surface decoration lives here (tracked, on the watchlist, in
  the library); surfaces derive those from ref sets at render time.

  An embedded schema so rows can carry it verbatim (`embeds_one :title`)
  with one serialization; in-memory it is a plain struct built by
  `new!/1` or `changeset/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type media_type :: :movie | :tv_series

  @type t :: %__MODULE__{
          tmdb_id: integer(),
          media_type: media_type(),
          name: String.t(),
          year: String.t() | nil,
          release_date: Date.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil,
          overview: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :year, :string
    field :release_date, :date
    field :poster_path, :string
    field :backdrop_path, :string
    field :overview, :string
  end

  @fields [:tmdb_id, :media_type, :name, :year, :release_date, :poster_path, :backdrop_path, :overview]

  @doc "Casts a title from plain attrs; identity and name are required."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(title \\ %__MODULE__{}, attrs) do
    title
    |> cast(attrs, @fields)
    |> validate_required([:tmdb_id, :media_type, :name])
  end

  @doc """
  Builds a title from plain attrs, raising `ArgumentError` when the
  identity or name is missing or the media type is unknown — the
  enforced constructor every in-app builder uses.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case apply_action(changeset(attrs), :insert) do
      {:ok, title} -> title
      {:error, changeset} -> raise ArgumentError, "invalid TMDB title: #{inspect(changeset.errors)}"
    end
  end

  @doc "The `{tmdb_id, media_type}` identity pair — the key every ref set uses."
  @spec ref(t()) :: {integer(), media_type()}
  def ref(%__MODULE__{tmdb_id: tmdb_id, media_type: media_type}), do: {tmdb_id, media_type}
end
```

- [ ] **Step 4: Export it from the TMDB boundary**

In `lib/media_centaur/tmdb.ex` change the `exports:` list to:

```elixir
    exports: [Client, Confidence, Mapper, MetadataStats, RateLimiter, Title]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/media_centaur/tmdb/title_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/tmdb/title.ex lib/media_centaur/tmdb.ex test/media_centaur/tmdb/title_test.exs
git commit -m "feat(tmdb): TMDB.Title — the app-wide title value

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 2: `TMDB.TitleSearch` (search moves out of ReleaseTracking)

**Files:**
- Create: `lib/media_centaur/tmdb/title_search.ex`
- Create: `test/media_centaur/tmdb/title_search_test.exs`
- Modify: `test/media_centaur/release_tracking_test.exs:700-955` (move the two `search_tmdb/1` describe blocks)

The search body is a verbatim move of `ReleaseTracking.Acquisition.search_tmdb/1` and its private helpers (`multi_search`, `year_search`, `tag_media_type`, `normalize_*`, `presence`, `extract_year`, `extract_date`) minus the tracked decoration. Read `lib/media_centaur/release_tracking/acquisition.ex:22-143` before starting.

- [ ] **Step 1: Write the failing tests (moved)**

Create `test/media_centaur/tmdb/title_search_test.exs` by moving the `describe "search_tmdb/1"` block (`release_tracking_test.exs:700-837`) and `describe "search_tmdb/1 — trailing year in the query"` block (`:839-955`) into it, with these edits:

- module `MediaCentaur.TMDB.TitleSearchTest`, `use MediaCentaur.DataCase, async: false` (the stubs need the sandbox owner; keep whatever `use` line `release_tracking_test.exs` has), `alias MediaCentaur.TMDB.{Title, TitleSearch}`.
- every `ReleaseTracking.search_tmdb(` → `TitleSearch.search(`; every `%TitleResult{` → `%Title{`; describe names → `"search/1"` and `"search/1 — trailing year in the query"`.
- **Delete** the test at `:817-831` ("marks tracked results" — the one that calls `create_tracking_item` then asserts `hd(results).tracked? == true`). Its replacement is Task 3's `tracked_refs/0` test.
- keep the `stub_year_search/3` private helper with the block.

Remove both describe blocks from `release_tracking_test.exs`. Leave the `alias MediaCentaur.ReleaseTracking.TitleResult` line there for now if other tests in that file use it; Task 3 removes it.

- [ ] **Step 2: Run the new test to verify it fails**

Run: `mix test test/media_centaur/tmdb/title_search_test.exs`
Expected: compile error — `TitleSearch` undefined.

- [ ] **Step 3: Write `TitleSearch`**

Create `lib/media_centaur/tmdb/title_search.ex`:

```elixir
defmodule MediaCentaur.TMDB.TitleSearch do
  @moduledoc """
  TMDB title search — the one normalized `[Title.t()]` every
  title-search surface consumes (omnibox, track flow).

  Plain queries go to the multi endpoint, preserving TMDB's cross-type
  relevance order (a regrouped movies-then-tv merge once starved every
  TV result out of the capped omnibox dropdown). Person results are
  dropped.

  A trailing year ("Title 1999", "Title (1999)") never matches a TMDB
  title through the multi endpoint, so it is stripped and sent as the
  year filter of the per-type search endpoints instead, merged by
  popularity. A year that filters everything out (wrong year, or a
  number that is part of the title) falls back to a year-less multi
  search of the stripped title — the year is a disambiguator, never a
  gatekeeper.

  Pure adapter: no persistence, no decoration. Surfaces layer tracked /
  watchlisted / in-library state on via ref sets.
  """

  alias MediaCentaur.TMDB.{Client, Title}

  # A query ending in a standalone year, optionally parenthesized
  # ("Title 1999", "Title (1999)"). The title part must be non-empty —
  # a bare year is a title query ("1999" the film), not a filter.
  @trailing_year_query ~r/^(.+?)\s+\(?((?:19|20)\d{2})\)?$/

  @spec search(String.t()) :: [Title.t()]
  def search(query) do
    case Regex.run(@trailing_year_query, String.trim(query)) do
      [_full, title, year] -> year_search(title, String.to_integer(year))
      nil -> multi_search(query)
    end
  end

  defp multi_search(query) do
    case Client.search_multi(query) do
      {:ok, results} -> Enum.flat_map(results, &normalize_multi_result/1)
      {:error, _reason} -> []
    end
  end

  # The per-type endpoints carry no cross-type relevance rank, so the
  # merged list orders by TMDB popularity instead.
  defp year_search(title, year) do
    movie_results = tag_media_type(Client.search_movie(title, year), "movie")
    tv_results = tag_media_type(Client.search_tv(title, year), "tv")

    case movie_results ++ tv_results do
      [] ->
        multi_search(title)

      combined ->
        combined
        |> Enum.sort_by(&(&1["popularity"] || 0.0), :desc)
        |> Enum.flat_map(&normalize_multi_result/1)
    end
  end

  defp tag_media_type({:ok, results}, media_type),
    do: Enum.map(results, &Map.put(&1, "media_type", media_type))

  defp tag_media_type({:error, _reason}, _media_type), do: []

  defp normalize_multi_result(%{"media_type" => "movie"} = tmdb), do: [normalize_movie_result(tmdb)]
  defp normalize_multi_result(%{"media_type" => "tv"} = tmdb), do: [normalize_tv_result(tmdb)]
  defp normalize_multi_result(_person_or_unknown), do: []

  defp normalize_movie_result(tmdb) do
    Title.new!(%{
      tmdb_id: tmdb["id"],
      media_type: :movie,
      name: tmdb["title"],
      year: extract_year(tmdb["release_date"]),
      release_date: extract_date(tmdb["release_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: presence(tmdb["overview"])
    })
  end

  defp normalize_tv_result(tmdb) do
    Title.new!(%{
      tmdb_id: tmdb["id"],
      media_type: :tv_series,
      name: tmdb["name"],
      year: extract_year(tmdb["first_air_date"]),
      release_date: extract_date(tmdb["first_air_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: presence(tmdb["overview"])
    })
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(text) when is_binary(text), do: text

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _::binary>>), do: year

  # Full date, not just the year — the results' upcoming/released scoping
  # compares against today. TMDB leaves unreleased titles undated or with
  # partial strings; both come through as nil.
  defp extract_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp extract_date(_missing), do: nil
end
```

Note: a TMDB hit missing its id or title is dropped with a debug log rather than raising — `@enforce_keys` on the old struct only checked key presence, so the old code rendered a blank row; dropping is the chosen policy (review of Task 2, 2026-09-02).

- [ ] **Step 4: Export it, run both test files**

In `lib/media_centaur/tmdb.ex` the `exports:` list becomes `[Client, Confidence, Mapper, MetadataStats, RateLimiter, Title, TitleSearch]`.

Run: `mix test test/media_centaur/tmdb/title_search_test.exs test/media_centaur/release_tracking_test.exs`
Expected: all pass (the moved tests now exercise `TitleSearch`; `release_tracking_test` still compiles because `search_tmdb/1` still exists until Task 3).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb.ex lib/media_centaur/tmdb/title_search.ex test/media_centaur/tmdb/title_search_test.exs test/media_centaur/release_tracking_test.exs
git commit -m "refactor(tmdb): TitleSearch — title search moves next to TMDB.Title

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 3: `ReleaseTracking.tracked_refs/0`; retire `TitleResult` and `search_tmdb/1`

**Files:**
- Modify: `lib/media_centaur/release_tracking.ex` (lines 14, 251-252)
- Modify: `lib/media_centaur/release_tracking/acquisition.ex` (lines 1-143, 154-158)
- Delete: `lib/media_centaur/release_tracking/title_result.ex`, `test/media_centaur/release_tracking/title_result_test.exs`
- Test: `test/media_centaur/release_tracking_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/release_tracking_test.exs`, next to the other `describe` blocks (after the tracking-item CRUD describes; anywhere before the end is fine):

```elixir
  describe "tracked_refs/0" do
    test "is the {tmdb_id, media_type} set of every tracked item" do
      assert ReleaseTracking.tracked_refs() == MapSet.new()

      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Sample Show"})
      create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      assert ReleaseTracking.tracked_refs() == MapSet.new([{200, :tv_series}, {777, :movie}])
    end
  end
```

(`create_tracking_item/1` is the factory the file already uses at `:818`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/media_centaur/release_tracking_test.exs --only describe:"tracked_refs/0"`
Expected: FAIL — `ReleaseTracking.tracked_refs/0` is undefined.

- [ ] **Step 3: Add `tracked_refs/0`, remove `search_tmdb/1`**

In `lib/media_centaur/release_tracking.ex` replace lines 251-252

```elixir
  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.search_tmdb/1`."
  def search_tmdb(query), do: Acquisition.search_tmdb(query)
```

with

```elixir
  @doc """
  The `{tmdb_id, media_type}` ref set of every tracked item — bulk
  decoration for title rows (the Tracked marker on search results).
  """
  @spec tracked_refs() :: MapSet.t({integer(), :movie | :tv_series})
  def tracked_refs do
    MapSet.new(Repo.all(from(i in Item, select: {i.tmdb_id, i.media_type})))
  end
```

(`Repo`, `Item`, and `import Ecto.Query` are already in scope in that module — confirm with `grep -n "import Ecto.Query\|alias.*Item" lib/media_centaur/release_tracking.ex`.)

Remove `TitleResult,` from the `exports:` list at line 14.

- [ ] **Step 4: Strip the search from `Acquisition`**

In `lib/media_centaur/release_tracking/acquisition.ex`:

- Moduledoc: replace the first paragraph with
  ```
  Track-from-search onboarding for release tracking
  (`track_from_search/2`, `track_from_search_async/2`). Title search
  itself lives in `MediaCentaur.TMDB.TitleSearch`.
  ```
- Delete everything from `# --- Search ---` (line 22) through the end of `extract_date/1` (line 143), i.e. `@trailing_year_query`, `search_tmdb/1`, `multi_search/1`, `year_search/2`, `tag_media_type/2`, `normalize_*`, `presence/1`, `extract_year/1`, `extract_date/1`.
- Change the alias line to `alias MediaCentaur.ReleaseTracking.{Extractor, Helpers, Release, Wants}` and drop `import Ecto.Query` and `alias MediaCentaur.Repo` **only if** nothing else in the file uses them (`grep -n "from(\|Repo\." lib/media_centaur/release_tracking/acquisition.ex`). `Item` is used by `track_from_search`'s callee? — it is not; drop it from the alias if the compiler warns.
- `track_from_search/2` doc: replace "Accepts a result map (%{tmdb_id, media_type, name, poster_path})" with "Accepts anything carrying `tmdb_id`, `media_type` and `name` — a `MediaCentaur.TMDB.Title` in practice".

- [ ] **Step 5: Delete the struct and its test**

```bash
git rm lib/media_centaur/release_tracking/title_result.ex test/media_centaur/release_tracking/title_result_test.exs
```

Remove `alias MediaCentaur.ReleaseTracking.TitleResult` from `test/media_centaur/release_tracking_test.exs:7` (nothing else in that file references it once the search blocks moved — verify with `grep -n TitleResult test/media_centaur/release_tracking_test.exs`).

- [ ] **Step 6: Compile and run the context tests**

Run: `mix compile --warnings-as-errors 2>&1 | tail -20`
Expected: errors only in the **web** layer and stories/tests that still reference `TitleResult` / `search_tmdb` (fixed in Task 4). If there are none, good.

Run: `mix test test/media_centaur/release_tracking_test.exs test/media_centaur/tmdb`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add -A lib/media_centaur/release_tracking lib/media_centaur/release_tracking.ex test/media_centaur/release_tracking_test.exs test/media_centaur/release_tracking
git commit -m "refactor(release-tracking): tracked_refs/0 replaces the TitleResult tracked flag

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 4: Web layer — `Title` rows and `tracked_refs`

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex`
- Modify: `lib/media_centaur_web/live/incoming_live.ex` (lines ~213, 470-500, 964, 1626, 1720-1733, 2393-2420)
- Modify: `lib/media_centaur_web/live/incoming_live/plan_logic.ex:19,339,345,366`
- Modify: `lib/media_centaur_web/components/acquisition/plan_modal.ex` (alias if present; `attr :identity` doc)
- Modify: `storybook/acquisition/media_results.story.exs`, `storybook/acquisition/plan_modal.story.exs`
- Tests: `test/media_centaur_web/components/acquisition/media_results_test.exs`, `test/media_centaur_web/live/incoming_live/plan_logic_test.exs`, `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Update the unit tests first**

`test/media_centaur_web/components/acquisition/media_results_test.exs`: replace the alias and helper (lines 9-20) with

```elixir
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  @today ~D[2026-08-02]

  defp title(tmdb_id, release_date) do
    Title.new!(%{
      tmdb_id: tmdb_id,
      media_type: :movie,
      name: "Sample Movie #{tmdb_id}",
      release_date: release_date
    })
  end
```

and rename every `title_result(` call to `title(`; every `%TitleResult{` pattern to `%Title{`.

`test/media_centaur_web/live/incoming_live/plan_logic_test.exs`: at `:308` and `:387` replace the `TitleResult` aliases with `alias MediaCentaur.TMDB.Title` (and `as: LockupTitle` for the second if the file needs the distinct name); `struct!(TitleResult, %{...})` → `Title.new!(%{...})`; `struct!(LockupTitleResult, ...)` → `Title.new!(...)`. The `tracked?: false` keys at `:17, :97, :336, :349, :408, :453` belong to `Targeting.Selection`/`Episode` and stay.

Add a LiveView test to `test/media_centaur_web/live/incoming_live_test.exs`, inside the describe block that holds the existing "pick marks the row as tracked" test (`grep -n "Tracked" test/media_centaur_web/live/incoming_live_test.exs`; it types via `form("form[phx-change='omnibox_change']", %{query: ...}) |> render_change()` then `render_async(view, 2_000)` — mirror that exactly, including its `setup` stubs and `live_async!/2`):

```elixir
    test "an already-tracked title carries the Tracked marker from the ref set", %{conn: conn} do
      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Sample Show"})

      MediaCentaur.TmdbStubs.stub_search_multi([
        %{"id" => 200, "media_type" => "tv", "name" => "Sample Show", "first_air_date" => "2025-01-01"},
        %{"id" => 777, "media_type" => "movie", "title" => "Sample Movie", "release_date" => "2020-01-01"}
      ])

      {:ok, view, _html} = live_async!(conn, ~p"/incoming")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view, 2_000)

      assert view |> element("#omnibox-result-tv_series-200") |> render() =~ "Tracked"
      refute view |> element("#omnibox-result-movie-777") |> render() =~ "Tracked"
    end
```

The existing test that picks a row and asserts `html =~ "Tracked"` keeps passing because `track_picked_result/2` now adds the ref to `tracked_refs` (Step 4). `create_tracking_item/1` comes from `MediaCentaur.TestFactory` (`test/support/factory.ex`), already imported in that file.

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/media_centaur_web/components/acquisition/media_results_test.exs test/media_centaur_web/live/incoming_live/plan_logic_test.exs`
Expected: compile errors in `media_results.ex`/`plan_logic.ex` (`TitleResult` gone).

- [ ] **Step 3: `MediaResults` — `Title` + `tracked_refs`**

In `lib/media_centaur_web/components/acquisition/media_results.ex`:

- `alias MediaCentaur.ReleaseTracking.TitleResult` → `alias MediaCentaur.TMDB.Title`
- `attr :results, :list, required: true, doc: "\`Title.t()\` rows, TMDB relevance order."`
- after `attr :in_library_refs` add:
  ```elixir
  attr :tracked_refs, :any,
    default: MapSet.new(),
    doc: "`{tmdb_id, media_type}` refs release tracking holds an open item for — the Tracked marker."
  ```
- in the `<.result_row :for=...>` call add `tracked?={MapSet.member?(@tracked_refs, {result.tmdb_id, result.media_type})}`
- on `result_row`: `attr :result, Title, required: true` and add
  ```elixir
  attr :tracked?, :boolean,
    required: true,
    doc: "Whether release tracking already holds this title — the Tracked marker, and no verb when upcoming."
  ```
- `assign(assigns, :verb, verb(assigns.tracked?, assigns.status, assigns.release_mode_available))`
- template: `<span :if={@result.tracked?} ...>Tracked</span>` → `<span :if={@tracked?} ...>Tracked</span>`
- `verb/3` heads become:
  ```elixir
  defp verb(true, :upcoming, _release_mode_available), do: nil
  defp verb(false, :upcoming, _release_mode_available), do: "Track release"
  defp verb(_tracked?, :released, true), do: "Download"
  defp verb(_tracked?, :released, false), do: "Track"
  ```
- `@spec scope([Title.t()], ...)`; `release_status/2` doc: "(`Title`, `WatchlistItem.title`)".

(The poster/identity markup is replaced by `title_summary` in Task 5; leave it as-is now.)

- [ ] **Step 4: `IncomingLive`**

- Line 1626: `ReleaseTracking.search_tmdb(trimmed)` → `TitleSearch.search(trimmed)`; add `alias MediaCentaur.TMDB.TitleSearch` to the module's alias block.
- Mount assigns (line ~213, the block with `omnibox_results: []`): add `tracked_refs: MapSet.new(),`.
- `handle_async(:omnibox_search, {:ok, {query, results}}, socket)` (line ~2393): in the `assign(socket, ...)` add `tracked_refs: ReleaseTracking.tracked_refs(),` next to `in_library_refs`.
- `track_picked_result/2` (line ~496-500): replace the `omnibox_results: Enum.map(... %{row | tracked?: true} ...)` assign with
  ```elixir
        assign(socket, tracked_refs: MapSet.put(socket.assigns.tracked_refs, {result.tmdb_id, result.media_type}))
  ```
  and the `track_from_search_async` call above it passes `result` directly (it is a `%Title{}`):
  ```elixir
        ReleaseTracking.track_from_search_async(result, scope)
  ```
- Render (line ~964): add `tracked_refs={@tracked_refs}` to `<MediaResults.media_results ...>`.
- Lines 1720-1733 (`watchlist_toggle`): leave for Task 6.

- [ ] **Step 5: `PlanLogic` and `PlanModal`**

`plan_logic.ex`: `alias MediaCentaur.ReleaseTracking.TitleResult` → `alias MediaCentaur.TMDB.Title`; the three `%TitleResult{}` patterns (`:339`, `:345`, `:366`) → `%Title{}`.

`plan_modal.ex`: `attr :identity, :any` at `:70` — update its `doc:` text to name `TMDB.Title` if it names `TitleResult`; no other change (the `tracked?` uses at `:256`, `:335`, `:429` are `Targeting.Selection`/`Episode` fields).

- [ ] **Step 6: Stories**

`storybook/acquisition/media_results.story.exs`: alias → `MediaCentaur.TMDB.Title`; each `%TitleResult{...}` → `%Title{...}` with the `tracked?: true` lines removed; add `tracked_refs: MapSet.new([{246_810, :tv_series}, {779, :tv_series}])` to the `:results` and `:scoped_upcoming` variations' attributes (those are the two that showed the tracked rows); update the `:results` description's "tracked marker" wording only if it becomes wrong (it does not).

`storybook/acquisition/plan_modal.story.exs`: alias → `MediaCentaur.TMDB.Title`; `%TitleResult{` → `%Title{`.

- [ ] **Step 7: Compile, run the touched tests and the storybook tests**

Run: `mix compile --warnings-as-errors && mix test test/media_centaur_web/components/acquisition test/media_centaur_web/live/incoming_live test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass. Storybook test filenames: confirm with `ls test/media_centaur_web/ | grep storybook`.

- [ ] **Step 8: Commit**

```bash
git add -A lib/media_centaur_web storybook test/media_centaur_web
git commit -m "refactor(web): search rows are TMDB.Title; Tracked marker via tracked_refs

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 5: `title_summary` component and the poster ladder

**Files:**
- Create: `lib/media_centaur_web/components/tmdb/title_summary.ex`
- Modify: `lib/media_centaur_web/live_helpers.ex` (add `title_poster_url/1` after `tmdb_cdn_url/2`, ~line 166)
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex` (result_row markup)
- Create: `storybook/tmdb/_tmdb.index.exs`, `storybook/tmdb/title_summary.story.exs`
- Test: create `test/media_centaur_web/components/tmdb/title_summary_test.exs`; modify `test/media_centaur_web/live_helpers_test.exs`

- [ ] **Step 1: Write the failing tests**

`test/media_centaur_web/components/tmdb/title_summary_test.exs`:

```elixir
defmodule MediaCentaurWeb.Components.TMDB.TitleSummaryTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias MediaCentaur.TMDB.Title

  defp title(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", overview: "A sample overview."},
        overrides
      )
    )
  end

  test "renders name, quiet type/year text, and the overview" do
    html =
      render_component(&MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary/1,
        title: title(),
        poster_url: nil
      )

    assert html =~ "Sample Movie"
    assert html =~ "Movie"
    assert html =~ "2010"
    assert html =~ "A sample overview."
    assert html =~ "hero-film-mini"
  end

  test "a TV title shows the TV icon fallback and no year when absent" do
    html =
      render_component(&MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary/1,
        title: title(%{media_type: :tv_series, year: nil}),
        poster_url: nil
      )

    assert html =~ "hero-tv-mini"
    refute html =~ "· "
  end

  test "a poster url replaces the icon with an eager, sync image" do
    html =
      render_component(&MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary/1,
        title: title(),
        poster_url: "https://image.tmdb.org/t/p/w92/p.jpg"
      )

    assert html =~ ~s(src="https://image.tmdb.org/t/p/w92/p.jpg")
    assert html =~ ~s(loading="eager")
    assert html =~ ~s(decoding="sync")
    refute html =~ "hero-film-mini"
  end

  test "the secondary slot displaces the overview; markers render on the identity line" do
    assigns = %{title: title()}

    html =
      rendered_to_string(~H"""
      <MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary title={@title} poster_url={nil}>
        <:markers><span>Tracked</span></:markers>
        <:secondary>Why it is here</:secondary>
      </MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary>
      """)

    assert html =~ "Tracked"
    assert html =~ "Why it is here"
    refute html =~ "A sample overview."
  end
end
```

`test/media_centaur_web/live_helpers_test.exs` — add (or create the module with) this describe:

```elixir
  describe "title_poster_url/1" do
    alias MediaCentaur.TMDB.Title

    test "hotlinks TMDB when the artwork cache holds nothing for the identity" do
      title = Title.new!(%{tmdb_id: 999_999_001, media_type: :movie, name: "Sample Movie", poster_path: "/p.jpg"})
      assert title_poster_url(title) == "https://image.tmdb.org/t/p/w92/p.jpg"
    end

    test "is nil when there is neither cached artwork nor a poster path" do
      title = Title.new!(%{tmdb_id: 999_999_002, media_type: :tv_series, name: "Sample Show"})
      assert title_poster_url(title) == nil
    end
  end
```

(The file exists and already does `import MediaCentaurWeb.LiveHelpers`, so the calls are unqualified. `TmdbArtwork.urls/2` only stats the filesystem, so `ExUnit.Case` without a DB sandbox is fine. The cached-tier branch is covered by the watchlist LiveView test in Task 6; do not stub the filesystem here.)

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/media_centaur_web/components/tmdb test/media_centaur_web/live_helpers_test.exs`
Expected: FAIL — module / function undefined.

- [ ] **Step 3: The poster ladder helper**

In `lib/media_centaur_web/live_helpers.ex`, after `tmdb_cdn_url/2` (line ~166), add:

```elixir
  @doc """
  The `src` a title thumb paints: the local cached tier when
  `TmdbArtwork` holds the identity, the TMDB hotlink otherwise, nil when
  the title carries no poster path either. Hosts resolve this once per
  row; `title_summary/1` sizes it.
  """
  @spec title_poster_url(MediaCentaur.TMDB.Title.t()) :: String.t() | nil
  def title_poster_url(%MediaCentaur.TMDB.Title{} = title) do
    MediaCentaur.TmdbArtwork.urls(title.media_type, title.tmdb_id).poster_url ||
      tmdb_cdn_url(title.poster_path, :w92)
  end
```

(`TmdbArtwork.urls/2` is filesystem-only — no DB read, so render-time calls stay inside the no-DB-on-render budget.)

- [ ] **Step 4: The component**

Create `lib/media_centaur_web/components/tmdb/title_summary.ex`:

```elixir
defmodule MediaCentaurWeb.Components.TMDB.TitleSummary do
  @moduledoc """
  The one identity block for a TMDB title that is not necessarily a
  library entry: poster thumb, name, quiet type/year text, and a
  secondary line (the overview by default). Search rows, watchlist rows
  and feed rows render this and add their own decorations through the
  `markers` slot (Tracked, In library) and the `secondary` slot (a
  watchlist note). Owns no state and no actions; renders as spans so a
  host may wrap it in a button or a link.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.TMDB.Title

  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`; nil shows the icon fallback"

  slot :markers, doc: "quiet text markers after the type/year (Tracked, In library)"
  slot :secondary, doc: "displaces the overview line — a watchlist note, a friend's reason"

  def title_summary(assigns) do
    ~H"""
    <span class="flex min-w-0 flex-1 items-start gap-4" data-component="title-summary">
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <%!-- The thumb paints at 48 CSS px (96 device px on the 4K 2×
              compose) — 160 is the shared thumb derivative width, so
              local artwork reuses the warm derivative; hotlinked TMDB
              urls pass through `sized_image_url/2` untouched. --%>
        <img
          :if={@poster_url}
          src={sized_image_url(@poster_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <.icon
          :if={!@poster_url}
          name={if @title.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>

      <span class="min-w-0 flex-1 space-y-0.5 self-center">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm font-semibold">{@title.name}</span>
          <%!-- Quiet text, not colored chips — type is metadata; color
                stays reserved for interaction and state. --%>
          <span class="shrink-0 text-xs text-base-content/50">
            {if @title.media_type == :movie, do: "Movie", else: "TV"}<span :if={@title.year}> · {@title.year}</span>
          </span>
          {render_slot(@markers)}
        </span>
        <span :if={@secondary != []} class="line-clamp-2 block text-xs leading-relaxed text-base-content/55">
          {render_slot(@secondary)}
        </span>
        <span
          :if={@secondary == [] && @title.overview}
          class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
        >
          {@title.overview}
        </span>
      </span>
    </span>
    """
  end
end
```

- [ ] **Step 5: `MediaResults` renders through it**

In `media_results.ex`:

- imports: drop `import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]`; add `import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]` and `import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]`. Keep the `icon` import (the chevron and bookmark still use it).
- In `result_row`, replace the block from `<span class="flex h-[72px] ...">` through the closing `</span>` of the text column (i.e. everything between the opening `<button ... data-nav-item tabindex="0">` and the `<span :if={@verb} ...>` verb span) with:

```heex
        <.title_summary title={@result} poster_url={title_poster_url(@result)}>
          <:markers>
            <span :if={@tracked?} class="shrink-0 text-xs text-success/70">Tracked</span>
            <%!-- Quiet neutral, deliberately unlike Tracked's success tint —
                in-library is metadata here, not a state this page owns. --%>
            <span :if={@in_library?} class="shrink-0 text-xs text-base-content/50">In library</span>
          </:markers>
        </.title_summary>
```

- [ ] **Step 6: Story + index**

`storybook/tmdb/_tmdb.index.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.TMDB do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "clapperboard", :light, "psb:mr-1"}

  def entry("title_summary"), do: [icon: {:fa, "id-card", :thin}, name: "Title summary"]
end
```

`storybook/tmdb/title_summary.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.TMDB.TitleSummary do
  @moduledoc """
  The one identity block for a TMDB title — poster thumb, name, quiet
  type/year text, overview — that search rows, watchlist rows and feed
  rows share. Surfaces add markers (Tracked, In library) and may
  displace the overview with a note. `poster_url: nil` shows the icon
  fallback.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary/1
  def render_source, do: :function
  def layout, do: :one_column

  defp title(overrides) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          release_date: ~D[2010-03-05],
          overview: "A sample movie overview that confirms this is the title you meant."
        },
        overrides
      )
    )
  end

  def variations do
    [
      %Variation{
        id: :movie,
        description: "A movie with no cached art — the film icon fallback, name, Movie · year, overview.",
        attributes: %{title: title(%{}), poster_url: nil}
      },
      %Variation{
        id: :show_no_year,
        description: "A show without a year — the TV icon and no dangling separator.",
        attributes: %{
          title: title(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show", year: nil, overview: nil}),
          poster_url: nil
        }
      },
      %Variation{
        id: :with_poster,
        description: "With art the placeholder gives way to the eager+sync poster thumb (the bundled sample poster).",
        attributes: %{title: title(%{}), poster_url: "/images/sample-nosferatu-poster.jpg"}
      },
      %Variation{
        id: :markers,
        description: "Surface decorations ride the identity line — the Tracked and In library markers as search rows render them.",
        attributes: %{title: title(%{}), poster_url: nil},
        slots: [
          ~s|<:markers><span class="shrink-0 text-xs text-success/70">Tracked</span><span class="shrink-0 text-xs text-base-content/50">In library</span></:markers>|
        ]
      },
      %Variation{
        id: :secondary,
        description: "A secondary line displaces the overview — a watchlist note is why the title is here.",
        attributes: %{title: title(%{}), poster_url: nil},
        slots: [~s|<:secondary>Recommended after movie night — the sequel to the one we liked.</:secondary>|]
      },
      %Variation{
        id: :long_name,
        description: "A long name truncates; the type/year text never wraps.",
        attributes: %{
          title: title(%{name: "Sample Movie Returns: An Extraordinarily Long Title That Truncates"}),
          poster_url: nil
        }
      }
    ]
  end
end
```

- [ ] **Step 7: Run the tests, storybook tests, and format**

Run: `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/components test/media_centaur_web/live_helpers_test.exs test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add -A lib/media_centaur_web storybook test/media_centaur_web
git commit -m "feat(web): title_summary — one identity block and one poster ladder for TMDB titles

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 6: Watchlist rows embed the title

**Files:**
- Create: `priv/repo/migrations/20260902120000_add_title_embed_to_watchlist_items.exs`
- Create: `priv/repo/data_migrations/20260902120100_backfill_watchlist_title_embed.exs`
- Modify: `lib/media_centaur/discovery/watchlist_item.ex`, `lib/media_centaur/discovery.ex`
- Modify: `lib/media_centaur_web/components/discovery/watchlist_row.ex`, `lib/media_centaur_web/live/watchlist_live.ex`, `lib/media_centaur_web/live/entity_modal.ex:1166-1173`, `lib/media_centaur_web/live/incoming_live.ex:1720-1733`
- Modify: `storybook/discovery/watchlist_row.story.exs`
- Tests: `test/media_centaur/discovery_test.exs`, `test/media_centaur_web/live/watchlist_live_test.exs`, `test/media_centaur/data_migrations_test.exs`, create `test/media_centaur/repo/data_migrations/backfill_watchlist_title_embed_test.exs`

- [ ] **Step 1: Update the context tests first**

`test/media_centaur/discovery_test.exs`:

- add `alias MediaCentaur.TMDB.Title`
- replace the `describe "WatchlistItem.create_changeset/1"` block with:

```elixir
  describe "WatchlistItem.create_changeset/2" do
    test "embeds the title and derives the identity columns from it" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010"})
      changeset = WatchlistItem.create_changeset(title, %{note: "why"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tmdb_id) == 777
      assert Ecto.Changeset.get_change(changeset, :media_type) == :movie
      assert Ecto.Changeset.get_change(changeset, :note) == "why"
      assert %Title{name: "Sample Movie"} = Ecto.Changeset.get_embed(changeset, :title, :struct)
    end

    test "rejects an unknown source" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      changeset = WatchlistItem.create_changeset(title, %{source: :carrier_pigeon})
      refute changeset.valid?
      assert %{source: _} = errors_on(changeset)
    end
  end
```

- in `describe "watchlist"`, replace `@attrs %{...}` with
  ```elixir
    @title Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", poster_path: "/p.jpg"})
  ```
  and every `Discovery.add_to_watchlist(@attrs)` → `Discovery.add_to_watchlist(@title)`; the second-item add at `:73` → `Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"}))`.
- add one test to the block:
  ```elixir
    test "the stored row reads back its title snapshot" do
      {:ok, item} = Discovery.add_to_watchlist(@title, %{note: "why"})
      assert %WatchlistItem{title: %Title{tmdb_id: 777, name: "Sample Movie", year: "2010", poster_path: "/p.jpg"}, note: "why"} =
               Repo.get!(WatchlistItem, item.id)

      await_supervised_tasks()
    end
  ```
  (`Repo` — check the file aliases `MediaCentaur.Repo`; `DataCase` usually provides it. Add `alias MediaCentaur.Repo` if not.)

`test/media_centaur_web/live/watchlist_live_test.exs`: add `alias MediaCentaur.TMDB.Title`; every `Discovery.add_to_watchlist(%{...})` → `Discovery.add_to_watchlist(Title.new!(%{...}))` (same attrs).

`test/media_centaur/data_migrations_test.exs`: add a structural test next to the existing directory test:

```elixir
    test "directory contains the watchlist title-embed backfill" do
      files = DataMigrations.path() |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".exs"))
      assert "20260902120100_backfill_watchlist_title_embed.exs" in files
    end
```

Create `test/media_centaur/repo/data_migrations/backfill_watchlist_title_embed_test.exs` (the same shape as the sibling `rename_watch_dirs_settings_key_test.exs`; the migration module is loaded by `test_helper.exs`). It proves the SQL's JSON shape is what Ecto's embed loader expects by reading the row back through the schema:

```elixir
defmodule MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbedTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbed
  alias MediaCentaur.TMDB.Title

  setup do
    MediaCentaur.TmdbStubs.setup_tmdb_client()
  end

  # A pre-embed row: the flat snapshot columns filled, `title` NULL.
  # New rows only write `name`, so the other flat columns are set by hand.
  defp insert_legacy_row do
    {:ok, item} = Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    Repo.query!(
      "UPDATE watchlist_items SET title = NULL, year = '2010', release_date = '2010-03-05', " <>
        "poster_path = '/p.jpg', overview = 'A sample overview.' WHERE tmdb_id = 777"
    )

    await_supervised_tasks()
    item.id
  end

  describe "backfill/1" do
    test "rebuilds the embedded title from the flat columns" do
      id = insert_legacy_row()

      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      assert %WatchlistItem{
               title: %Title{
                 tmdb_id: 777,
                 media_type: :movie,
                 name: "Sample Movie",
                 year: "2010",
                 release_date: ~D[2010-03-05],
                 poster_path: "/p.jpg",
                 backdrop_path: nil,
                 overview: "A sample overview."
               }
             } = Repo.get!(WatchlistItem, id)
    end

    test "is idempotent — a filled row is left alone" do
      id = insert_legacy_row()
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      Repo.query!("UPDATE watchlist_items SET name = 'Renamed' WHERE tmdb_id = 777")
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      assert %WatchlistItem{title: %Title{name: "Sample Movie"}} = Repo.get!(WatchlistItem, id)
    end

    test "no-op on an empty table" do
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)
    end
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/media_centaur/discovery_test.exs test/media_centaur_web/live/watchlist_live_test.exs test/media_centaur/data_migrations_test.exs test/media_centaur/repo/data_migrations`
Expected: FAIL — `create_changeset/2` undefined, `add_to_watchlist/1` pattern mismatch, migration module missing.

- [ ] **Step 3: Schema migration**

Create `priv/repo/migrations/20260902120000_add_title_embed_to_watchlist_items.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.AddTitleEmbedToWatchlistItems do
  @moduledoc """
  Watchlist rows carry their TMDB title as one embedded value
  (`MediaCentaur.TMDB.Title`, JSON in a `:map` column) instead of five
  flat snapshot columns. The identity columns (`tmdb_id`, `media_type`)
  stay for the unique index and are derived from the embed on write.

  Paired with the `BackfillWatchlistTitleEmbed` data migration, which
  fills `title` from the flat columns. The flat snapshot columns
  (`name`, `year`, `release_date`, `poster_path`, `overview`) are dropped
  by a later release's migration once every install has backfilled;
  until then `name` (NOT NULL) is still written from the embed.
  """
  use Ecto.Migration

  def change do
    alter table(:watchlist_items) do
      add :title, :map
    end
  end
end
```

- [ ] **Step 4: Data migration**

Create `priv/repo/data_migrations/20260902120100_backfill_watchlist_title_embed.exs`:

```elixir
defmodule MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbed do
  @moduledoc """
  Fills `watchlist_items.title` (the embedded `TMDB.Title` JSON) from
  the flat snapshot columns for rows created before the embed existed.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: only rows whose `title` is NULL are touched. The JSON key
  set mirrors the embedded schema's fields exactly (`backdrop_path` was
  never a flat column, so it is NULL). `release_date` is stored as an
  ISO-8601 TEXT by the SQLite adapter, which is also how Ecto dumps a
  `:date` inside an embed, so the value copies through unchanged.
  """
  use Ecto.Migration

  @backfill """
  UPDATE watchlist_items
  SET title = json_object(
    'tmdb_id', tmdb_id,
    'media_type', media_type,
    'name', name,
    'year', year,
    'release_date', release_date,
    'poster_path', poster_path,
    'backdrop_path', NULL,
    'overview', overview
  )
  WHERE title IS NULL
  """

  def up, do: backfill(repo())

  def down, do: :ok

  @doc "Backfill body, exposed for direct testing. Idempotent."
  def backfill(repo) do
    repo.query!(@backfill)
    :ok
  end
end
```

- [ ] **Step 5: `WatchlistItem`**

Replace `lib/media_centaur/discovery/watchlist_item.ex` with:

```elixir
defmodule MediaCentaur.Discovery.WatchlistItem do
  @moduledoc """
  Title-level "I want to watch this" intent — an embedded
  `MediaCentaur.TMDB.Title` plus provenance.

  Identity is `(tmdb_id, media_type)`, kept as indexed columns and
  derived from the embedded title on write so there is one write path
  (`create_changeset/2`) and one read path (`item.title`). The library is
  never referenced from here — presence is derived at read time via
  `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:friend`, `:import`, …); directed recommendations later add nullable
  sender/recipient columns — no dead columns until then.

  The flat `name` column is transitional: NOT NULL until the
  drop-flat-columns migration lands in a later release, so it is still
  written from the embed. Nothing reads it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watchlist_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    embeds_one :title, Title, on_replace: :update
    field :source, Ecto.Enum, values: [:manual], default: :manual
    field :note, :string

    timestamps()
  end

  @doc "A new row for `title`; `attrs` may carry `:source` and `:note`."
  @spec create_changeset(Title.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Title{} = title, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:source, :note])
    |> put_embed(:title, title)
    |> put_change(:tmdb_id, title.tmdb_id)
    |> put_change(:media_type, title.media_type)
    |> put_change(:name, title.name)
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type])
  end
end
```

- [ ] **Step 6: `Discovery` context**

In `lib/media_centaur/discovery.ex`:

- Boundary: `deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork, MediaCentaur.TMDB]`.
- Moduledoc: replace the "Accepts plain attrs at the boundary … Scheduled convergence: …" paragraph with:
  ```
  Accepts `MediaCentaur.TMDB.Title` at the boundary — the app-wide title
  value every candidate source produces (converged 2026-09-02; see
  docs/superpowers/specs/2026-09-02-friends-recommendations-design.md).
  ```
- add `alias MediaCentaur.TMDB.Title`.
- replace `add_to_watchlist/1` with:

```elixir
  @doc """
  Adds a title to the watchlist. `attrs` may carry `:source` and
  `:note`. Idempotent — re-adding an existing `(tmdb_id, media_type)`
  returns the existing item unchanged, including when a concurrent
  insert wins the race (unique-constraint branch).
  """
  @spec add_to_watchlist(Title.t(), map()) :: {:ok, WatchlistItem.t()} | {:error, Ecto.Changeset.t()}
  def add_to_watchlist(%Title{} = title, attrs \\ %{}) do
    case get_item(title.tmdb_id, title.media_type) do
      %WatchlistItem{} = existing ->
        {:ok, existing}

      nil ->
        title
        |> WatchlistItem.create_changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, item} ->
            ensure_artwork_async(item)

            Events.broadcast(%Events.ItemAdded{
              item_id: item.id,
              tmdb_id: item.tmdb_id,
              media_type: item.media_type
            })

            {:ok, item}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # Concurrent add won the race exactly when a unique constraint
            # fired (constraint metadata, not field name — a future
            # validation on :tmdb_id must not be mistaken for the race);
            # re-fetch so idempotency holds under contention too.
            unique_violation? =
              Enum.any?(errors, fn {_field, {_msg, meta}} -> meta[:constraint] == :unique end)

            if unique_violation?,
              do: {:ok, get_item(title.tmdb_id, title.media_type)},
              else: {:error, changeset}
        end
    end
  end
```

- [ ] **Step 7: Callers build a `Title`**

`lib/media_centaur_web/live/incoming_live.ex:1725-1733`: the `result` found in `omnibox_results` is a `%Title{}`, so the call becomes `Discovery.add_to_watchlist(result)`.

`lib/media_centaur_web/live/entity_modal.ex:1163-1173`: replace the `Discovery.add_to_watchlist(%{...})` call with

```elixir
          # No poster_path on purpose: library subjects don't carry a TMDB
          # poster path — artwork arrives via Discovery's async TmdbArtwork.ensure.
          Discovery.add_to_watchlist(
            Title.new!(%{
              tmdb_id: tmdb_id,
              media_type: media_type,
              name: subject.name,
              year: watchlist_year(subject[:date_published]),
              release_date: subject[:date_published],
              overview: subject[:description]
            })
          )
```

and add `alias MediaCentaur.TMDB.Title` to the alias block at `:64-74`.

- [ ] **Step 8: `WatchlistRow` and `WatchlistLive` read `item.title`**

`lib/media_centaur_web/components/discovery/watchlist_row.ex`:

- imports: replace `import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]` with `import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]`.
- in `watchlist_row/1`: `MediaResults.release_status(assigns.item.title, today)`.
- replace the poster `<span class="flex h-[72px] ...">…</span>` block and the identity `<span class="min-w-0 flex-1 space-y-0.5 self-center">…</span>` block (everything before the action-strip comment) with:

```heex
      <.title_summary title={@item.title} poster_url={@poster_url}>
        <:secondary :if={@item.note}>{@item.note}</:secondary>
      </.title_summary>
```

(A slot with `:if` renders nothing when false, so the overview shows when there is no note — the same displacement rule as before.)

- `primary_action/1`: `@item.tmdb_id`/`@item.media_type` still exist on the row; no change.
- the `poster_url` attr doc → `"resolved by the host via \`LiveHelpers.title_poster_url/1\`"`.

`lib/media_centaur_web/live/watchlist_live.ex`:

- imports: `import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]` (drop `tmdb_cdn_url`); drop `alias MediaCentaur.TmdbArtwork` if nothing else uses it.
- `load_items/1`: `Map.put(row, :poster_url, title_poster_url(item.title))`; delete the private `poster_url/1` and its comment.
- `watchlist_track` handler: `ReleaseTracking.track_from_search_async(item.title)` and the flash `"Tracking #{item.title.name} — …"`.

- [ ] **Step 9: Story**

`storybook/discovery/watchlist_row.story.exs`: add `alias MediaCentaur.TMDB.Title`; replace `item/1` with

```elixir
  defp item(overrides) do
    {title_overrides, item_overrides} = Map.split(overrides, [:tmdb_id, :media_type, :name, :year, :release_date, :overview])

    title =
      Title.new!(
        Map.merge(
          %{
            tmdb_id: 777,
            media_type: :movie,
            name: "Sample Movie",
            year: "2010",
            release_date: ~D[2010-03-05],
            overview: "A sample movie overview that confirms this is the title you meant."
          },
          title_overrides
        )
      )

    struct!(
      %WatchlistItem{tmdb_id: title.tmdb_id, media_type: title.media_type, name: title.name, title: title, source: :manual},
      item_overrides
    )
  end
```

Variations keep their existing override maps unchanged (the split routes each key to the right struct).

- [ ] **Step 10: Migrate the test DB, run everything touched**

Run: `mix format && mix compile --warnings-as-errors && mix test test/media_centaur/discovery_test.exs test/media_centaur_web/live/watchlist_live_test.exs test/media_centaur/data_migrations_test.exs test/media_centaur/repo/data_migrations test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/no_db_on_render_test.exs`
Expected: pass. (`mix test` runs `ecto.migrate` first via the mix alias, so the test DB picks up the new column on its own.)

- [ ] **Step 11: Run the dev DB migrations**

The dev server on :2160 uses the real database. Apply both streams so the running app reads the new column:

```bash
mix ecto.migrate && mix ecto.migrate_data
```

Then verify via Tidewave `project_eval`: `MediaCentaur.Discovery.list_watchlist() |> Enum.map(& &1.item.title.name)` returns every existing watchlist name (or `[]` on an empty watchlist).

- [ ] **Step 12: Commit**

```bash
git add -A priv/repo lib/media_centaur/discovery lib/media_centaur/discovery.ex lib/media_centaur_web storybook test
git commit -m "feat(discovery): watchlist rows embed TMDB.Title (paired migration + backfill)

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 7: Precommit, docs, campaign bookkeeping

**Files:**
- Modify: `campaigns/friends-recommendations.md` (Status + Next steps)
- Modify: `docs/superpowers/plans/2026-08-18-watchlist-foundation.md` (unification note 1 — mark converged)
- Modify: `CHANGELOG.md` (Unreleased — migration mention per the safe-migration rule)

- [ ] **Step 1: Full precommit**

Run: `mix precommit 2>&1 | tail -40`
Expected: `PASSED` with zero warnings. Fix everything it reports (Credo MC0008 docs on any new loose attr, MC0009 story coverage for `title_summary`, formatter, Boundary). Re-run until clean.

- [ ] **Step 2: Grep for stragglers**

Run: `grep -rn "TitleResult\|search_tmdb\|tracked?: " lib storybook test docs/*.md AGENTS.md CLAUDE.md | grep -v "Targeting\|targeting\|Selection\|plans/\|specs/"`
Expected: no output. (Matches inside `Targeting.Selection`/`Episode` and historical plans/specs are fine.)

- [ ] **Step 3: Record the convergence**

In `docs/superpowers/plans/2026-08-18-watchlist-foundation.md` unification note 1, append: *[Converged 2026-09-02 in `docs/superpowers/plans/2026-09-02-title-convergence.md`: `MediaCentaur.TMDB.Title` + `TitleSearch`; Discovery takes the struct.]* Note 2: append *[Converged 2026-09-02: `tracked?` is `tracked_refs`.]*

In `campaigns/friends-recommendations.md` Status: "Layer 1a (title convergence) shipped <date>; next: plan 1b (Discovery page)". Under a `## Next steps` list (create if absent) add: "**Drop watchlist flat snapshot columns** (`name`, `year`, `release_date`, `poster_path`, `overview`) + remove the transitional `name` write in `WatchlistItem.create_changeset/2` — a schema migration in the release after the one that ships the embed."

`CHANGELOG.md` Unreleased: "Watchlist entries now store their TMDB title as one value. Existing entries are converted automatically on update; no action needed."

- [ ] **Step 4: Commit**

```bash
git add campaigns docs CHANGELOG.md
git commit -m "docs: title convergence shipped; schedule the flat-column drop

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

Do **not** push or tag — the owner reviews fresh work before shipping.

---

## Self-review

**Spec coverage (unification decisions 1–5):** 1 → Tasks 1, 2, 3, 6. 2 → Tasks 3, 4. 3 → Task 6 (paired migration + backfill + scheduled drop in Task 7). 4 → Task 5 (search rows, watchlist rows; feed rows arrive in layer 6; plan modal header stays scheduled). 5 → Task 5 (`title_poster_url/1` used by both). Artwork holds (6) unaffected — `TmdbArtworkHolds` still selects the identity columns.

**Type consistency:** `Title.new!/1`, `Title.ref/1`, `TitleSearch.search/1`, `ReleaseTracking.tracked_refs/0`, `LiveHelpers.title_poster_url/1`, `TitleSummary.title_summary/1` (`title`, `poster_url`, slots `markers`/`secondary`), `WatchlistItem.create_changeset/2` (title, attrs), `Discovery.add_to_watchlist/2` (title, attrs) — used with those exact names and arities throughout.

**Placeholders:** none; every code step carries its code. Steps that say "mirror the existing test" name the grep to find it.
