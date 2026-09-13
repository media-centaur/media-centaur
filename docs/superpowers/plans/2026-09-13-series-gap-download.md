# Series Gap Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the holes in a TV series actionable from the detail modal — click a missing episode to download it, and follow one link to pick more seasons.

**Architecture:** A season's episode list becomes one stored fact (`library_seasons.episode_list`, written from the `get_season` payload ingest already fetches and discards), replacing the `number_of_episodes` count. The season list renders that list joined against library files and today's date, so `Missing` means *aired and absent* by construction. Two controls then hang off it: a clickable missing row that plans one `{season, episode}` unit through the existing `Plans.create_series_plan/3` door, and a link to the existing plan picker on Incoming.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView, Ecto + SQLite, Phoenix Storybook, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-13-series-gap-download-design.md`

---

## Ground rules

- **Never run `mix` directly.** Every command below uses `~/scripts/agents/agent-mix`, which points `MIX_BUILD_ROOT` outside the checkout. A bare `mix` writes `.beam` files under the running dev server and can take it down.
- Tests are written before implementation. No network in tests — TMDB goes through `MediaCentaur.TMDBStubs`.
- Run `~/scripts/agents/agent-mix precommit` before the final commit of each phase and fix everything it reports. Zero warnings.
- Commit after each task.

## File structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/media_centaur/library/episode_list_entry.ex` | Embedded schema for one entry in a season's episode list |
| `priv/repo/migrations/20260913120000_season_episode_list.exs` | Adds `episode_list`, drops `number_of_episodes` |
| `test/media_centaur/library/episode_order_test.exs` | Renamed from `episode_list_test.exs` |
| `test/media_centaur/library/movie_order_test.exs` | Renamed from `movie_list_test.exs` |

**Renamed:**

| From | To |
|---|---|
| `lib/media_centaur_web/view_model/episode_list_item.ex` | `episode_row.ex` (`ViewModel.EpisodeRow`) |
| `lib/media_centaur_web/view_model/movie_list_item.ex` | `movie_row.ex` (`ViewModel.MovieRow`) |
| `lib/media_centaur/library/episode_list.ex` | `episode_order.ex` (`Library.EpisodeOrder`) |
| `lib/media_centaur/library/movie_list.ex` | `movie_order.ex` (`Library.MovieOrder`) |

**Modified:** `library/season.ex`, `library/completeness.ex`, `library/inbound.ex`, `library/progress_records.ex`, `library/views/detail.ex`, `library/views/detail_item.ex`, `pipeline/stages/fetch_metadata.ex`, `tmdb/mapper.ex`, `showcase.ex`, `maintenance.ex`, `view_model/series_detail.ex`, `components/detail/season_list.ex`, `live/entity_modal.ex`, `live/settings_live.ex`, `live/settings_live/maintenance_section.ex`, `test/support/factory.ex`, `storybook/detail_panel/detail_panel.story.exs`.

---

# Phase 1 — Renames

No behaviour changes. The existing suite is the test: it must pass before and after, with the same test count.

## Task 1: `EpisodeListItem` → `EpisodeRow`, `MovieListItem` → `MovieRow`

**Files:**
- Rename: `lib/media_centaur_web/view_model/episode_list_item.ex` → `episode_row.ex`
- Rename: `lib/media_centaur_web/view_model/movie_list_item.ex` → `movie_row.ex`
- Modify: 17 other files across `lib/`, `test/`, `storybook/`

- [ ] **Step 1: Record the baseline test count**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
~/scripts/agents/agent-mix test 2>&1 | tail -5
```

Expected: a line like `N tests, 0 failures`. Write N down — Task 1 and Task 2 must both end on the same N.

- [ ] **Step 2: Rewrite the module references**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
find lib test storybook -type f \( -name "*.ex" -o -name "*.exs" \) \
  -exec sed -i 's/EpisodeListItem/EpisodeRow/g; s/MovieListItem/MovieRow/g' {} +
git mv lib/media_centaur_web/view_model/episode_list_item.ex lib/media_centaur_web/view_model/episode_row.ex
git mv lib/media_centaur_web/view_model/movie_list_item.ex lib/media_centaur_web/view_model/movie_row.ex
```

- [ ] **Step 3: Fix the two moduledocs by hand**

The sed renamed the modules but left prose that now reads wrong. In `lib/media_centaur_web/view_model/episode_row.ex`, replace the opening moduledoc line:

```elixir
  @moduledoc """
  Tagged-struct ADT for the rows of a TV-series season, as consumed by
  `MediaCentaurWeb.Components.Detail.SeasonList`.
```

and in the `Missing` variant's moduledoc replace the `season.number_of_episodes` sentence with:

```elixir
  defmodule Missing do
    @moduledoc """
    An episode the season's `episode_list` says exists, that has aired
    (or carries no air date), and that no file has been imported for.
    No release record either — otherwise it would be an `Upcoming`.
    """
```

In `lib/media_centaur_web/view_model/movie_row.ex`, the moduledoc's cross-reference now reads `MediaCentaurWeb.ViewModel.EpisodeRow` — correct, leave it.

- [ ] **Step 4: Compile and fix what the compiler reports**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
~/scripts/agents/agent-mix compile --warnings-as-errors
```

Expected: clean. If a file aliased the old name in a way sed missed (a string in a `@doc`, say), the compiler or Credo will name it.

- [ ] **Step 5: Run the full suite**

```bash
~/scripts/agents/agent-mix test 2>&1 | tail -5
```

Expected: the same N tests, 0 failures as Step 1.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: EpisodeListItem becomes EpisodeRow, MovieListItem becomes MovieRow

Frees the words 'episode list' for the season's stored list of episodes.
'Row' is already the components' vocabulary (missing_episode_row,
upcoming_episode_row, Detail.PlayableRow). The movie sibling renames with
it because its moduledoc defines it as the episode one's parallel.

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 2: `Library.EpisodeList` → `EpisodeOrder`, and the progress trio moves out

**Files:**
- Rename: `lib/media_centaur/library/episode_list.ex` → `episode_order.ex`
- Rename: `lib/media_centaur/library/movie_list.ex` → `movie_order.ex`
- Rename: `test/media_centaur/library/episode_list_test.exs` → `episode_order_test.exs`
- Rename: `test/media_centaur/library/movie_list_test.exs` → `movie_order_test.exs`
- Modify: `lib/media_centaur/library/progress_records.ex` (gains three functions)
- Modify: 19 other files

- [ ] **Step 1: Rename the two modules**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
find lib test -type f \( -name "*.ex" -o -name "*.exs" \) \
  -exec sed -i 's/\bEpisodeList\b/EpisodeOrder/g; s/\bMovieList\b/MovieOrder/g' {} +
git mv lib/media_centaur/library/episode_list.ex lib/media_centaur/library/episode_order.ex
git mv lib/media_centaur/library/movie_list.ex lib/media_centaur/library/movie_order.ex
git mv test/media_centaur/library/episode_list_test.exs test/media_centaur/library/episode_order_test.exs
git mv test/media_centaur/library/movie_list_test.exs test/media_centaur/library/movie_order_test.exs
```

- [ ] **Step 2: Move the three progress functions into `ProgressRecords`**

Cut these from `lib/media_centaur/library/episode_order.ex` and paste them into `lib/media_centaur/library/progress_records.ex`, above the existing write functions:

```elixir
  @doc """
  Indexes progress records by their container id (Movie or Episode id),
  resolved through the linked `PlayableItem`. Expects `:playable_item` to
  be preloaded on each record (Library Schema v2 Phase 2 Task C — the
  three direct FKs `movie_id` / `episode_id` / `video_object_id` no
  longer exist on `WatchProgress`).
  """
  def index_progress_by_key(progress_records) do
    Map.new(progress_records, fn record ->
      {progress_container_id(record), record}
    end)
  end

  @doc """
  The leaf id a progress record belongs to, read off its preloaded
  `PlayableItem`. nil when the association is absent.
  """
  def progress_container_id(%{playable_item: %{container_id: id}}), do: id
  def progress_container_id(_), do: nil

  @doc """
  The watch state a progress record implies: `:watched` when completed,
  `:current` when started, `:unwatched` otherwise.
  """
  def state_from_progress(nil), do: :unwatched

  def state_from_progress(progress) do
    cond do
      progress.completed -> :watched
      (progress.position_seconds || 0) > 0 -> :current
      true -> :unwatched
    end
  end
```

