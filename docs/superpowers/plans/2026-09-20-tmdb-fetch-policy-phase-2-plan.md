# TMDB fetch policy — Phase 2: checks replace the refresher

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release tracking stops asking TMDB on a clock. A cron job checks the stored titles that are due; release tracking rebuilds its calendar from the store when a title changes; the tracked item sheds every copied TMDB fact; a person can force a check from the title's Manage view or tracking controls.

**Architecture:** `TMDB.References` (a behaviour and registry, generalised from the artwork hold providers) answers "who references this identity" and which of those references schedule checks. `TMDB.CheckJob` (Oban cron, `@reboot` and every 15 minutes) first-contacts referenced titles the store lacks and checks the due ones. `ReleaseTracking.TmdbListener` subscribes to `{:tmdb_title_changed, ref}` and `ReleaseTracking.title_changed/1` rebuilds releases from stored payloads through the pure `ReleaseTracking.Calendar`. `Item` loses its eight copy columns; `name` and `season_sizes` become virtual fields attached on read from the store. `Refresher`, `RefreshSchedule`, both interval settings and the Settings stepper go; the want sweep becomes `ReleaseTracking.SweepJob`. Design: [`2026-09-20-tmdb-fetch-policy-design.md`](../specs/2026-09-20-tmdb-fetch-policy-design.md) §2.4–2.7, §3 rows C–F, Y.

**Tech Stack:** Elixir, Ecto/SQLite, Oban (cron plugin, `:maintenance` queue), Phoenix.PubSub, LiveView, Phoenix Storybook, ExUnit.

**House rules:** `~/scripts/agents/agent-mix` for every mix command; test-first; no real titles; zero warnings; factories not `Repo.insert`; every commit ends with `Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF`. Run the full gate (`agent-mix precommit`) in the foreground.

**Scope decisions made in this plan** (recorded in the campaign file on completion):
- Scheduling scope in Phase 2 is tracked titles only. Discovery (listed) and Acquisition (planned) providers exist but answer `schedules_checks?/0` false until Phase 3 gives them readers; Activities never schedules.
- The refresher's collection branch (`library_container_type: :movie_series`) is deleted with the refresher. No such item exists on the owner's instance, and the `collection-identity` campaign already suspected the path unreachable; that campaign's file gets a dated note.
- The Settings key `release_tracking_sweep_interval_minutes` goes with the refresher; the sweep runs on the same 15-minute cron as the checker.
- No record sweep yet (design §2.4 retention) — Phase 5, with the artwork sweep.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/tmdb/references.ex` | **Create.** `TMDB.References` registry + `TMDB.References.Provider` behaviour. |
| `lib/media_centaur/{release_tracking,acquisition,discovery,activities}/tmdb_references.ex` | **Rename** from `tmdb_artwork_holds.ex`; implement the new behaviour. |
| `lib/media_centaur/tmdb_artwork/hold_provider.ex` | **Delete.** |
| `lib/media_centaur/tmdb_artwork.ex` | **Modify.** Sweep reads `TMDB.References.all/0`. |
| `config/config.exs` | **Modify.** `:tmdb_reference_providers`; two cron rows. |
| `lib/media_centaur/tmdb/store.ex` | **Modify.** `get_many/1`. |
| `lib/media_centaur/tmdb/check_job.ex` | **Create.** The checker. |
| `lib/media_centaur/release_tracking/calendar.ex` | **Create.** Pure: releases and season sizes from payloads. |
| `lib/media_centaur/release_tracking/titles.ex` | **Create.** Store reads for items: `attach/1`, `payload!/1`. |
| `lib/media_centaur/release_tracking/tmdb_listener.ex` | **Create.** PubSub → `ReleaseTracking.title_changed/1`. |
| `lib/media_centaur/release_tracking/sweep_job.ex` | **Create.** Want-ledger sweep on cron. |
| `lib/media_centaur/release_tracking.ex` | **Modify.** `title_changed/1`, `rebuild_calendar/1`, loaders attach titles, `get_item_by_ref/1`. |
| `lib/media_centaur/release_tracking/{item,identity,onboarding,helpers}.ex` | **Modify.** |
| `lib/media_centaur/release_tracking/{refresher,refresh_schedule}.ex` | **Delete.** |
| `priv/repo/migrations/20260920130000_release_tracking_items_read_the_store.exs` | **Create.** Drop eight columns; delete three settings rows. |
| `lib/media_centaur/settings/config.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/acquisition_section.ex` | **Modify.** Remove the interval setting and stepper. |
| `lib/media_centaur/application.ex` | **Modify.** Listener in, refresher out. |
| `lib/media_centaur_web/components/detail/manage_panel.ex`, `lib/media_centaur_web/live/title_detail_host/library_events.ex`, `lib/media_centaur_web/components/detail_panel.ex`, `lib/media_centaur_web/components/title/refresh_from_tmdb.ex` (create), `lib/media_centaur_web/live/title_detail_host.ex` | **Modify/Create.** The manual refresh control. |
| `storybook/title/refresh_from_tmdb.story.exs` | **Create.** MC0009. |
| `decisions/user-interface/2026-09-20-044-refresh-from-tmdb.md` | **Create.** |
| `test/support/factory.ex` | **Modify.** Tracking items carry a stored title. |
| Tests | see each task |
| Wiki (`../media-centaur.wiki`) | Release-Tracking, Settings-Reference, Browsing-Your-Library, Keyboard-and-Gamepad, Troubleshooting, TMDB-API-Key |

---

### Task 1: `TMDB.References` replaces the artwork hold providers

**Files:** create `lib/media_centaur/tmdb/references.ex`; rename the four `*/tmdb_artwork_holds.ex` → `*/tmdb_references.ex`; delete `lib/media_centaur/tmdb_artwork/hold_provider.ex`; modify `lib/media_centaur/tmdb_artwork.ex`, `config/config.exs`, `lib/media_centaur/tmdb.ex`; tests `test/media_centaur/tmdb/references_test.exs` (create), `test/media_centaur/discovery_test.exs:148,159`, `test/media_centaur/activities/activities_test.exs:313`.

- [ ] **Step 1: Failing test** — `test/media_centaur/tmdb/references_test.exs`:

```elixir
defmodule MediaCentaur.TMDB.ReferencesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.References

  defmodule Tracked do
    @behaviour References.Provider
    def references, do: MapSet.new([{1, :movie}, {2, :tv_series}])
    def schedules_checks?, do: true
  end

  defmodule Friends do
    @behaviour References.Provider
    def references, do: MapSet.new([{2, :tv_series}, {3, :movie}])
    def schedules_checks?, do: false
  end

  test "all/1 is the union of every provider's references" do
    assert References.all([Tracked, Friends]) == MapSet.new([{1, :movie}, {2, :tv_series}, {3, :movie}])
  end

  test "scheduled/1 is the union of the providers that schedule checks" do
    assert References.scheduled([Tracked, Friends]) == MapSet.new([{1, :movie}, {2, :tv_series}])
  end

  test "the configured providers are the four contexts that hold titles" do
    assert References.providers() == [
             MediaCentaur.ReleaseTracking.TmdbReferences,
             MediaCentaur.Acquisition.TmdbReferences,
             MediaCentaur.Discovery.TmdbReferences,
             MediaCentaur.Activities.TmdbReferences
           ]
  end
end
```

- [ ] **Step 2: Run** `agent-mix test test/media_centaur/tmdb/references_test.exs` → FAIL, module missing.

- [ ] **Step 3: Implement**

`lib/media_centaur/tmdb/references.ex`:

```elixir
defmodule MediaCentaur.TMDB.References do
  @moduledoc """
  Who references a TMDB identity — the one answer behind two decisions:
  what the store and the artwork cache keep alive, and which stored
  titles are scheduled for checks (ADR-071 §4).

  A reference is a `{tmdb_id, media_type}` ref held by a context: a
  tracked item, a title intent, an open pursuit, a friend's activity.
  Each context registers a `Provider` under
  `config :media_centaur, :tmdb_reference_providers` — runtime dispatch,
  so the referencing contexts stay upstream of TMDB in the Boundary
  graph. `all/1` is retention; `scheduled/1` is only the providers whose
  references mean the user is waiting on how the title unfolds. A title
  known only through friends' activity is kept, never checked.

  Generalised from `TmdbArtwork.HoldProvider` (2026-09-20), which asked
  the retention half of this question for artwork alone.
  """

  alias MediaCentaur.TMDB.Store

  defmodule Provider do
    @moduledoc "A context that holds TMDB titles: what it references, and whether those references schedule checks."
    @callback references() :: MapSet.t(Store.ref())
    @callback schedules_checks?() :: boolean()
  end

  @doc "The registered providers, in configuration order."
  @spec providers() :: [module()]
  def providers, do: Application.get_env(:media_centaur, :tmdb_reference_providers, [])

  @doc "Every referenced identity — what stays alive."
  @spec all([module()]) :: MapSet.t(Store.ref())
  def all(providers \\ providers()) do
    Enum.reduce(providers, MapSet.new(), &MapSet.union(&2, &1.references()))
  end

  @doc "The identities whose references schedule checks."
  @spec scheduled([module()]) :: MapSet.t(Store.ref())
  def scheduled(providers \\ providers()) do
    providers
    |> Enum.filter(& &1.schedules_checks?())
    |> all()
  end