Check the body of `state_from_progress/1` against the original in `episode_order.ex` before deleting it — copy the original body verbatim if it differs from the above.

- [ ] **Step 3: Update the moduledocs on both sides**

`lib/media_centaur/library/episode_order.ex`:

```elixir
  @moduledoc """
  Ordering and position lookup over a TV series entity's seasons and
  episodes: sorting, the playable sequence, and finding an episode by
  position or content URL. Used by Resume, ResumeTarget and
  ProgressSummary.

  The movie-collection parallel is `MediaCentaur.Library.MovieOrder`.
  Reading a progress record — its container id, its state, indexing a
  list of them — belongs to `MediaCentaur.Library.ProgressRecords`.
  """
```

`lib/media_centaur/library/movie_order.ex`: change the moduledoc's `Parallel to EpisodeList but for MovieSeries.` to `Parallel to EpisodeOrder but for MovieSeries.`

In `lib/media_centaur/library/progress_records.ex`, add to the moduledoc after the existing first paragraph:

```elixir
  Reading a record is here too: `progress_container_id/1` resolves the
  leaf id off the preloaded `PlayableItem`, `state_from_progress/1`
  derives the watch state, and `index_progress_by_key/1` keys a list of
  records by leaf. They lived in `Library.EpisodeOrder` until
  2026-09-13, which is why a movie view model used to call an
  episode-named module for them.
```

- [ ] **Step 4: Repoint the call sites**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
find lib test -type f \( -name "*.ex" -o -name "*.exs" \) -exec sed -i \
  's/EpisodeOrder\.state_from_progress/ProgressRecords.state_from_progress/g;
   s/EpisodeOrder\.progress_container_id/ProgressRecords.progress_container_id/g;
   s/EpisodeOrder\.index_progress_by_key/ProgressRecords.index_progress_by_key/g' {} +
```

Then fix the three fully-qualified references sed cannot see, by hand:

`lib/media_centaur_web/view_model/series_detail.ex` around line 289:

```elixir
  # Both `Detail.PlayableRow.state_from_progress/1` and this caller delegate to the
  # same Library helper so the rendering layer and the composition
  # layer can't drift.
  defdelegate episode_state(progress),
    to: MediaCentaur.Library.ProgressRecords,
    as: :state_from_progress
```

`lib/media_centaur_web/components/detail/playable_row.ex` around line 23 — change its `defdelegate state_from_progress(progress), to: MediaCentaur.Library.EpisodeOrder` target to `MediaCentaur.Library.ProgressRecords`.

`lib/media_centaur_web/components/detail_panel.ex:64` — the `@doc_progress_records` string says `EpisodeList.progress_container_id/1`; change it to `ProgressRecords.progress_container_id/1`.

- [ ] **Step 5: Compile and fix the aliases the compiler names**

```bash
~/scripts/agents/agent-mix compile --warnings-as-errors
```

Expected: errors naming files that call `ProgressRecords.…` without aliasing it, and warnings for files that now alias `EpisodeOrder` without using it. Both are mechanical: add `alias MediaCentaur.Library.ProgressRecords` (or drop the unused alias) in each file the compiler names. Files known to need it: `library/progress_summary.ex`, `playback/resume.ex`, `playback/resume_target.ex`, `playback/resolver.ex`, `playback/next_episode.ex`, `view_model/collection_detail.ex`.

- [ ] **Step 6: Move the two misplaced tests**

`test/media_centaur/library/episode_order_test.exs` has a `describe "index_progress_by_key/1"` block, and `test/media_centaur/library/movie_order_test.exs` has `describe "EpisodeOrder.index_progress_by_key/1 keys movie-series progress by movie_id"`. Both now test `ProgressRecords`. Move both describe blocks into `test/media_centaur/library/progress_records_test.exs` (create it if absent, with `use MediaCentaur.DataCase` matching the header of `episode_order_test.exs`), renaming the second describe to `"index_progress_by_key/1 keys movie-series progress by movie_id"`.

- [ ] **Step 7: Run the full suite**

```bash
~/scripts/agents/agent-mix test 2>&1 | tail -5
```

Expected: the same N tests, 0 failures as Task 1 Step 1. A different count means a describe block was dropped rather than moved.

- [ ] **Step 8: Precommit and commit**

```bash
~/scripts/agents/agent-mix precommit
git add -A
git commit -m "refactor: EpisodeList becomes EpisodeOrder, progress reads move to ProgressRecords

Third claimant on the words 'episode list'. The module's moduledoc was an
'and' — walking a series' episodes and indexing progress records — and its
MovieList parallel carried no progress functions at all, which is why
CollectionDetail (a movie view model) called EpisodeList.state_from_progress/1.
What remains in both is ordering and position lookup.

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

# Phase 2 — The episode list

## Task 3: The `EpisodeListEntry` embed and the migration

**Files:**
- Create: `lib/media_centaur/library/episode_list_entry.ex`
- Create: `priv/repo/migrations/20260913120000_season_episode_list.exs`
- Modify: `lib/media_centaur/library/season.ex`
- Modify: `test/support/factory.ex:159-169`
- Test: `test/media_centaur/library/season_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur/library/season_test.exs`:

```elixir
defmodule MediaCentaur.Library.SeasonTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Library.Season

  describe "create_changeset/1 with an episode list" do
    test "casts entries, coercing ISO air dates" do
      changeset =
        Season.create_changeset(%{
          season_number: 2,
          name: "Season 2",
          tv_series_id: Ecto.UUID.generate(),
          episode_list: [
            %{episode_number: 1, name: "My Overkill", air_date: "2002-10-01"},
            %{episode_number: 2, name: "My Nightingale", air_date: nil}
          ]
        })

      assert changeset.valid?
      [first, second] = Ecto.Changeset.apply_changes(changeset).episode_list
      assert first.episode_number == 1
      assert first.name == "My Overkill"
      assert first.air_date == ~D[2002-10-01]
      assert second.air_date == nil
    end

    test "an entry without an episode number is invalid" do
      changeset =
        Season.create_changeset(%{
          season_number: 1,
          tv_series_id: Ecto.UUID.generate(),
          episode_list: [%{name: "Untitled"}]
        })

      refute changeset.valid?
    end
  end

  describe "episode_list_changeset/2" do
    test "replaces the whole list" do
      season = %Season{
        season_number: 1,
        episode_list: [%MediaCentaur.Library.EpisodeListEntry{episode_number: 1}]
      }

      changeset =
        Season.episode_list_changeset(season, [
          %{episode_number: 1, name: "One", air_date: "2020-01-01"},
          %{episode_number: 2, name: "Two", air_date: "2020-01-08"}
        ])

      assert length(Ecto.Changeset.apply_changes(changeset).episode_list) == 2
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/library/season_test.exs
```

Expected: FAIL — `MediaCentaur.Library.EpisodeListEntry` is undefined.

- [ ] **Step 3: Create the embedded schema**

`lib/media_centaur/library/episode_list_entry.ex`:

```elixir
defmodule MediaCentaur.Library.EpisodeListEntry do
  @moduledoc """
  One entry in a `MediaCentaur.Library.Season`'s episode list — an
  episode TMDB says the season contains, whether or not a file for it
  was ever imported.

  Written from the `get_season` payload at ingest
  (`MediaCentaur.Pipeline.Stages.FetchMetadata`) and refreshed by
  `MediaCentaur.Maintenance.refresh_episode_lists/0`. This is not a
  `Library.Episode`: an Episode row means a file exists, and several
  invariants depend on that (release tracking satisfies a want by
  finding one). An entry only means TMDB lists the episode.

  `air_date` is nil for episodes TMDB has not dated. An undated entry
  is treated as aired, not as upcoming: absence of a date is not
  evidence that an episode is in the future.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          episode_number: integer() | nil,
          name: String.t() | nil,
          air_date: Date.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :episode_number, :integer
    field :name, :string
    field :air_date, :date
  end

  @doc "Casts one TMDB episode into an entry."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:episode_number, :name, :air_date])
    |> validate_required([:episode_number])
  end
end
```