end
```

Rename each provider (`git mv`) and rewrite, e.g. `lib/media_centaur/release_tracking/tmdb_references.ex`:

```elixir
defmodule MediaCentaur.ReleaseTracking.TmdbReferences do
  @moduledoc """
  Every tracked item references its title — tracking is a standing
  interest, so the title's record and artwork never age out while the
  item exists, and the title is checked while it is unsettled.
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  import Ecto.Query

  alias MediaCentaur.ReleaseTracking.Item
  alias MediaCentaur.Repo

  @impl true
  def references do
    from(i in Item, select: {i.tmdb_id, i.media_type}) |> Repo.all() |> MapSet.new()
  end

  @impl true
  def schedules_checks?, do: true
end
```

Acquisition (`schedules_checks?` **false** until Phase 3 — "planned titles get their reader when the plan board reads the store"), Discovery (**false** until Phase 3), Activities (**false**, permanently, with the design's reason). Each keeps its existing query, with the tuple order flipped to `{tmdb_id, media_type}`.

`config/config.exs`: rename the key to `:tmdb_reference_providers` with the four new module names and a comment pointing at `TMDB.References`.

`lib/media_centaur/tmdb_artwork.ex`: replace the `holds/0` union (`:326-328`) with

```elixir
    MediaCentaur.TMDB.References.all()
    |> MapSet.new(fn {tmdb_id, media_type} -> {media_type, tmdb_id} end)
```

(the artwork cache keys `{media_type, tmdb_id}`); moduledoc `:28,:35` and `exports:` drop `HoldProvider`. Delete `hold_provider.ex`. `lib/media_centaur/tmdb.ex` exports add `References`, `References.Provider`.

Tests: `discovery_test.exs:148,159` and `activities_test.exs:313` → `TmdbReferences.references()`; `tmdb_artwork_test.exs` sweep tests need no change (they go through config).

- [ ] **Step 4: Run** `agent-mix test test/media_centaur/tmdb/ test/media_centaur/tmdb_artwork_test.exs test/media_centaur/discovery_test.exs test/media_centaur/activities/ --warnings-as-errors` → pass. `agent-mix compile --force` once if Boundary complains about exports.

- [ ] **Step 5: Commit** `refactor(tmdb): References — who holds a title, and whose hold schedules a check; replaces TmdbArtwork.HoldProvider`.

---

### Task 2: `Store.get_many/1`

- [ ] **Step 1: Failing test** in `store_test.exs`:

```elixir
  describe "get_many/1" do
    test "returns the stored records by ref, missing refs absent" do
      a = create_title_record(%{tmdb_id: 610, media_type: :movie})
      b = create_title_record(%{tmdb_id: 611, media_type: :tv_series})

      assert %{{610, :movie} => ^a, {611, :tv_series} => ^b} = found =
               Store.get_many([{610, :movie}, {611, :tv_series}, {612, :movie}])

      assert map_size(found) == 2
    end
  end
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** in `store.ex`, under reads:

```elixir
  @doc "The stored titles for `refs`, keyed by ref; a ref the store lacks is absent."
  @spec get_many(Enumerable.t()) :: %{ref() => TitleRecord.t()}
  def get_many(refs) do
    ids = refs |> Enum.map(fn {id, _type} -> id end) |> Enum.uniq()

    from(t in TitleRecord, where: t.tmdb_id in ^ids)
    |> Repo.all()
    |> Map.new(&{{&1.tmdb_id, &1.media_type}, &1})
    |> Map.take(Enum.to_list(refs))
  end
```

(ids are parsed integers on records; callers pass integer refs.)

- [ ] **Step 4: Run** → pass. **Step 5: Commit** `feat(tmdb): Store.get_many/1`.

---

### Task 3: `TMDB.CheckJob`

**Files:** create `lib/media_centaur/tmdb/check_job.ex`, `test/media_centaur/tmdb/check_job_test.exs`; modify `config/config.exs` crontab, `lib/media_centaur/tmdb.ex` exports.

- [ ] **Step 1: Failing tests**

```elixir
defmodule MediaCentaur.TMDB.CheckJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.{CheckJob, Store}
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.mark_ready!()
    test_pid = self()

    Req.Test.stub(:tmdb, fn conn ->
      validator = Plug.Conn.get_req_header(conn, "if-none-match")
      send(test_pid, {:tmdb_hit, conn.request_path, validator})

      if validator == [~s(W/"held")] do
        Plug.Conn.send_resp(conn, 304, "")
      else
        body =
          if String.contains?(conn.request_path, "/tv/"),
            do: TmdbStubs.tv_detail(%{"id" => 800, "status" => "Returning Series", "seasons" => []}),
            else: TmdbStubs.movie_detail(%{"id" => 801, "release_date" => "2026-12-25"})

        conn |> Plug.Conn.put_resp_header("etag", ~s(W/"held")) |> Req.Test.json(body)
      end
    end)

    :ok
  end

  defp perform, do: Oban.Testing.perform_job(CheckJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)

  test "a referenced title the store lacks is first-contacted" do
    create_tracking_item(%{tmdb_id: 801, media_type: :movie, stored: false})

    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/movie/801", []}
    assert %Store.TitleRecord{etag: ~s(W/"held")} = Store.get({801, :movie})
  end

  test "a due referenced title is checked with its etag; an undue one is not" do
    due = create_tracking_item(%{tmdb_id: 800, media_type: :tv_series})
    _fresh = create_tracking_item(%{tmdb_id: 802, media_type: :movie})
    backdate(Store.get({800, :tv_series}), :next_check_at, ~U[2026-01-01 00:00:00Z])
    Store.get({800, :tv_series}) |> force_attrs(etag: ~s(W/"held"))

    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/tv/800", [~s(W/"held")]}
    refute_receive {:tmdb_hit, "/3/movie/802", _validator}
    assert DateTime.compare(Store.get({800, :tv_series}).fetched_at, ~U[2026-01-01 00:00:00Z]) == :gt
    _ = due
  end

  test "a due title nothing references is left alone" do
    record = create_title_record(%{tmdb_id: 803, media_type: :movie})
    backdate(record, :next_check_at, ~U[2026-01-01 00:00:00Z])

    assert :ok = perform()
    refute_receive {:tmdb_hit, _path, _validator}
  end

  test "held while TMDB is down: no request, nothing lost" do
    create_tracking_item(%{tmdb_id: 801, media_type: :movie, stored: false})
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

    assert :ok = perform()
    refute_receive {:tmdb_hit, _path, _validator}
    assert Store.get({801, :movie}) == nil
  end
end
```

The factory option `stored: false` is added in Task 6 (`create_tracking_item` stores a title record by default from Task 6 on). Until then this test is written but the factory work lands in Task 6 — run Task 3's tests after Task 6's factory change if the option is missing; the plan orders it so, see Task 6 Step 2.

- [ ] **Step 2: Implement** `lib/media_centaur/tmdb/check_job.ex`:

```elixir
defmodule MediaCentaur.TMDB.CheckJob do
  @moduledoc """
  The tick that asks TMDB only what is due (ADR-071 §3). Every 15
  minutes, and once at boot: the referenced titles the store does not
  hold yet are first-contacted, bounded per tick so a fresh install
  fills in over a few ticks rather than one burst; then every stored
  title that is due and scheduled (`TMDB.References.scheduled/0`) is
  checked — one conditional request, a 304 when nothing changed.

  Held like every metered job: when TMDB is unavailable the tick does
  nothing and the next one tries again. Nothing is lost, because
  due-ness is a stored fact. A title whose request fails is logged and
  skipped; the tick goes on. Between titles the tick re-reads `up?/1`,
  so an outage that begins mid-tick stops the spending at once.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.{References, Store}

  @first_contacts_per_tick 50

  @impl Oban.Worker
  def perform(_job) do
    if IntegrationAvailability.available?(:tmdb) do
      tick()
    else
      Log.debug(:tmdb, "check tick held — TMDB is unavailable")
    end

    :ok
  end

  defp tick do
    scheduled = References.scheduled()
    stored = Store.get_many(scheduled)

    contacted =
      scheduled
      |> Enum.reject(&Map.has_key?(stored, &1))
      |> Enum.take(@first_contacts_per_tick)
      |> Enum.count(fn ref -> up_and(fn -> Store.ensure(ref) end) end)

    outcomes =
      DateTime.utc_now()
      |> Store.due()
      |> Enum.map(&{&1.tmdb_id, &1.media_type})
      |> Enum.filter(&MapSet.member?(scheduled, &1))
      |> Enum.map(fn ref -> up_and(fn -> Store.check(ref) end) end)

    changed = Enum.count(outcomes, &match?({:ok, :changed, _record}, &1))
    checked = Enum.count(outcomes, &match?({:ok, _outcome, _record}, &1))

    if contacted + checked > 0 do
      Log.info(:tmdb, "check tick — #{contacted} first contacts, #{checked} checks, #{changed} changed")
    end
  end

  # Spend a request only while TMDB is still up; a failure is the title's, not the tick's.
  defp up_and(request) do
    if IntegrationAvailability.up?(:tmdb) do
      case request.() do
        {:error, reason} ->
          Log.info(:tmdb, "check skipped a title — #{inspect(reason)}")
          false

        ok ->
          ok
      end
    else
      false
    end
  end
end
```

(`Enum.count` over `up_and(...)` for first contacts counts truthy `{:ok, _}` results; adjust to `Enum.count(&match?({:ok, _}, &1))` if the truthiness reads badly.)

`config/config.exs` crontab, with comments in the file's style:

```elixir
       # Asks TMDB only what is due: first-contacts referenced titles the
       # store lacks, checks stored titles whose next_check_at has passed
       # (ADR-071). @reboot fills the store on the first boot after a
       # release; the quarter-hour tick then keeps it current.
       {"@reboot", MediaCentaur.TMDB.CheckJob},
       {"7-59/15 * * * *", MediaCentaur.TMDB.CheckJob},