- [ ] **Step 4: Swap the field on `Season`**

In `lib/media_centaur/library/season.ex`, replace `field :number_of_episodes, :integer` with the embed, and rewrite the changesets:

```elixir
  schema "library_seasons" do
    field :season_number, :integer
    field :name, :string

    embeds_many :episode_list, MediaCentaur.Library.EpisodeListEntry, on_replace: :delete

    belongs_to :tv_series, MediaCentaur.Library.TVSeries
    has_many :episodes, MediaCentaur.Library.Episode
```

(leave the rest of the schema block untouched), and:

```elixir
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:season_number, :name, :tv_series_id])
    |> cast_embed(:episode_list)
    # Matches the unique index restored in
    # 20260523210000_restore_season_unique_index. Surfaces a racing
    # duplicate insert as `{:error, changeset}` so `find_or_insert_by/3`
    # can recover to the winning row instead of creating a second Season.
    |> unique_constraint([:tv_series_id, :season_number])
  end

  @doc """
  Replaces the season's episode list wholesale — the write
  `Maintenance.refresh_episode_lists/0` makes. `entries` is a list of
  plain maps with `:episode_number`, `:name` and `:air_date`.
  """
  def episode_list_changeset(%__MODULE__{} = season, entries) do
    season
    |> cast(%{episode_list: entries}, [])
    |> cast_embed(:episode_list)
  end
```

Also update the moduledoc:

```elixir
  @moduledoc """
  A TV season belonging to a `TVSeries` entity. Created from TMDB season
  data when a file for that season is first ingested.

  `episode_list` is TMDB's ordered episodes for the season, including
  episodes no file was imported for — the season's single source for
  "what episodes exist". The episode *count* is `length(episode_list)`;
  the `number_of_episodes` column it replaced was that same length,
  stored separately.
  """
```

- [ ] **Step 5: Write the migration**

`priv/repo/migrations/20260913120000_season_episode_list.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.SeasonEpisodeList do
  @moduledoc """
  A season's episode list replaces its episode count. `number_of_episodes`
  was `length(episodes)` over the TMDB `get_season` payload, which the
  ingest stage discarded; `episode_list` keeps `episode_number`, `name`
  and `air_date` for every episode the season has, so the detail modal
  can tell a missing episode from one that has not aired without asking
  TMDB (2026-09-13 series-gap-download design).

  No data migration. The column is a snapshot of an external source and
  cannot be derived from anything local — *Refresh episode lists* under
  Settings → Maintenance repopulates it, one `get_season` per incomplete
  season. Until it runs, a season carries an empty list and the season
  list renders exactly as it did before.
  """
  use Ecto.Migration

  def change do
    alter table(:library_seasons) do
      add :episode_list, :map
      remove :number_of_episodes, :integer
    end
  end
end
```

- [ ] **Step 6: Update the factory**

`test/support/factory.ex`, in `build_season/1`, replace `number_of_episodes: 0` with `episode_list: []`. In `create_factory_episode_for_tv_series/1` (around line 713), drop `number_of_episodes: 0` from the `Library.Seasons.find_or_create/1` call — the comment above it about gap-filling stays accurate.

- [ ] **Step 7: Run migration and the new test**

```bash
~/scripts/agents/agent-mix ecto.migrate
~/scripts/agents/agent-mix test test/media_centaur/library/season_test.exs
```

Expected: PASS, 3 tests.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(library): a season stores its episode list, not a count

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 4: Ingest writes the episode list

**Files:**
- Modify: `lib/media_centaur/pipeline/stages/fetch_metadata.ex:22`, `:268-291`, `:293-312`
- Modify: `lib/media_centaur/library/inbound.ex:592-600`, `:678-688`
- Delete: `lib/media_centaur/tmdb/mapper.ex:93-105` (`season_attrs/2`)
- Delete: `test/media_centaur/tmdb/mapper_test.exs:559-582` (`describe "season_attrs/2"`)
- Test: `test/media_centaur/pipeline/stages/fetch_metadata_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/pipeline/stages/fetch_metadata_test.exs`, inside the existing top-level `describe` for season metadata (match the file's existing setup for stubbing TMDB and running the stage; if the file has no season describe block, add this one at the end of the module):

```elixir
  describe "season episode list" do
    test "carries every TMDB episode with its air date" do
      MediaCentaur.TMDBStubs.stub_get_season(246_810, 1, %{
        "season_number" => 1,
        "name" => "Season 1",
        "episodes" => [
          %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
          %{"episode_number" => 2, "name" => "Second", "air_date" => ""},
          %{"episode_number" => 3, "name" => "Third", "air_date" => "2199-01-01"}
        ]
      })

      season = FetchMetadata.build_season_for_test(season_data(), parsed())

      assert [one, two, three] = season.episode_list
      assert one == %{episode_number: 1, name: "Pilot", air_date: "2020-01-01"}
      assert two.air_date == nil
      assert three.air_date == "2199-01-01"
    end
  end
```

`build_season/2` is private. Rather than exposing it, drive the assertion through whatever public entry point the existing tests in this file already use to run the stage (look at the top of the file for the established pattern) and assert on the `season.episode_list` in the resulting metadata map. Replace `FetchMetadata.build_season_for_test(season_data(), parsed())` with that call and its fixtures — do not add a test-only public function.

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/pipeline/stages/fetch_metadata_test.exs
```

Expected: FAIL — the season map has `number_of_episodes`, no `episode_list`.

- [ ] **Step 3: Build the list in the stage**

In `lib/media_centaur/pipeline/stages/fetch_metadata.ex`, replace the tail of `build_season/2`:

```elixir
    %{
      season_number: season_data["season_number"],
      name: season_data["name"],
      episode_list: Enum.map(episodes, &episode_list_entry/1),
      episode: episode
    }
  end

  # TMDB dates an undated episode as "" rather than omitting the key;
  # Ecto's :date cast rejects the empty string, so it becomes nil here.
  defp episode_list_entry(episode) do
    %{
      episode_number: episode["episode_number"],
      name: episode["name"],
      air_date: presence(episode["air_date"])
    }
  end

  defp presence(""), do: nil
  defp presence(value), do: value
```

In `build_minimal_season/1`, replace `number_of_episodes: 0,` with `episode_list: [],`.

Update the moduledoc line 22 to:

```elixir
  - `season` — `%{season_number, name, episode_list, episode}`
```

- [ ] **Step 4: Persist it in Inbound**

`lib/media_centaur/library/inbound.ex`, in `create_season_and_episode/3`, replace `number_of_episodes: season_data.number_of_episodes` with `episode_list: season_data.episode_list`. In `create_extra/4` (around line 683) replace `number_of_episodes: 0` with `episode_list: []`.

- [ ] **Step 5: Delete the dead mapper function**

Remove `season_attrs/2` and its `@doc` from `lib/media_centaur/tmdb/mapper.ex` (lines 93-105), and remove the whole `describe "season_attrs/2"` block from `test/media_centaur/tmdb/mapper_test.exs`.

```bash
grep -rn "season_attrs" lib/ test/
```

Expected: no output.

- [ ] **Step 6: Run the affected tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur/pipeline/stages/fetch_metadata_test.exs test/media_centaur/library/inbound_test.exs test/media_centaur/tmdb/mapper_test.exs
```

Expected: PASS. `inbound_test.exs` will need its `number_of_episodes:` fixtures changed to `episode_list:` — five of them.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(pipeline): ingest keeps the season's episode list

The get_season payload already carried every episode with its air date and
build_season/2 reduced it to a count. Mapper.season_attrs/2 — a second
extraction of the same fact with no production callers — is deleted.

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 5: Showcase seeder writes the episode list

**Files:**
- Modify: `lib/media_centaur/showcase.ex:280-288`

- [ ] **Step 1: Replace the count with the list**

At `lib/media_centaur/showcase.ex:284`, replace:

```elixir
            number_of_episodes: length(season_data["episodes"] || [])
```

with:

```elixir
            episode_list:
              Enum.map(season_data["episodes"] || [], fn episode ->
                %{
                  episode_number: episode["episode_number"],
                  name: episode["name"],
                  air_date: if(episode["air_date"] in [nil, ""], do: nil, else: episode["air_date"])
                }
              end)
```

- [ ] **Step 2: Verify the seeder compiles**

```bash
~/scripts/agents/agent-mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(showcase): seed seasons with their episode list

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 6: The detail projection carries the episode list

**Files:**
- Modify: `lib/media_centaur/library/views/detail_item.ex:194-206`, `:604-612`
- Modify: `lib/media_centaur/library/views/detail.ex:1189-1203`
- Test: `test/media_centaur/library/views/detail_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/library/views/detail_test.exs` (inside the existing describe block that builds a TV series detail item — match its setup):

```elixir
    test "the season carries its episode list" do
      series = Factory.create_tv_series(%{name: "Sample Show"})

      {:ok, season} =
        MediaCentaur.Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: [
            %{episode_number: 1, name: "One", air_date: "2020-01-01"},
            %{episode_number: 2, name: "Two", air_date: nil}
          ]
        })

      _ = season

      item = MediaCentaur.Library.Views.Detail.detail_by_container(:tv_series, series.id)
      [season_view] = item.seasons

      assert [%{episode_number: 1, name: "One", air_date: ~D[2020-01-01]}, %{episode_number: 2}] =
               season_view.episode_list
    end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/library/views/detail_test.exs
```

Expected: FAIL — `key :episode_list not found` on `DetailItem.Season`.

- [ ] **Step 3: Swap the field on `DetailItem.Season`**

In `lib/media_centaur/library/views/detail_item.ex`, replace the `Season` defstruct, type and doc line:

```elixir
    @moduledoc """
    A season bucket of the detail item.

    `:episode_list` mirrors the Season schema field — TMDB's episodes for
    the season, including ones the library has no file for. Carried as
    plain maps (`%{episode_number, name, air_date}`) like the rest of this
    lean projection.
    """
    defstruct [:season_number, :name, :episodes, :episode_list, extras: []]

    @type t :: %__MODULE__{
            season_number: integer(),
            name: String.t() | nil,
            episodes: [MediaCentaur.Library.Views.DetailItem.Episode.t()],
            episode_list: [%{episode_number: integer(), name: String.t() | nil, air_date: Date.t() | nil}],
            extras: list()
          }
```

Keep the surrounding lines of the original `Season` moduledoc that describe the other fields; only the `number_of_episodes` sentence is replaced.

In `season_to_map/1` (line ~604), replace `number_of_episodes: season.number_of_episodes,` with `episode_list: season.episode_list || [],`.

- [ ] **Step 4: Populate it in the projection**

In `lib/media_centaur/library/views/detail.ex`, `shape_seasons/2`:

```elixir
      %DetailItem.Season{
        season_number: season.season_number,
        name: season.name,
        episode_list: Enum.map(season.episode_list || [], &shape_episode_list_entry/1),
        episodes: episodes,
        extras: Map.get(graph.extras_by_season_id, season.id, [])
      }
```

and add beside it:

```elixir
  defp shape_episode_list_entry(entry) do
    %{episode_number: entry.episode_number, name: entry.name, air_date: entry.air_date}
  end
```

- [ ] **Step 5: Run the tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur/library/views/detail_test.exs test/media_centaur/library/views/detail_item_test.exs
```

Expected: PASS. Three `number_of_episodes` fixtures in each file need swapping to `episode_list`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(library): the detail projection carries the season episode list

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 7: The season list renders from the episode list

**Files:**
- Modify: `lib/media_centaur_web/view_model/series_detail.ex:182-234`
- Test: `test/media_centaur_web/view_model/series_detail_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/media_centaur_web/view_model/series_detail_test.exs` (the file builds inputs as plain fixtures — follow its existing `build/3` call shape):

```elixir
  describe "build/3 against the season episode list" do
    setup do
      entry = fn number, date -> %{episode_number: number, name: "Ep #{number}", air_date: date} end
      %{entry: entry}
    end

    test "an aired entry with no file is a Missing row", %{entry: entry} do
      season = %{
        season_number: 1,
        name: "Season 1",
        episodes: [%{id: "e1", episode_number: 1, name: "Ep 1"}],
        episode_list: [entry.(1, ~D[2020-01-01]), entry.(2, ~D[2020-01-08])],
        extras: []
      }

      [view] = SeriesDetail.build(entry_for(season), [], nil).seasons

      assert [%EpisodeRow.Library{}, %EpisodeRow.Missing{episode_number: 2}] = view.items
    end

    test "an entry dated in the future is an Upcoming row", %{entry: entry} do
      future = Date.add(Date.utc_today(), 30)

      season = %{
        season_number: 1,
        name: "Season 1",
        episodes: [],
        episode_list: [entry.(1, future)],
        extras: []
      }

      [view] = SeriesDetail.build(entry_for(season), [], nil).seasons

      assert [%EpisodeRow.Upcoming{episode_number: 1, sub_status: :unaired, air_date: ^future}] =
               view.items
    end

    test "an undated entry is Missing, not Upcoming", %{entry: entry} do
      season = %{
        season_number: 1,
        name: "Season 1",
        episodes: [],
        episode_list: [entry.(1, nil)],
        extras: []
      }

      [view] = SeriesDetail.build(entry_for(season), [], nil).seasons

      assert [%EpisodeRow.Missing{episode_number: 1}] = view.items
    end

    test "an empty episode list renders only the library rows", %{entry: _entry} do
      season = %{
        season_number: 1,
        name: "Season 1",
        episodes: [%{id: "e1", episode_number: 3, name: "Ep 3"}],
        episode_list: [],
        extras: []
      }

      [view] = SeriesDetail.build(entry_for(season), [], nil).seasons

      assert [%EpisodeRow.Library{}] = view.items
      assert view.total_count == 1
    end

    test "a release still wins over the episode list", %{entry: entry} do
      season = %{
        season_number: 1,
        name: "Season 1",
        episodes: [],
        episode_list: [entry.(1, ~D[2020-01-01])],
        extras: []
      }

      releases = [
        %{
          season_number: 1,
          episode_number: 1,
          title: "From the calendar",
          air_date: ~D[2020-01-01],
          released: true,
          in_library: false
        }
      ]

      [view] = SeriesDetail.build(entry_for(season), releases, nil).seasons

      assert [%EpisodeRow.Upcoming{title: "From the calendar"}] = view.items
    end
  end
```

Add a private helper at the bottom of the test module (or reuse the file's existing equivalent if one is already defined — check before adding):

```elixir
  defp entry_for(season) do
    %{
      entity: %{seasons: [season], extras: []},
      progress: nil,
      progress_records: []
    }
  end
```

- [ ] **Step 2: Run them to verify they fail**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/view_model/series_detail_test.exs
```

Expected: FAIL — the composer still reads `number_of_episodes`.

- [ ] **Step 3: Rewrite `build_library_items/4` and `total_count`**

In `lib/media_centaur_web/view_model/series_detail.ex`, replace the `total_count` line in `build_library_season/4`:

```elixir
    total_count = max(length(season.episodes || []), length(season.episode_list || []))
```

and replace `build_library_items/4` entirely:

```elixir
  # One row per episode number the season knows about, in order: the
  # episode list TMDB gave us, plus any library or release row numbered
  # outside it (a misparsed `E1080`, an absolute episode number). A
  # release wins over an episode-list entry for the same number — the
  # calendar is maintained on a cadence and carries the episode's title,
  # where the list is an ingest-time snapshot.
  defp build_library_items(season, releases, progress_by_episode_id, resume_episode_key) do
    episode_map = Map.new(season.episodes || [], &{&1.episode_number, &1})
    release_map = Map.new(releases, &{&1.episode_number, &1})
    listed = Map.new(season.episode_list || [], &{&1.episode_number, &1})
    today = Date.utc_today()

    (Map.keys(listed) ++ Map.keys(episode_map) ++ Map.keys(release_map))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn number ->
      cond do
        episode = Map.get(episode_map, number) ->
          build_library_item(episode, season.season_number, progress_by_episode_id, resume_episode_key)

        release = Map.get(release_map, number) ->
          build_upcoming_item(release)

        true ->
          build_listed_item(Map.fetch!(listed, number), season.season_number, today)
      end
    end)
  end

  # An episode TMDB lists that no file was imported for. Dated in the
  # future means it has not aired; a past date — or no date at all —
  # is a gap the person can act on, because absence of a date is not
  # evidence that an episode is still to come.
  defp build_listed_item(entry, season_number, today) do
    if entry.air_date && Date.compare(entry.air_date, today) == :gt do
      %EpisodeRow.Upcoming{
        season_number: season_number,
        episode_number: entry.episode_number,
        title: entry.name,
        air_date: entry.air_date,
        sub_status: :unaired
      }
    else
      %EpisodeRow.Missing{season_number: season_number, episode_number: entry.episode_number}
    end
  end