```

`lib/media_centaur/tmdb.ex` exports add `CheckJob`.

- [ ] **Step 3: Run** the CheckJob tests (after Task 6's factory change) → pass. **Step 4: Commit** `feat(tmdb): CheckJob — first-contact what is referenced, check what is due, hold when TMDB is down`.

---

### Task 4: `ReleaseTracking.Calendar` — the pure half of `Helpers`

**Files:** create `lib/media_centaur/release_tracking/calendar.ex`, `test/media_centaur/release_tracking/calendar_test.exs`.

- [ ] **Step 1: Failing tests** (port `helpers_tv_calendar_test.exs`'s case to payloads, no stub):

```elixir
defmodule MediaCentaur.ReleaseTracking.CalendarTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Calendar

  @today ~D[2026-09-17]

  defp show do
    %{"id" => 424_242, "name" => "Sample Show", "number_of_seasons" => 2,
      "next_episode_to_air" => %{"air_date" => "2026-09-24", "season_number" => 2, "episode_number" => 11},
      "seasons" => [%{"season_number" => 0, "episode_count" => 3}, %{"season_number" => 1, "episode_count" => 22}, %{"season_number" => 2, "episode_count" => 13}]}
  end

  defp season_two do
    %{"season_number" => 2,
      "episodes" => Enum.map(1..13, fn n -> %{"episode_number" => n, "name" => "Episode #{n}", "air_date" => Date.to_iso8601(Date.add(@today, (n - 10) * 7))} end)}
  end

  test "tv_releases/4 lists the episodes after the library's last one" do
    assert Enum.map(Calendar.tv_releases(show(), [season_two()], 2, 10), & &1.episode_number) == [11, 12, 13]
  end

  test "tv_releases/4 falls back to next_episode_to_air when no stored season yields an episode" do
    assert [%{season_number: 2, episode_number: 11, air_date: ~D[2026-09-24]}] = Calendar.tv_releases(show(), [], 2, 10)
  end

  test "season_sizes/3 sizes a stored season by aired episodes and the rest by episode_count, specials excluded" do
    assert Calendar.season_sizes(show(), [season_two()], @today) == %{"1" => 22, "2" => 10}
  end

  test "seasons_wanted/2 is the library's last season and the next season to air" do
    assert Calendar.seasons_wanted(show(), 1) == [1, 2]
    assert Calendar.seasons_wanted(show(), 0) == [1, 2]
    assert Calendar.seasons_wanted(show(), 2) == [2]
  end

  test "movie_releases/1 carries the film's own id as the part" do
    movie = %{"id" => 550, "title" => "Sample Movie", "release_date" => "2026-10-01"}
    assert [%{part_tmdb_id: 550, release_type: "theatrical", air_date: ~D[2026-10-01], season_number: nil, episode_number: nil}] = Calendar.movie_releases(movie)
  end
end
```

- [ ] **Step 2: Implement** by moving the bodies of `Helpers.seasons_to_fetch/2`, the release computation inside `fetch_tv_releases/5`, `season_sizes/3`, `aired_count/2` and `fetch_movie_releases/1` into `Calendar` (`tv_releases/4`, `season_sizes/3`, `seasons_wanted/2`, `movie_releases/1`), delegating from the old `Helpers` names until Task 6 deletes them. Moduledoc: "Pure. The calendar a tracked title's stored payloads imply — what `TMDB.Store` holds becomes rows here, never a request."

- [ ] **Step 3: Run** `agent-mix test test/media_centaur/release_tracking/` → pass. **Step 4: Commit** `refactor(release_tracking): Calendar — releases and season sizes as a pure function of stored payloads`.

---

### Task 5: Release tracking rebuilds from the store on change

**Files:** create `lib/media_centaur/release_tracking/tmdb_listener.ex`, `test/media_centaur/release_tracking/title_changed_test.exs`; modify `lib/media_centaur/release_tracking.ex`, `lib/media_centaur/application.ex`.

- [ ] **Step 1: Failing tests**

```elixir
defmodule MediaCentaur.ReleaseTracking.TitleChangedTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    ReleaseTracking.subscribe()
    :ok
  end

  test "a changed tracked series rebuilds its calendar from the stored season" do
    item = create_tracking_item(%{tmdb_id: 900, media_type: :tv_series, last_library_season: 1, last_library_episode: 2})
    season = TmdbStubs.season_detail(%{"season_number" => 1, "episodes" => [
      %{"episode_number" => 2, "name" => "Two", "air_date" => "2026-01-01"},
      %{"episode_number" => 3, "name" => "Three", "air_date" => "2026-12-01"}]})
    create_season_record(%{tmdb_id: 900, season_number: 1, payload: season})

    assert :ok = ReleaseTracking.title_changed({900, :tv_series})
    assert [%{episode_number: 3, air_date: ~D[2026-12-01]}] = ReleaseTracking.list_releases_for_item(item.id)
    assert_receive {:releases_updated, [item_id]}
    assert item_id == item.id
  end

  test "a changed tracked movie rebuilds its typed dates" do
    item = create_tracking_item(%{tmdb_id: 901, media_type: :movie, payload: TmdbStubs.movie_detail(%{"id" => 901, "release_date" => "2026-11-11"})})
    assert :ok = ReleaseTracking.title_changed({901, :movie})
    assert [%{release_type: "theatrical", air_date: ~D[2026-11-11]}] = ReleaseTracking.list_releases_for_item(item.id)
  end

  test "a title nobody tracks is ignored" do
    create_title_record(%{tmdb_id: 902, media_type: :movie})
    assert :ok = ReleaseTracking.title_changed({902, :movie})
    refute_receive {:releases_updated, _ids}
  end

  test "a wanted season the store lacks is first-contacted before the rebuild" do
    test_pid = self()
    Req.Test.stub(:tmdb, fn conn ->
      send(test_pid, {:tmdb_hit, conn.request_path})
      Req.Test.json(conn, TmdbStubs.season_detail(%{"season_number" => 2, "episodes" => [%{"episode_number" => 1, "name" => "S2E1", "air_date" => "2026-12-24"}]}))
    end)
    series = TmdbStubs.tv_detail(%{"id" => 903, "status" => "Returning Series", "number_of_seasons" => 2,
      "next_episode_to_air" => %{"air_date" => "2026-12-24", "season_number" => 2, "episode_number" => 1},
      "seasons" => [%{"season_number" => 1, "episode_count" => 10}, %{"season_number" => 2, "episode_count" => 10}]})
    item = create_tracking_item(%{tmdb_id: 903, media_type: :tv_series, payload: series, last_library_season: 1, last_library_episode: 10})

    assert :ok = ReleaseTracking.title_changed({903, :tv_series})
    assert_receive {:tmdb_hit, "/3/tv/903/season/2"}
    assert [%{season_number: 2, episode_number: 1}] = ReleaseTracking.list_releases_for_item(item.id)
  end
end
```

- [ ] **Step 2: Implement** in `release_tracking.ex`:

```elixir
  @doc """
  A stored title changed (`{:tmdb_title_changed, ref}`): when it is
  tracked, its calendar is rebuilt from the store — the wanted seasons
  the store lacks are first-contacted, the release rows replaced through
  `replace_releases!/3`, in-library marks and the want ledger synced,
  artwork completed, and `{:releases_updated, [item.id]}` published.
  Nothing when the title is not tracked.
  """
  @spec title_changed(TMDB.Store.ref()) :: :ok
  def title_changed({tmdb_id, media_type}) do
    case get_item_by_tmdb(tmdb_id, media_type) do
      nil -> :ok
      %Item{} = item -> rebuild_calendar(item)
    end
  end

  @doc "Rebuilds a tracked item's releases from its stored title and seasons."
  @spec rebuild_calendar(Item.t()) :: :ok | {:error, term()}
  def rebuild_calendar(%Item{} = item) do
    with {:ok, record} <- TMDB.Store.ensure({item.tmdb_id, item.media_type}),
         {:ok, seasons} <- ensure_wanted_seasons(item, record) do
      releases = Calendar.releases(item, record.payload, Enum.map(seasons, & &1.payload))
      replace_releases!(item, releases, persister_for(item))
      mark_in_library_releases(item)
      sync_wants(item)
      Helpers.download_images_async(item, item.tmdb_id, record.payload)
      broadcast_releases_updated([item.id])
      :ok
    end
  end
```

with `Calendar.releases/3` dispatching on `item.media_type` (tv → `tv_releases(payload, seasons, item.last_library_season, item.last_library_episode)`; movie → `movie_releases(payload)`), `persister_for/1` (`&persist_release!/2` for tv, `&persist_movie_release!/2` for movies), and `ensure_wanted_seasons/2` calling `TMDB.Store.ensure_season/2` for each of `Calendar.seasons_wanted(record.payload, item.last_library_season)` and returning `{:ok, TMDB.Store.seasons(item.tmdb_id)}` (a season first contact that fails is logged and skipped, not fatal). Check `get_item_by_tmdb/2`'s existing signature (`release_tracking.ex:130`).

`tmdb_listener.ex`, modelled on `LibraryListener`:

```elixir
defmodule MediaCentaur.ReleaseTracking.TmdbListener do
  @moduledoc "Subscribes to `Topics.tmdb_titles/0` and hands a changed title to `ReleaseTracking.title_changed/1`. Skipped in `:test`; tests call the function."
  use GenServer
  alias MediaCentaur.{ReleaseTracking, Topics}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.tmdb_titles())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:tmdb_title_changed, ref}, state) do
    ReleaseTracking.title_changed(ref)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
```

`application.ex` `pubsub_listeners/1`: add `MediaCentaur.ReleaseTracking.TmdbListener` after `LibraryListener`. Boundary: `ReleaseTracking` exports add `TmdbListener`. Add `alias MediaCentaur.ReleaseTracking.Calendar` and `alias MediaCentaur.TMDB` as needed.

- [ ] **Step 3: Run** → pass (the tests rely on the Task 6 factory storing a title record; run after Task 6 if `create_tracking_item` does not yet). **Step 4: Commit** `feat(release_tracking): a changed stored title rebuilds the tracked calendar`.

---

### Task 6: The tracked item reads the store; the refresher goes

**Files:** create migration `priv/repo/migrations/20260920130000_release_tracking_items_read_the_store.exs`, `lib/media_centaur/release_tracking/titles.ex`, `lib/media_centaur/release_tracking/sweep_job.ex`; modify `item.ex`, `identity.ex`, `onboarding.ex`, `helpers.ex`, `release_tracking.ex`, `drop_planner.ex` (log lines only), `settings/config.ex`, `settings_live.ex`, `acquisition_section.ex`, `application.ex`, `config/config.exs`, `test/support/factory.ex`; delete `refresher.ex`, `refresh_schedule.ex`, `test/media_centaur/release_tracking/{refresher_test,refresh_schedule_test,helpers_tv_calendar_test}.exs`; modify `set_rung_test.exs`, `drop_planner_test.exs`, `settings_live_test.exs:580-591`, `settings_live_acquisition_test.exs:325-336`, `test/media_centaur/log/component_test.exs:45`, `test/media_centaur/credo/checks/log_component_matches_context_test.exs:77`.

- [ ] **Step 1: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.ReleaseTrackingItemsReadTheStore do
  @moduledoc """
  A tracked item stops copying TMDB facts (campaign `tmdb-fetch-policy`
  Phase 2, ADR-071): name, year, imdb_id, tvdb_id, original_title,
  origin_country, season_sizes and last_refreshed_at were written by the
  refresher from every fetch and are now read from the TMDB store, which
  `TMDB.CheckJob` fills at boot for every tracked title the store lacks.
  The refresher's two interval settings and its sweep anchor go with it.

  `down/0` restores the columns empty: nothing refills them, since the
  refresher that did no longer exists.
  """
  use Ecto.Migration

  @columns [:name, :year, :imdb_id, :tvdb_id, :original_title, :origin_country, :season_sizes, :last_refreshed_at]
  @settings_keys ["release_tracking_refresh_interval_hours", "release_tracking_sweep_interval_minutes", "release_tracking:last_swept_at"]

  def up do
    alter table(:release_tracking_items) do
      for column <- @columns, do: remove(column)
    end

    execute(fn ->
      for key <- @settings_keys, do: repo().query!("DELETE FROM settings_entries WHERE key = ?", [key])
    end)
  end

  def down do
    alter table(:release_tracking_items) do
      add :name, :string
      add :year, :integer
      add :imdb_id, :string
      add :tvdb_id, :string
      add :original_title, :string
      add :origin_country, {:array, :string}
      add :season_sizes, :map, null: false, default: %{}
      add :last_refreshed_at, :utc_datetime
    end
  end
end
```