```

- [ ] **Step 4: Run the tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/view_model/series_detail_test.exs
```

Expected: PASS. The file's ten existing `number_of_episodes` fixtures become `episode_list` — a season that used to say `number_of_episodes: 4` now says `episode_list: [entry(1), entry(2), entry(3), entry(4)]` with past air dates, which is the same intent stated exactly.

- [ ] **Step 5: Run the wider suite**

```bash
~/scripts/agents/agent-mix test
```

Expected: PASS. Failures here are fixtures elsewhere still passing `number_of_episodes` — `deletion_test`, `entity_cascade_test`, `library_links_test`, `page_smoke_test`, `inbound_listener_test`, `watched_file_test`, `type_resolver_test`, `image_health_test`, `image_repair_test`, `ingest_test`, `library_test`, `entity_modal_refresh_test`. Each is a one-line fixture change.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(detail): the season list renders from the season's episode list

Missing now means aired and absent, by construction. The 1..ceiling
synthesis and the known-numbers union existed only because the composer
had a count instead of a list.

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 8: `Completeness` reads the episode list

**Files:**
- Modify: `lib/media_centaur/library/completeness.ex:49-105`
- Test: `test/media_centaur/library/completeness_test.exs`

**Note — this changes the Status tile's number and what it counts.** The old function counted *series* with an internal numbering hole while its label read "Incomplete seasons". It now counts *seasons* holding an aired episode with no file, which is what the label says. On the owner's library the tile goes from 2 to roughly 9 once the maintenance pass has run.

- [ ] **Step 1: Write the failing test**

Replace the `detect_season_gaps/1` describe block in `test/media_centaur/library/completeness_test.exs` with:

```elixir
  describe "incomplete_season_count/0" do
    test "counts a season holding an aired episode with no file" do
      series = Factory.create_tv_series(%{name: "Sample Show"})

      {:ok, season} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: [
            %{episode_number: 1, air_date: "2020-01-01"},
            %{episode_number: 2, air_date: "2020-01-08"}
          ]
        })

      {:ok, _} = Library.Episodes.find_or_create(%{season_id: season.id, episode_number: 1})

      assert Completeness.incomplete_season_count() == 1
    end

    test "a season whose only absent episodes are unaired does not count" do
      series = Factory.create_tv_series(%{name: "Sample Show"})
      future = Date.add(Date.utc_today(), 30) |> Date.to_iso8601()

      {:ok, season} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: [
            %{episode_number: 1, air_date: "2020-01-01"},
            %{episode_number: 2, air_date: future}
          ]
        })

      {:ok, _} = Library.Episodes.find_or_create(%{season_id: season.id, episode_number: 1})

      assert Completeness.incomplete_season_count() == 0
    end

    test "a season with an empty episode list never counts" do
      series = Factory.create_tv_series(%{name: "Sample Show"})

      {:ok, _season} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: []
        })

      assert Completeness.incomplete_season_count() == 0
    end

    test "each short season of one series counts separately" do
      series = Factory.create_tv_series(%{name: "Sample Show"})

      for number <- [1, 2] do
        {:ok, _} =
          Library.Seasons.create(%{
            tv_series_id: series.id,
            season_number: number,
            name: "Season #{number}",
            episode_list: [%{episode_number: 1, air_date: "2020-01-01"}]
          })
      end

      assert Completeness.incomplete_season_count() == 2
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/library/completeness_test.exs
```

Expected: FAIL — the old heuristic returns 0 for the first case (no internal hole) and 1 for the last (one series, not two seasons).

- [ ] **Step 3: Rewrite the function**

In `lib/media_centaur/library/completeness.ex`, replace `incomplete_season_count/0`, `detect_season_gaps/1` and `season_has_gap?/1` with:

```elixir
  @doc """
  Count of seasons holding at least one episode TMDB lists that has
  aired and that the library has no file for.

  A season whose `episode_list` is empty never counts: the list is a
  snapshot of TMDB, and its absence is not evidence of a gap. Run
  *Refresh episode lists* under Settings → Maintenance to populate it.
  An entry TMDB has not dated counts as aired, matching how the detail
  modal renders it.
  """
  @spec incomplete_season_count() :: non_neg_integer()
  def incomplete_season_count do
    today = Date.utc_today()
    owned = owned_episode_numbers()

    from(s in Season, select: %{id: s.id, episode_list: s.episode_list})
    |> Repo.all()
    |> Enum.count(&season_short?(&1, owned, today))
  end

  # `%{season_id => MapSet.t(episode_number)}` for every library episode.
  defp owned_episode_numbers do
    from(e in Episode, select: {e.season_id, e.episode_number})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {season_id, numbers} -> {season_id, MapSet.new(numbers)} end)
  end

  defp season_short?(season, owned, today) do
    have = Map.get(owned, season.id, MapSet.new())

    Enum.any?(season.episode_list || [], fn entry ->
      aired?(entry.air_date, today) and not MapSet.member?(have, entry.episode_number)
    end)
  end

  defp aired?(nil, _today), do: true
  defp aired?(air_date, today), do: Date.compare(air_date, today) != :gt
```

Update the moduledoc's second sentence to read:

```elixir
  on: containers with no TMDB metadata, and TV seasons holding aired
  episodes the library has no file for.
```

Remove the now-unused `TVSeries` alias only if the compiler reports it — `missing_metadata_count/0` still uses it.

- [ ] **Step 4: Run the tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur/library/completeness_test.exs
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(status): incomplete seasons counts seasons, exactly

The heuristic counted series with an internal numbering hole under a label
reading 'Incomplete seasons' — it missed a season that stops early and could
not tell an unaired episode from an absent one. The episode list settles both.

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

# Phase 3 — Keeping the episode list true

## Task 9: `Maintenance.refresh_episode_lists/0`