Check `ecto_sqlite3` supports `remove/1` inside `alter table` (it does, via table rebuild) and whether `for` inside `alter` works — otherwise list eight `remove :column` lines.

- [ ] **Step 2: Factory** — `create_tracking_item/1` stores a title record unless `stored: false`, and `create_intent_for/2` stops reading `item.name`:

```elixir
  def create_tracking_item(attrs \\ %{}) do
    {rung, attrs} = Map.pop(attrs, :rung, :grab)
    {stored?, attrs} = Map.pop(attrs, :stored, true)
    {payload, attrs} = Map.pop(attrs, :payload)
    {name, attrs} = Map.pop(attrs, :name, "Test Tracked Series")
    tmdb_id = Map.get(attrs, :tmdb_id, :rand.uniform(999_999))
    media_type = Map.get(attrs, :media_type, :tv_series)
    attrs = attrs |> Map.put(:tmdb_id, tmdb_id) |> Map.put(:media_type, media_type)

    if stored? do
      payload = payload || default_tracked_payload(media_type, tmdb_id, name)
      {:ok, _record} = MediaCentaur.TMDB.Store.record_fetched({tmdb_id, media_type}, payload, ~s(W/"v1"))
    end

    {:ok, item} = ReleaseTracking.track_item(attrs)
    if rung, do: create_intent_for(item, rung, name)
    item
  end
```

with `default_tracked_payload/3` building a `tv_detail`/`movie_detail` carrying the name, and `create_intent_for/3` taking the name explicitly (update its callers). `build_tracking_item/1` drops `name`, `last_refreshed_at`, `tracking_mode`, `poster_path` defaults (the two dead fields were silently ignored).

- [ ] **Step 3: `Item`** — remove the eight fields and their changeset casts; `validate_required([:tmdb_id, :media_type])`; add virtual projections:

```elixir
    # Read from the TMDB store on load (`ReleaseTracking.Titles.attach/1`),
    # never stored: the title's name, and how many episodes each season
    # has — the drop planner's fit denominator.
    field :name, :string, virtual: true
    field :season_sizes, :map, virtual: true, default: %{}
```

Moduledoc: replace the copy-column paragraphs with "Everything TMDB says about the title lives in `TMDB.Store`; `name` and `season_sizes` are attached from it when items are loaded."

- [ ] **Step 4: `ReleaseTracking.Titles`**

```elixir
defmodule MediaCentaur.ReleaseTracking.Titles do
  @moduledoc """
  What the store says about tracked items. `attach/1` fills the virtual
  `name` and `season_sizes` of loaded items from their stored title and
  seasons in two queries, so every reader that shows a tracked title's
  name or plans against its season sizes reads one representation.
  `payload!/1` is the acquisition path's read: the stored payload, first
  contact when the store lacks it, because a plan's identity must be
  right and a tracked title is a reference the app holds.
  """
  alias MediaCentaur.ReleaseTracking.{Calendar, Item}
  alias MediaCentaur.TMDB.Store

  @spec attach([Item.t()] | Item.t() | nil) :: [Item.t()] | Item.t() | nil
  def attach(nil), do: nil
  def attach(%Item{} = item), do: item |> List.wrap() |> attach() |> hd()

  def attach(items) when is_list(items) do
    records = Store.get_many(Enum.map(items, &{&1.tmdb_id, &1.media_type}))
    seasons = items |> Enum.filter(&(&1.media_type == :tv_series)) |> Enum.map(& &1.tmdb_id) |> Store.seasons_for()
    today = Date.utc_today()

    Enum.map(items, fn item ->
      case Map.get(records, {item.tmdb_id, item.media_type}) do
        nil -> item
        record ->
          season_payloads = seasons |> Map.get(item.tmdb_id, []) |> Enum.map(& &1.payload)
          %{item | name: name(record), season_sizes: sizes(item, record, season_payloads, today)}
      end
    end)
  end

  @spec payload!(Item.t()) :: map()
  def payload!(%Item{} = item) do
    {:ok, record} = Store.ensure({item.tmdb_id, item.media_type})
    record.payload
  end

  defp name(%{media_type: :movie, payload: payload}), do: payload["title"]
  defp name(%{media_type: :tv_series, payload: payload}), do: payload["name"]
  defp sizes(%Item{media_type: :tv_series}, record, season_payloads, today), do: Calendar.season_sizes(record.payload, season_payloads, today)
  defp sizes(_item, _record, _seasons, _today), do: %{}
end
```

Add `Store.seasons_for([tmdb_id]) :: %{tmdb_id => [SeasonRecord]}` (one query, grouped) with a test. `payload!/1` raises on a TMDB failure at first contact — the drop planner's tick rescues per item today? Check `drop_planner.ex:63` flow; if not, make `Identity.for_item/1` return a minimal identity (`title: nil` is not allowed by `@enforce_keys`… `TitleIdentity.new/1` sets `title: fetch(attrs, :title)` — nil passes `new/1` since it builds the struct directly). Decide: `payload!/1` → `payload/1` returning `{:ok, map} | {:error, reason}`, and `Identity.for_item/1` falls back to `TitleIdentity.new(%{tmdb_type: item.media_type, tmdb_id: item.tmdb_id, title: item.name})` on error (name may be nil; the matcher treats missing identity as optional evidence).