**Files:**
- Modify: `lib/media_centaur/maintenance.ex` (async variant near line 113, action after `refresh_series_credits/0`)
- Test: `test/media_centaur/maintenance_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/maintenance_test.exs` (follow the file's existing setup for stubbing TMDB):

```elixir
  describe "refresh_episode_lists/0" do
    test "fills an incomplete season from TMDB and skips a complete one" do
      series = Factory.create_tv_series(%{name: "Sample Show"})
      Factory.create_external_id(series, "tmdb", "246810")

      {:ok, short} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: []
        })

      {:ok, complete} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 2,
          name: "Season 2",
          episode_list: [%{episode_number: 1, air_date: "2021-01-01"}]
        })

      {:ok, _} = Library.Episodes.find_or_create(%{season_id: complete.id, episode_number: 1})

      MediaCentaur.TMDBStubs.stub_get_tv_with_seasons(246_810, %{"id" => 246_810}, %{
        1 =>
          MediaCentaur.TMDBStubs.season_detail(%{
            "season_number" => 1,
            "episodes" => [
              %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
              %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
            ]
          })
      })

      assert {:ok, %{updated: 1, skipped: 1, failed: 0}} = Maintenance.refresh_episode_lists()

      refreshed = Repo.get!(MediaCentaur.Library.Season, short.id)
      assert length(refreshed.episode_list) == 2
      assert Enum.map(refreshed.episode_list, & &1.episode_number) == [1, 2]
      assert hd(refreshed.episode_list).air_date == ~D[2020-01-01]
    end
  end
```

Check `MediaCentaur.TMDBStubs.season_detail/1` and `Factory.create_external_id/3` exist with those names before running — if they differ, use the file's established helpers.

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/maintenance_test.exs
```

Expected: FAIL — `Maintenance.refresh_episode_lists/0` is undefined.

- [ ] **Step 3: Add the async variant**

In `lib/media_centaur/maintenance.ex`, beside the other async wrappers (after `rederive_extra_names_async/1`):

```elixir
  @doc "Async `refresh_episode_lists/0`; sends `{:episode_lists_refreshed, result}`."
  def refresh_episode_lists_async(reply_to) do
    run_async(fn ->
      {:ok, result} = refresh_episode_lists()
      send(reply_to, {:episode_lists_refreshed, result})
    end)
  end
```

This is the same shape as `refresh_series_credits_async/1` at line 82: `run_async/1` takes a zero-arity function that sends its own result message.

- [ ] **Step 4: Add the action**

After `refresh_series_credits/0` and its private helpers:

```elixir
  @doc """
  Refreshes the TMDB episode list of every season that is not complete —
  an empty `episode_list`, or fewer library episode rows than the list
  holds — for series carrying a TMDB id. One `get_season` per season,
  rate-limited inside the TMDB client.

  Complete seasons are skipped, so re-running is cheap. It refreshes
  rather than backfills: a season ingested mid-run captured whatever
  TMDB knew that day, and a revised episode count would otherwise never
  reach the library.

  Broadcasts `entities_changed` for the touched series so the ETS Detail
  projection — and any open modal — picks the new lists up.

  Returns `{:ok, %{updated: n, skipped: n, failed: n}}`.
  """
  @spec refresh_episode_lists() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
  def refresh_episode_lists do
    Log.info(:library, "refreshing season episode lists")

    initial = %{updated: 0, skipped: 0, failed: 0, updated_ids: []}

    result =
      Enum.reduce(records_with_tmdb_id(TVSeries), initial, fn {series, tmdb_id}, acc ->
        Enum.reduce(Library.Seasons.list_for_tv_series(series.id), acc, fn season, acc ->
          refresh_one_episode_list(series, season, tmdb_id, acc)
        end)
      end)

    %{updated_ids: updated_ids} = result
    Library.broadcast_entities_changed(Enum.uniq(updated_ids))

    counts = Map.delete(result, :updated_ids)

    Log.info(
      :library,
      "episode list refresh — #{counts.updated} updated, #{counts.skipped} skipped, #{counts.failed} failed"
    )

    {:ok, counts}
  end

  defp refresh_one_episode_list(series, season, tmdb_id, acc) do
    if season_complete?(season) do
      %{acc | skipped: acc.skipped + 1}
    else
      case Client.get_season(tmdb_id, season.season_number) do
        {:ok, season_data} ->
          entries = Enum.map(season_data["episodes"] || [], &episode_list_entry/1)

          case Repo.update(Library.Season.episode_list_changeset(season, entries)) do
            {:ok, _season} ->
              %{acc | updated: acc.updated + 1, updated_ids: [series.id | acc.updated_ids]}

            {:error, _changeset} ->
              %{acc | failed: acc.failed + 1}
          end

        {:error, reason} ->
          Log.warning(
            :library,
            "episode list refresh failed for #{series.id} season #{season.season_number}: #{inspect(reason)}"
          )

          %{acc | failed: acc.failed + 1}
      end
    end
  end

  # Complete means the library holds a row for every episode the list
  # names. An empty list is never complete — it is a season that has
  # never been refreshed.
  defp season_complete?(season) do
    listed = length(season.episode_list || [])
    listed > 0 and length(Library.Episodes.list_for_season(season.id)) >= listed
  end

  # TMDB dates an undated episode as "" rather than omitting the key.
  defp episode_list_entry(episode) do
    %{
      episode_number: episode["episode_number"],
      name: episode["name"],
      air_date: if(episode["air_date"] in [nil, ""], do: nil, else: episode["air_date"])
    }
  end
```

Add `Season` to the `alias MediaCentaur.Library.{...}` block at the top of the module, and `alias MediaCentaur.Library.Seasons` / `Episodes` if the module does not already reach them through `Library`.

- [ ] **Step 4a: Check the Boundary declaration**

`Maintenance` declares `use Boundary, deps: [MediaCentaur.Library, ...]`, so `Library.Seasons`, `Library.Episodes` and `Library.Season` must be exported by the Library boundary. Run the compile in the next step; if Boundary rejects a call, reach the data through an existing exported `Library.*` function rather than widening the boundary.

- [ ] **Step 5: Run the test**

```bash
~/scripts/agents/agent-mix test test/media_centaur/maintenance_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(maintenance): refresh season episode lists

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 10: The Settings button

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/maintenance_section.ex:28`, `:170`
- Modify: `lib/media_centaur_web/live/settings_live.ex:161`, `:650`, `:1268`, `:1807`, `:2072`
- Test: `test/media_centaur_web/live/settings_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/settings_live_test.exs` (match the file's existing pattern for a maintenance button):

```elixir
    test "refresh episode lists button starts the pass", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      assert view |> element("button[phx-click='refresh_episode_lists']") |> render_click()
      assert render(view) =~ "Refreshing…"
    end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs
```

Expected: FAIL — no element matches the selector.

- [ ] **Step 3: Add the attr and the row**

In `lib/media_centaur_web/live/settings_live/maintenance_section.ex`, beside the other attrs (line ~28):

```elixir
  attr :refreshing_episode_lists, :boolean, required: true
```

and, after the *Refresh series credits* block (line ~170):

```elixir
        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Refresh episode lists</p>
            <p class="text-xs text-base-content/55 mt-0.5">
              Asks TMDB which episodes each season has, so the detail view can tell a missing episode from one that hasn't aired. Only checks seasons you don't have in full — safe to re-run.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="refresh_episode_lists"
            disabled={@refreshing_episode_lists}
            data-nav-item
            tabindex="0"
          >
            {if @refreshing_episode_lists, do: "Refreshing…", else: "Refresh"}
          </.button>
        </div>
```

- [ ] **Step 4: Wire the LiveView**

In `lib/media_centaur_web/live/settings_live.ex`: add `refreshing_episode_lists: false,` to the mount assigns beside line 161; add the event handler beside line 650:

```elixir
  def handle_event("refresh_episode_lists", _params, socket) do
    Maintenance.refresh_episode_lists_async(self())
    {:noreply, assign(socket, refreshing_episode_lists: true)}
  end
```

the result handler beside line 1268:

```elixir
  def handle_info(
        {:episode_lists_refreshed, %{updated: updated, skipped: skipped, failed: failed}},
        socket
      ) do
    msg =
      cond do
        updated == 0 and failed == 0 ->
          "Episode lists already up to date — nothing to refresh."

        failed > 0 ->
          "Refreshed #{updated} season episode lists (#{skipped} skipped, #{failed} failed)."

        true ->
          "Refreshed #{updated} season episode lists" <>
            if(skipped > 0, do: " (#{skipped} already complete).", else: ".")
      end

    {:noreply,
     socket
     |> assign(refreshing_episode_lists: false)
     |> put_flash(:info, msg)}
  end
```

and pass `refreshing_episode_lists={@refreshing_episode_lists}` at both call sites of `maintenance_section` (lines ~1807 and ~2072).

- [ ] **Step 5: Run the test**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(settings): Refresh episode lists maintenance button

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

# Phase 4 — The controls

## Task 11: "Download more of this show"

**Files:**
- Modify: `lib/media_centaur_web/components/detail/season_list.ex:56-105`
- Modify: `lib/media_centaur_web/components/detail_panel.ex` (thread `tmdb_id` and `acquisition?` into `season_list`)
- Test: `test/media_centaur_web/components/detail/season_list_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur_web/components/detail/season_list_test.exs`:

```elixir
defmodule MediaCentaurWeb.Components.Detail.SeasonListTest do
  use MediaCentaurWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.Detail.SeasonList
  alias MediaCentaurWeb.ViewModel.{EpisodeRow, SeasonView}

  defp season_view do
    %SeasonView{
      season_number: 1,
      name: "Season 1",
      kind: :library,
      items: [%EpisodeRow.Missing{season_number: 1, episode_number: 2}],
      extras: [],
      watched_count: 0,
      total_count: 2
    }
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        seasons: [season_view()],
        entity_id: "entity-1",
        expanded_seasons: MapSet.new([1]),
        expanded_item_details: MapSet.new(),
        all_episode_details_open: false,
        extras: [],
        extra_progress_by_id: %{},
        on_play: "play",
        spoiler_free: false,
        available: true,
        series_tmdb_id: "4556",
        acquisition?: true
      },
      overrides
    )
  end

  test "offers the link to the plan picker" do
    html = render_component(&SeasonList.season_list/1, assigns(%{}))

    assert html =~ "Download more of this show"
    assert html =~ "/incoming?plan=new&amp;tmdb_id=4556&amp;tmdb_type=tv"
  end

  test "no link without a TMDB id" do
    html = render_component(&SeasonList.season_list/1, assigns(%{series_tmdb_id: nil}))

    refute html =~ "Download more of this show"
  end

  test "no link when acquisition is not configured" do
    html = render_component(&SeasonList.season_list/1, assigns(%{acquisition?: false}))

    refute html =~ "Download more of this show"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/components/detail/season_list_test.exs