- [ ] **Step 5: Loaders attach** — in `release_tracking.ex`: `list_all_items/0` (drop `order_by: [asc: i.name]`; sort in Elixir by attached name after `Titles.attach/1`), `get_item/1`, `get_item_by_tmdb/2`, and every function that preloads `:item` for display (`list_releases/0`, `list_releases_between/3`, `list_releases_for_item/1` if it preloads) → pipe items through `Titles.attach/1`. `list_releases_between/3` keeps `name: release.item.name` (now virtual). `UpcomingFeed.event_from/2` reads `item.name` — unchanged, provided its releases came through a loader that attached (check `IncomingLive`'s loader; if it queries releases itself, attach there).

- [ ] **Step 6: `Identity`** — `for_item/1`:

```elixir
  def for_item(%Item{} = item) do
    case Titles.payload(item) do
      {:ok, payload} -> TitleIdentity.from_payload(item.media_type, payload)
      {:error, _reason} -> TitleIdentity.new(%{tmdb_type: item.media_type, tmdb_id: item.tmdb_id, title: item.name})
    end
  end
```

`for_want/2`: `title: want.title || identity.title`. Moduledoc's "carried on the item" sentences → "read from the store".

- [ ] **Step 7: `Onboarding`** — both branches through the store:

```elixir
  defp do_onboard(%Title{media_type: :tv_series} = title, start_season, start_episode) do
    with {:ok, record} <- Store.ensure({title.tmdb_id, :tv_series}),
         {:ok, item} <- track(%{tmdb_id: title.tmdb_id, media_type: :tv_series, last_library_season: start_season, last_library_episode: start_episode}) do
      seasons = ensure_seasons(item, record)
      all_releases = Calendar.tv_releases(record.payload, Enum.map(seasons, & &1.payload), start_season, start_episode)
      releases = if start_season == 0 and start_episode == 0, do: Enum.reject(all_releases, &Release.released?/1), else: all_releases
      persist_releases(item, releases)
      schedule_image_downloads(item, title.tmdb_id, record.payload)
      {:ok, item}
    end
  end

  defp do_onboard(%Title{media_type: :movie} = title, _start_season, _start_episode) do
    with {:ok, record} <- Store.ensure({title.tmdb_id, :movie}),
         {:ok, item} <- track(%{tmdb_id: title.tmdb_id, media_type: :movie}) do
      persist_movie_releases(item, Extractor.extract_movie_release_dates(record.payload))
      schedule_image_downloads(item, title.tmdb_id, record.payload)
      {:ok, item}
    end
  end
```

`track/1` wraps `ReleaseTracking.track_item/1` and maps the changeset through the existing `track_item_error/1`. `ensure_seasons/2` first-contacts `Calendar.seasons_wanted(record.payload, item.last_library_season)` and returns the stored seasons. The `Client` alias goes.

- [ ] **Step 8: `Helpers`** — delete `fetch_tv_releases/5`, `seasons_to_fetch/2`, `fetch_collection_releases/1`, `fetch_movie_releases/1`, `normalize_collection_releases/1`, `season_sizes/3`, `aired_count/2` (now `Calendar`); keep the image functions, `parse_tmdb_id/1`, `find_last_library_episode/1`. Moduledoc trimmed accordingly. Delete `test/media_centaur/release_tracking/helpers_tv_calendar_test.exs` (its case lives in `calendar_test.exs`).

- [ ] **Step 9: Retire the refresher** — delete `refresher.ex`, `refresh_schedule.ex`, `refresher_test.exs`, `refresh_schedule_test.exs`; remove from `application.ex`; the `complete_movie_tracking_for/1` tests inside `refresher_test.exs:302-377` test a `ReleaseTracking` function, not the refresher — move them into `test/media_centaur/release_tracking/library_events_test.exs` (or a new `complete_movie_tracking_test.exs`) unchanged. Update `test/media_centaur/log/component_test.exs:45` and `test/media_centaur/credo/checks/log_component_matches_context_test.exs:77` (they name `Refresher` as a module→component example — substitute `MediaCentaur.ReleaseTracking.SweepJob`).

- [ ] **Step 10: `SweepJob`**

```elixir
defmodule MediaCentaur.ReleaseTracking.SweepJob do
  @moduledoc """
  The want-ledger sweep, every 15 minutes: `sync_wants/1` for every
  tracked item, then `{:tracking_sweep_completed}` — the drop planner's
  clock (`Acquisition.Reactor`). No TMDB request. Took over the
  refresher's second timer when the refresher was retired (ADR-071).
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  alias MediaCentaur.{ReleaseTracking, Topics}

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(ReleaseTracking.list_all_items(), &ReleaseTracking.sync_wants/1)
    Topics.publish(Topics.release_tracking_updates(), {:tracking_sweep_completed})
    :ok
  end
end
```

Cron row `{"*/15 * * * *", MediaCentaur.ReleaseTracking.SweepJob}` with a comment. Test `sweep_job_test.exs`: ports `refresher_test.exs:255-292` ("marks releases with past air dates as released", "broadcasts {:tracking_sweep_completed}") to `Oban.Testing.perform_job(SweepJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)`. `wants_test.exs:352` (`Refresher.sweep_now()`) → the same `perform_job`. Boundary: `ReleaseTracking` exports add `SweepJob`.

- [ ] **Step 11: Settings** — `config.ex`: remove both keys from `@runtime_settable_keys` and the defaults map. `acquisition_section.ex`: remove the *Release tracking* card, `refresh_ladder/0`, `refresh_hours/1`. `settings_live.ex`: remove `handle_event("set_release_tracking_interval", …)`, `@refresh_hours_ladder`, the `load_config/0` entry. Delete the two tests. `page_smoke_test.exs` still renders `?section=acquisition`.

- [ ] **Step 12: `drop_planner.ex`** — `span_sizes: item.season_sizes` and the log lines keep working through the virtual fields; nothing to change unless the compiler says otherwise. `drop_planner_test.exs`: `create_tracked_show(%{season_sizes: %{"1" => 22}})` → the season sizes now come from the payload — pass a `payload:` with `"seasons" => [%{"season_number" => 1, "episode_count" => 22}]` instead (find the helper in that test file).

- [ ] **Step 13: Run** `agent-mix test` (full, foreground) — expect fallout in tests that built items with `name:`/`season_sizes:`/`last_refreshed_at:` attrs; fix each by passing `name:`/`payload:` to the factory. Then Tasks 3 and 5 tests. Zero warnings.

- [ ] **Step 14: Commit** `feat(release_tracking): the tracked item reads the store — copy columns dropped, refresher retired, sweep on cron, interval setting removed`.

---

### Task 7: *Refresh from TMDB*

**Files:** create `lib/media_centaur_web/components/title/refresh_from_tmdb.ex`, `storybook/title/refresh_from_tmdb.story.exs`, `decisions/user-interface/2026-09-20-044-refresh-from-tmdb.md`; modify `manage_panel.ex` (`:202-212` neighbourhood), `detail_panel.ex` tracking card (`:622-638`), `title_detail_host.ex` (`handle_title_event`), `library_events.ex` (`@events`, handler), `title_detail_host/acquisition.ex` or a new `title_detail_host/tmdb_events.ex`; tests `library_events_test.exs`, `library_live_test.exs:1192-1205`, a host test for the unowned case; `docs/input-system.md:308`; `storybook/title/_title.index.exs`.

**Behaviour (design §2.7):** one button, *Refresh from TMDB*, `variant="neutral" size="sm"` on the Manage toolbar between *Rematch* and *Refresh artwork* (owned titles), and `variant="dismiss" size="xs"` under the tracking switches (tracked titles without a Manage sheet — `Detail.Logic` says which; show it when `detail.tracking` is present and the title is not owned). Click → `start_async({:refresh_from_tmdb, ref}, fn -> TMDB.Store.check(ref) end)`; on result a flash: `{:ok, :unchanged, _}` → `"Checked TMDB — nothing has changed."`; `{:ok, :changed, _}` → `"Updated from TMDB."`; `{:error, _}` → `"TMDB didn't answer — try again later."`. Owned entity ref: `EntityImageContext.find_tmdb_context(entity_id, type)` gives `{tmdb_id, media_type}`-equivalent (check its return shape at `entity_image_context.ex:31-60`); no TMDB id → `"No TMDB match — Rematch first."` (the artwork button's wording). While the async runs, the button label reads *Checking…* and is disabled — a `checking?` boolean attr on both hosts, mirroring `@deleting`.

- [ ] **Step 1: Failing tests** — `library_events_test.exs`: the flash mapping for the three outcomes; `library_live_test.exs` toolbar test asserts a fourth button `button[phx-click='refresh_from_tmdb']`; a `title_detail_host` test opens a tracked unowned title (factory `create_tracking_item` + intent) and asserts the control is present and, after `render_click` + `render_async`, the flash text against a 304 stub.

- [ ] **Step 2: Implement** the component (`refresh_from_tmdb/1` with attrs `id`, `ref` or `entity_id`, `variant`, `checking?`), mount it in both hosts, add the event to `LibraryEvents.@events` for the owned path and a `handle_title_event("refresh_from_tmdb", …)` clause for the unowned path, and the `handle_async` result clause (one module: `TitleDetailHost.TmdbEvents`). The component carries `data-nav-item tabindex="0"` (toolbar order = DOM order).

- [ ] **Step 3: Story** `storybook/title/refresh_from_tmdb.story.exs` with variations `:toolbar` (neutral/sm), `:tracking` (dismiss/xs), `:checking` (disabled, *Checking…*); index entry. `manage_panel.story.exs` needs no new variation (the button renders in every variation; `:tmdb_not_ready` still hides it). `agent-mix storybook.compile`/render tests run in precommit.

- [ ] **Step 4: UIDR-044** — title "One control to ask TMDB again: Refresh from TMDB", context (the owner's "just in case" against a policy that never fetches on open), decision (where it sits on each surface, the three outcomes, no confirm step), consequences; amends UIDR-042 (the tracking card gains a title-wide action). `scripts/gen-decisions-index`.

- [ ] **Step 5: Docs** — `docs/input-system.md:308` enumeration; wiki in Task 8.

- [ ] **Step 6: Run** the web tests + storybook tests → pass. **Step 7: Commit** `feat(web): Refresh from TMDB on the Manage view and the tracking card (UIDR-044)`.

---

### Task 8: Wiki, docs, campaign

- [ ] **Release-Tracking.md** — delete *Tuning the schedule* (`:41-43`); add a section *When Media Centaur asks TMDB*: a tracked title is checked the day after its next known date, or weekly when none is known; a title whose release is over is not checked again; *Refresh from TMDB* forces a check. Fix `:89`.
- [ ] **Settings-Reference.md** — remove the *Release tracking* table (`:160-164`); add *Refresh from TMDB* beside *Refresh artwork* at `:216`.
- [ ] **Browsing-Your-Library.md** — `:91` tool list; a paragraph for *Refresh from TMDB* after `:94`.
- [ ] **Keyboard-and-Gamepad.md** — `:78` enumeration.
- [ ] **Troubleshooting.md** — `:97` (held checks resume within a quarter hour), `:98` (the store keeps TMDB's answer and asks only whether it changed), `:156` (the 24-hour sentence → "wait for the next check, or press Refresh from TMDB on the title"; filter `:tmdb`).
- [ ] **TMDB-API-Key.md** — *Caching* section gains the store: one record per title, checks by ETag, the `checked … — unchanged` console line, `stored … — first contact`.
- [ ] **In-repo docs** — `docs/tmdb.md` store section (Phase 2 state); `docs/architecture.md` supervision tree (refresher → listener + two cron jobs); `docs/GLOSSARY.md` *TMDB store* rows (scheduled-ness is a query; *Reference*); campaign file (Status, Decisions, Next steps → Phase 3); `campaigns/collection-identity.md` dated note that the refresher's collection branch is gone; `campaigns/README.md`.
- [ ] **Commit** wiki (`wiki: release tracking asks TMDB only when due; Refresh from TMDB`) and repo docs separately.

---

### Task 9: Gate and the dev node

- [ ] `agent-mix precommit` (foreground, timeout 600000) → PASSED.
- [ ] Restart the dev service so the new cron rows and listener start: `systemctl --user restart media-centaur-dev`; wait for the listener on :2160; confirm the migration ran (boot migrates) with `mc-eval 'Ecto.Migrator.migrations(MediaCentaur.Repo) |> Enum.filter(&(elem(&1, 0) == :down))'` → `[]`.
- [ ] Watch the `@reboot` tick: `mc-eval` the `:tmdb` console lines — expect `check tick — N first contacts …` with N = tracked items the store lacked; `Repo.aggregate(TitleRecord, :count)` ≥ tracked items.
- [ ] Force a due check: `backdate`-equivalent via `mc-eval 'MediaCentaur.TMDB.Store.get({<tracked id>, :movie}) |> Ecto.Changeset.change(next_check_at: ~U[2026-01-01 00:00:00Z]) |> MediaCentaur.Repo.update!()'` then `mc-eval 'Oban.insert!(MediaCentaur.TMDB.CheckJob.new(%{}))'` and read the console: one `checked … — unchanged` (304), `Traffic.recent()` shows `cache: :conditional, status: 304`.
- [ ] Record in the campaign: requests per cycle before (12/day for 5 titles) and after (0 for settled, 1 revalidation per due check).

## Self-review notes

* Design §5 Phase 2 items: CheckJob ✔ (T3); release rows rebuilt on change ✔ (T5); Item shrinks ✔ (T6); refresher and interval setting go ✔ (T6); Refresh from TMDB ✔ (T7); one-time backfill ✔ (CheckJob `@reboot` first contacts, T3); wiki ✔ (T8); measured on the dev node ✔ (T9). Row R (References) pulled forward from Phase 5 because scheduling needs it (T1).
* Types: refs are `{tmdb_id, media_type}` everywhere new; the artwork cache alone keeps `{media_type, tmdb_id}` internally and converts at its boundary.