```

Expected: FAIL — unknown attrs `series_tmdb_id` / `acquisition?`.

- [ ] **Step 3: Add the attrs and the link**

In `lib/media_centaur_web/components/detail/season_list.ex`, add beside the other attrs on `season_list/1`:

```elixir
  attr :series_tmdb_id, :string,
    default: nil,
    doc: "the series' TMDB id — the plan picker's target. nil hides the Download more link."

  attr :acquisition?, :boolean,
    default: false,
    doc: "an indexer and a download client are ready; without them nothing here can download."
```

and, inside the outer `<div>` after the `<.season_section :for={...} />` loop and before `<ExtrasSection.extras_section ... />`:

```heex
      <%!-- The season list is a picture of what is on disk; seasons you
            don't own live in the plan picker on the other side of this
            link (2026-09-13 series-gap-download design, decision 12). --%>
      <div :if={@series_tmdb_id && @acquisition?} class="pt-1">
        <.link
          navigate={~p"/incoming?plan=new&tmdb_id=#{@series_tmdb_id}&tmdb_type=tv"}
          class="inline-flex items-center gap-1.5 text-xs text-base-content/55 hover:text-base-content transition-colors"
          data-role="download-more-link"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-arrow-down-tray-mini" class="size-3.5" />
          Download more of this show
        </.link>
      </div>
```

- [ ] **Step 4: Thread the two attrs from `DetailPanel`**

In `lib/media_centaur_web/components/detail_panel.ex`, find the `<SeasonList.season_list ... />` call and add:

```heex
        series_tmdb_id={@entity && @entity.tmdb_id}
        acquisition?={@acquisition?}
```

`acquisition?` is already an attr on `detail_panel/1`; `@entity.tmdb_id` is already read there for the Letterboxd link on movies.

- [ ] **Step 5: Run the test**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/components/detail/season_list_test.exs
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(detail): Download more of this show closes the season list

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 12: The missing row downloads its episode

**Files:**
- Modify: `lib/media_centaur_web/components/detail/season_list.ex:345-372` (`missing_episode_row/1`)
- Modify: `lib/media_centaur_web/live/entity_modal.ex` (`__using__` clause + handler)
- Test: `test/media_centaur_web/components/detail/season_list_test.exs`
- Test: `test/media_centaur_web/live/library_live_test.exs`

- [ ] **Step 1: Write the failing component test**

Add to `test/media_centaur_web/components/detail/season_list_test.exs`:

```elixir
  test "the missing row carries the download event" do
    html = render_component(&SeasonList.season_list/1, assigns(%{}))

    assert html =~ ~s(phx-click="download_missing_episode")
    assert html =~ ~s(phx-value-season="1")
    assert html =~ ~s(phx-value-episode="2")
  end

  test "the missing row is inert without acquisition" do
    html = render_component(&SeasonList.season_list/1, assigns(%{acquisition?: false}))

    refute html =~ "download_missing_episode"
  end
```

- [ ] **Step 2: Run to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/components/detail/season_list_test.exs
```

Expected: FAIL on both new tests.

- [ ] **Step 3: Make the row actionable**

In `season_list.ex`, `season_item/1` dispatches to `missing_episode_row/1` — thread the two new values down from `season_list/1` through `season_section/1` and `season_item/1` by adding the same two attrs to each (`series_tmdb_id`, `acquisition?`) and passing them at each call site. Then replace `missing_episode_row/1`:

```elixir
  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeRow.Missing{}`"

  attr :id, :string, required: true, doc: "stable DOM id for the row (UIDR-012)."

  attr :actionable, :boolean,
    required: true,
    doc: "whether clicking the row downloads the episode — a TMDB id plus a configured indexer and client."

  defp missing_episode_row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "p-2 rounded group",
        if(@actionable,
          do: "opacity-30 hover:opacity-90 focus-visible:opacity-90 cursor-pointer transition-opacity",
          else: "opacity-30"
        )
      ]}
      data-role="missing-episode-row"
      data-nav-item
      tabindex="0"
      phx-click={@actionable && "download_missing_episode"}
      phx-value-season={@actionable && @item.season_number}
      phx-value-episode={@actionable && @item.episode_number}
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/55 font-mono text-xs tabular-nums">
          {@item.episode_number}
        </span>
        <span class="flex-1 min-w-0 truncate text-base-content/70 italic">
          Episode {@item.episode_number}
        </span>
        <.icon
          :if={@actionable}
          name="hero-arrow-down-tray-mini"
          class="size-3.5 flex-shrink-0 text-base-content/0 group-hover:text-base-content/60 group-focus-visible:text-base-content/60 transition-colors"
        />
      </div>
    </div>
    """
  end
```

In `season_item/1`'s `Missing` clause, pass `actionable={@series_tmdb_id != nil && @acquisition?}`.

- [ ] **Step 4: Run the component tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/components/detail/season_list_test.exs
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Write the failing LiveView test**

Add to `test/media_centaur_web/live/library_live_test.exs`:

```elixir
    test "clicking a missing episode row plans that episode", %{conn: conn} do
      series = Factory.create_tv_series(%{name: "Sample Show"})
      Factory.create_external_id(series, "tmdb", "246810")

      {:ok, season} =
        Library.Seasons.create(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1",
          episode_list: [
            %{episode_number: 1, name: "Pilot", air_date: "2020-01-01"},
            %{episode_number: 2, name: "Second", air_date: "2020-01-08"}
          ]
        })

      {:ok, _} = Library.Episodes.find_or_create(%{season_id: season.id, episode_number: 1})

      MediaCentaur.TMDBStubs.stub_sample_show()

      {:ok, view, _html} = live(conn, ~p"/library?selected=#{series.id}")

      view
      |> element("[data-role='missing-episode-row'][phx-value-episode='2']")
      |> render_click()

      assert render(view) =~ "Finding a release for"
      assert [plan] = MediaCentaur.Acquisition.Plans.list_drafts()
      assert Enum.map(plan.units, & &1.episode_number) == [2]
    end
```

`Plans.list_drafts/0` is the public read (`plans.ex:401`). Use the file's own helpers for creating the series and stubbing TMDB if they differ from the names above — `stub_sample_show/0` must stub `/tv/246810` and `/tv/246810/season/1` together, which is what `TMDBStubs.stub_get_tv_with_seasons/3` is for.

The test asserts the auto-select ending, so it needs the planning-mode preference set to auto first — `MediaCentaur.Settings.Preferences.PlanningMode.set(:auto_select_best_release)` in the test body, before `live/2`. Without it the default is manual select, which navigates to the plan board instead of flashing.

- [ ] **Step 6: Run to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/library_live_test.exs
```

Expected: FAIL — no handler for `download_missing_episode`.

- [ ] **Step 7: Add the injected clause and the handler**

In `lib/media_centaur_web/live/entity_modal.ex`, inside `__using__`, beside the other clauses:

```elixir
      def handle_event("download_missing_episode", params, socket) do
        EntityModal.handle_download_missing_episode(params, socket)
      end
```

and, as a public function on the module beside `handle_toggle_season/2`:

```elixir
  @doc """
  Plans the one episode a missing row names. Fetches the series'
  targeting selection (a TMDB call, on an explicit click — never on
  render) and creates a one-unit plan through the existing
  `Plans.create_series_plan/3` door.

  The fetched selection is the guard: an episode that has not aired, or
  that arrived since the projection was built, is not planned. The
  person's planning mode decides the approval policy and the ending —
  auto-select flashes and stays put, manual select lands on the plan
  board (2026-09-13 series-gap-download design, decisions 9-10).
  """
  def handle_download_missing_episode(%{"season" => season, "episode" => episode}, socket) do
    unit = {String.to_integer(season), String.to_integer(episode)}
    entity = socket.assigns.selected_entry && socket.assigns.selected_entry.entity

    cond do
      socket.assigns[:download_pending] ->
        {:noreply, socket}

      is_nil(entity) or is_nil(entity.tmdb_id) ->
        {:noreply, socket}

      true ->
        name = {:missing_episode, entity.id, unit}
        tmdb_id = entity.tmdb_id
        mode = MediaCentaur.Settings.Preferences.PlanningMode.value()

        {:noreply,
         socket
         |> Phoenix.Component.assign(:download_pending, name)
         |> Phoenix.LiveView.start_async(name, fn ->
           plan_missing_episode(tmdb_id, unit, mode)
         end)}
    end
  end

  # Runs in the async task: TMDB read, then the plan door.
  defp plan_missing_episode(tmdb_id, {season, episode} = unit, mode) do
    policy =
      case mode do
        :auto_select_best_release -> "automatic"
        _manual -> "review"
      end

    with {:ok, selection} <- Acquisition.Targeting.series_selection(tmdb_id),
         :ok <- unit_plannable(selection, unit) do
      case Acquisition.Plans.create_series_plan(selection, [unit], approval_policy: policy) do
        {:ok, plan} -> {:planned, plan, mode, selection.title, season, episode}
        {:error, reason} -> {:plan_failed, reason}
      end
    else
      {:error, reason} -> {:plan_failed, reason}
      {:skip, reason} -> {:plan_skipped, reason}
    end
  end

  defp unit_plannable(selection, {season, episode}) do
    found =
      Enum.find_value(selection.seasons, fn s ->
        s.season_number == season && Enum.find(s.episodes, &(&1.episode_number == episode))
      end)

    cond do
      is_nil(found) -> {:skip, :not_listed}
      not found.aired? -> {:skip, :unaired}
      found.in_library? -> {:skip, :already_here}
      true -> :ok
    end
  end
```

Add the matching `handle_async/3` clauses in `__using__` beside the existing ones (find how `TitleDetailHost`'s `{:title_download, …}` async result is handled and mirror it):

```elixir
      def handle_async({:missing_episode, _entity_id, _unit} = name, {:ok, result}, socket) do
        EntityModal.handle_missing_episode_result(name, result, socket)
      end
```

and on the module:

```elixir
  @doc "Ends a missing-episode download: flash, or the plan's board."
  def handle_missing_episode_result(_name, {:planned, plan, mode, title, season, episode}, socket) do
    socket = Phoenix.Component.assign(socket, :download_pending, nil)
    label = "#{title} S#{season}E#{episode}"

    case mode do
      :auto_select_best_release ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :info, "Finding a release for #{label}")}

      _manual ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/incoming?plan=#{plan.id}")}
    end
  end

  def handle_missing_episode_result(_name, {:plan_skipped, reason}, socket) do
    copy =
      case reason do
        :unaired -> "That episode hasn't aired yet."
        :already_here -> "That episode is already in your library."
        :not_listed -> "TMDB doesn't list that episode for this season."
      end

    {:noreply,
     socket
     |> Phoenix.Component.assign(:download_pending, nil)
     |> Phoenix.LiveView.put_flash(:info, copy)}
  end

  def handle_missing_episode_result(_name, {:plan_failed, _reason}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:download_pending, nil)
     |> Phoenix.LiveView.put_flash(:error, "Couldn't plan that episode. Check TMDB under Settings and try again.")}
  end
```

Add `download_pending: nil` to the modal's mount assigns wherever the other modal assigns are seeded, and the aliases `MediaCentaur.Acquisition` needs at the top of `entity_modal.ex`.

- [ ] **Step 8: Run the LiveView test**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/library_live_test.exs
```

Expected: PASS.

- [ ] **Step 9: Precommit and commit**

```bash
~/scripts/agents/agent-mix precommit
git add -A
git commit -m "feat(detail): click a missing episode to download it

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

## Task 13: Storybook variation for the acquisition gate

**Files:**
- Modify: `storybook/detail_panel/detail_panel.story.exs:686-711` and the variations list

- [ ] **Step 1: Confirm the existing TV fixture has a TMDB id**

```bash
grep -n "defp sample_tv_entity" -A 20 storybook/detail_panel/detail_panel.story.exs | grep tmdb_id
```

If it has no `tmdb_id`, add `tmdb_id: "4556",` to the entity map — the default `:tv_series_with_seasons` variation must render the actionable row and the link, since `tv_series_attrs/0` already sets `acquisition?: true`.

- [ ] **Step 2: Add the gated variation**

After the `:tv_series_with_seasons` variation entry:

```elixir
      %Variation{
        id: :tv_series_acquisition_off,
        description:
          "Same library shape as `:tv_series_with_seasons` with `acquisition?: false`: " <>
            "the missing-episode row is inert (no download glyph, no click) and " <>
            "\"Download more of this show\" is absent. The gate for an install " <>
            "with no indexer or download client configured.",
        attributes: Map.put(tv_series_attrs(), :acquisition?, false)
      },
```

- [ ] **Step 3: Update the story moduledoc**

Add to the numbered list in the moduledoc, after entry 8b:

```
    8c. `:tv_series_acquisition_off` — the acquisition gate: missing rows
        inert, no "Download more of this show".
```

- [ ] **Step 4: Run the storybook tests**

```bash
~/scripts/agents/agent-mix test test/storybook_compile_test.exs test/storybook_render_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test(storybook): pin the acquisition gate on the TV detail panel

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

# Phase 5 — Copy and docs

## Task 14: Copy pass and wiki

**Files:**
- Modify: whatever the copy pass changes
- Modify: `../media-centaur.wiki/Settings-Reference.md`
- Modify: `../media-centaur.wiki/` TV detail page under *Using Media Centaur*

- [ ] **Step 1: Run the copy through the skill**

Invoke the `writing-copy` skill and settle these strings against it:

- `Download more of this show` (the link)
- `Refresh episode lists` and its Settings description
- `Finding a release for Sample Show S1E2`
- `That episode hasn't aired yet.`
- `That episode is already in your library.`
- `TMDB doesn't list that episode for this season.`
- `Couldn't plan that episode. Check TMDB under Settings and try again.`
- The three maintenance result flashes

Apply whatever it changes and re-run the affected tests.

- [ ] **Step 2: Update the wiki**

```bash
cd ~/src/media-centaur/media-centaur.wiki
```

In `Settings-Reference.md`, add *Refresh episode lists* to the Library Maintenance section, matching the entries around it: what it does, that it only touches seasons you don't have in full, and that it is safe to re-run.

In the TV detail page under *Using Media Centaur*, document both controls: clicking a greyed-out episode downloads it, and the link at the end of the season list opens the picker where you choose seasons. Note that episodes that haven't aired show a date instead and can't be clicked.

```bash
git add -A
git commit -m "wiki: downloading a missing episode and getting more of a show"
git push
```

- [ ] **Step 3: Final precommit**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
~/scripts/agents/agent-mix precommit
```

Expected: clean. Fix everything it reports.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: copy pass for the series-gap download controls

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

- [ ] **Step 5: Run the maintenance pass against the real library**

Start the dev server (or use the running one) and press *Refresh episode lists* under Settings → Maintenance. Confirm afterwards that the Scrubs detail modal shows S2E13 as an actionable missing row, and that The Boys S5's absent episodes render according to their real air dates.

---

## Deviations from the spec

Recorded here so the spec and the plan do not silently disagree:

- **Spec decision 18 said the Status tile goes from 2 to 6** (series with a gap). This plan counts **seasons** instead, because the tile's label reads "Incomplete seasons" and counting series under that label was the naming incoherence the spec's decision 18 half-fixed. Roughly 9 on this library, minus any whose absent episodes turn out to be unaired. No copy change needed — the label becomes true.
