# TMDB fetch policy — Phase 1: the store, filled organically

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app one durable record per TMDB title — payload, ETag, fetch time, due time — that fills from the detail fetches callers already make, with the check path (conditional revalidation) built and tested but not yet scheduled.

**Architecture:** `MediaCentaur.TMDB.Store` owns two tables (`tmdb_titles`, `tmdb_seasons`) and is the only writer. `TMDB.Schedule` is a pure function from stored payloads and today to the next due time. `TMDB.Client.detail/2` is the one request path that can carry the store's own `If-None-Match`; `HttpClient.Cache` stands aside for any request the caller made conditional. A transitional write-through in `TMDB.Client` records every detail payload fetched, so the store fills while every caller still fetches as before. Design: [`docs/superpowers/specs/2026-09-20-tmdb-fetch-policy-design.md`](../specs/2026-09-20-tmdb-fetch-policy-design.md).

**Tech Stack:** Elixir, Ecto (SQLite via `ecto_sqlite3`, `:map` columns), Req + `Req.Test` stubs, Phoenix.PubSub via `MediaCentaur.Topics`, ExUnit through `MediaCentaur.DataCase` / `MediaCentaur.Case`.

**House rules that bind every task:** run `mix` only as `~/scripts/agents/agent-mix` (a bare `mix` in this checkout takes the dev server down). Test-first: write the failing test, run it, see it fail for the stated reason, implement, run, commit. No real title names in fixtures (`Sample Movie`, `Sample Show`). Zero warnings. Never `Repo.insert` in a test — factories only (MC0023). Every test module states `async:` (MC0035). Commit messages end with the session trailer:

```
Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF
```

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/tmdb/schedule.ex` | **Create.** Pure: settled rule, next known event, due time, open-season rule. |
| `lib/media_centaur/tmdb/store.ex` | **Create.** Context: `get/1`, `get_season/2`, `seasons/1`, `due/1`, `ensure/2`, `ensure_season/3`, `check/2`, `record_fetched/3`, `record_season_fetched/4`, `trim_payload/1`. The only writer. |
| `lib/media_centaur/tmdb/store/title_record.ex` | **Create.** Schema `tmdb_titles`. |
| `lib/media_centaur/tmdb/store/season_record.ex` | **Create.** Schema `tmdb_seasons`. |
| `priv/repo/migrations/20260920100000_create_tmdb_store.exs` | **Create.** Both tables, additive. |
| `lib/media_centaur/tmdb/client.ex` | **Modify.** `detail/2` (conditional request path), `:conditional` log source, detail request builders shared with `get_*`, transitional write-through, search-query normalisation. |
| `lib/media_centaur/http_client/cache.ex` | **Modify.** Pass-through for caller-conditional requests; `:conditional` outcome. |
| `lib/media_centaur/tmdb/identifiers.ex` | **Modify.** Delete `fetch/3` and the `Client` alias. |
| `lib/media_centaur/topics.ex` | **Modify.** `tmdb_titles/0`. |
| `lib/media_centaur/tmdb.ex` | **Modify.** Boundary exports; moduledoc (TMDB now owns data). |
| `test/support/factory.ex` | **Modify.** `build_title_record/1`, `create_title_record/1`, `create_season_record/1`. |
| `test/media_centaur/tmdb/schedule_test.exs` | **Create.** |
| `test/media_centaur/tmdb/store_test.exs` | **Create.** |
| `test/media_centaur/tmdb/client_test.exs` | **Modify.** `detail/2`, write-through, search normalisation. |
| `test/media_centaur/http_client/cache_test.exs` | **Modify.** Pass-through test. |
| `test/media_centaur/tmdb/identifiers_test.exs` | **Modify.** Remove the three `fetch/3` tests. |
| `decisions/architecture/2026-09-20-071-tmdb-store-one-record-per-title.md` | **Create.** |
| `decisions/architecture/2026-09-04-064-outbound-http-seam.md` | **Modify.** Dated amendment. |
| `decisions/README.md` | **Regenerate** with `scripts/gen-decisions-index`. |
| `docs/GLOSSARY.md`, `docs/tmdb.md`, `campaigns/tmdb-fetch-policy.md` | **Modify.** |

---

### Task 1: `TMDB.Schedule` — the pure due-time rule

**Files:**
- Create: `lib/media_centaur/tmdb/schedule.ex`
- Test: `test/media_centaur/tmdb/schedule_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.TMDB.ScheduleTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.Schedule

  @today ~D[2026-09-20]
  @fetched_at ~U[2026-09-20 08:00:00Z]
  @heartbeat ~U[2026-09-27 08:00:00Z]

  defp movie(overrides), do: Map.merge(%{"id" => 1, "title" => "Sample Movie", "status" => "Released"}, overrides)

  defp us_dates(entries) do
    %{
      "release_dates" => %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" => Enum.map(entries, fn {type, date} -> %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"} end)
          }
        ]
      }
    }
  end

  defp day_after_noon(date), do: DateTime.new!(Date.add(date, 1), ~T[12:00:00], "Etc/UTC")

  describe "plan/5 for a movie" do
    test "a movie past its digital release is settled and never due" do
      payload = movie(Map.merge(%{"release_date" => "2026-05-01"}, us_dates([{3, ~D[2026-05-01]}, {4, ~D[2026-07-01]}])))

      assert %{settled?: true, next_check_at: nil, next_event_on: nil} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a theatrical movie with a digital date ahead is due the day after it" do
      payload = movie(Map.merge(%{"release_date" => "2026-09-01"}, us_dates([{3, ~D[2026-09-01]}, {4, ~D[2026-09-23]}])))

      assert %{settled?: false, next_event_on: ~D[2026-09-23], next_check_at: next_check_at} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)

      assert next_check_at == day_after_noon(~D[2026-09-23])
    end

    test "an event more than a week away yields to the heartbeat" do
      payload = movie(Map.merge(%{"release_date" => "2026-12-25"}, us_dates([{3, ~D[2026-12-25]}])))

      assert %{settled?: false, next_event_on: ~D[2026-12-25], next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "released more than 180 days ago with no typed home date is settled" do
      payload = movie(%{"release_date" => "2026-01-01"})

      assert %{settled?: true, next_check_at: nil} = Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "released within 180 days with no typed home date keeps the heartbeat" do
      payload = movie(%{"release_date" => "2026-07-01"})

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a canceled movie is settled" do
      payload = movie(%{"status" => "Canceled", "release_date" => "2027-03-01"})

      assert %{settled?: true, next_check_at: nil} = Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a movie with no dates at all keeps the heartbeat" do
      payload = movie(%{"status" => "Rumored", "release_date" => ""})

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end
  end

  describe "plan/5 for a series" do
    defp series(overrides), do: Map.merge(%{"id" => 2, "name" => "Sample Show", "status" => "Returning Series", "seasons" => []}, overrides)

    test "the next episode to air is the next event, due the day after" do
      payload = series(%{"next_episode_to_air" => %{"air_date" => "2026-09-23", "season_number" => 2, "episode_number" => 4}})

      assert %{settled?: false, next_event_on: ~D[2026-09-23], next_check_at: next_check_at} =
               Schedule.plan(:tv_series, payload, [], @today, @fetched_at)

      assert next_check_at == day_after_noon(~D[2026-09-23])
    end

    test "a returning series between seasons keeps the heartbeat" do
      payload = series(%{"next_episode_to_air" => nil, "seasons" => [%{"season_number" => 1, "air_date" => "2025-01-05"}]})

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:tv_series, payload, [], @today, @fetched_at)
    end

    test "a future season air date is an event" do
      payload = series(%{"seasons" => [%{"season_number" => 2, "air_date" => "2026-09-25"}]})

      assert %{next_event_on: ~D[2026-09-25]} = Schedule.plan(:tv_series, payload, [], @today, @fetched_at)
    end

    test "an ended series with every episode aired is settled" do
      payload = series(%{"status" => "Ended", "seasons" => [%{"season_number" => 1, "air_date" => "2020-01-01"}]})
      season = %{"season_number" => 1, "episodes" => [%{"episode_number" => 1, "air_date" => "2020-01-01"}]}

      assert %{settled?: true, next_check_at: nil} = Schedule.plan(:tv_series, payload, [season], @today, @fetched_at)
    end

    test "an ended series whose stored season still has a future air date is not settled" do
      payload = series(%{"status" => "Ended"})
      season = %{"season_number" => 3, "episodes" => [%{"episode_number" => 1, "air_date" => "2026-09-22"}]}

      assert %{settled?: false, next_event_on: ~D[2026-09-22]} =
               Schedule.plan(:tv_series, payload, [season], @today, @fetched_at)
    end
  end

  describe "open_season?/3" do
    @title %{"seasons" => [%{"season_number" => 1}, %{"season_number" => 2}, %{"season_number" => 0}]}

    test "the latest season is open even when every episode has aired" do
      season = %{"season_number" => 2, "episodes" => [%{"air_date" => "2026-01-01"}]}
      assert Schedule.open_season?(season, @title, @today)
    end

    test "an earlier season is closed once every episode has aired" do
      season = %{"season_number" => 1, "episodes" => [%{"air_date" => "2026-01-01"}]}
      refute Schedule.open_season?(season, @title, @today)
    end

    test "an earlier season with an unannounced or future episode is open" do
      unannounced = %{"season_number" => 1, "episodes" => [%{"air_date" => nil}]}
      future = %{"season_number" => 1, "episodes" => [%{"air_date" => "2026-10-01"}]}
      assert Schedule.open_season?(unannounced, @title, @today)
      assert Schedule.open_season?(future, @title, @today)
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/schedule_test.exs`
Expected: FAIL — `module MediaCentaur.TMDB.Schedule is not available`.

- [ ] **Step 3: Implement `TMDB.Schedule`**

```elixir
defmodule MediaCentaur.TMDB.Schedule do
  @moduledoc """
  When the app is next due to ask TMDB about a stored title — a pure
  function of the stored payloads and today's date, with no process and
  no I/O. `MediaCentaur.TMDB.Store` calls it on every write and stores
  the answer as columns, so the checker can query what is due.

  Two rules, agreed with the owner on 2026-09-20 (campaign
  `tmdb-fetch-policy`):

    * **Settled** — a title whose release facts can no longer change. A
      movie is settled at release stage `:home`
      (`MediaCentaur.TMDB.ReleaseWindow`), or when its primary date is
      more than #{@settled_after_days} days past with no typed home
      date, or when canceled. A series is settled when ended or
      canceled with no air date ahead of today in its payload or any
      stored season. A settled title is never due.
    * **Due** — the day after the next known event (noon UTC, past the
      air date in every time zone), or #{@heartbeat_days} days after the
      last fetch, whichever comes first. The heartbeat is the pace at
      which a distant announcement is worth learning and bounds how late
      a date that moved earlier is noticed.

  The **next known event** is the earliest release fact still ahead of
  today: a series' next air date (its `next_episode_to_air`, any stored
  season's episode, any season's own air date); a movie's typed dates
  and primary date.

  A season is **open** — checked with its series — while it is the
  series' latest season or holds an episode with no air date or one
  ahead of today; `open_season?/3`.
  """

  alias MediaCentaur.TMDB.ReleaseWindow

  @heartbeat_days 7
  @settled_after_days 180
  @check_time ~T[12:00:00]

  @type plan :: %{
          next_event_on: Date.t() | nil,
          next_check_at: DateTime.t() | nil,
          settled?: boolean()
        }

  @doc "Days between checks when no event is nearer."
  @spec heartbeat_days() :: pos_integer()
  def heartbeat_days, do: @heartbeat_days

  @doc "The schedule for a title from its payload, its stored season payloads, today, and its last fetch."
  @spec plan(:movie | :tv_series, map(), [map()], Date.t(), DateTime.t()) :: plan()
  def plan(:movie, payload, _season_payloads, %Date{} = today, %DateTime{} = fetched_at) do
    window = ReleaseWindow.from_payload(payload, today)

    future =
      [window.theatrical, window.digital, window.physical, window.primary]
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&Date.after?(&1, today))

    build(future, movie_settled?(payload, window, today, future), fetched_at)
  end

  def plan(:tv_series, payload, season_payloads, %Date{} = today, %DateTime{} = fetched_at) do
    future =
      payload
      |> tv_dates(season_payloads)
      |> Enum.map(&parse_date/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&Date.after?(&1, today))

    settled? = payload["status"] in ["Ended", "Canceled"] and future == []
    build(future, settled?, fetched_at)
  end

  @doc """
  Whether a stored season is still checked with its series: it is the
  series' latest numbered season, or it holds an episode with no air
  date or one ahead of `today`.
  """
  @spec open_season?(map(), map(), Date.t()) :: boolean()
  def open_season?(season_payload, title_payload, %Date{} = today) do
    latest =
      title_payload
      |> Map.get("seasons", [])
      |> List.wrap()
      |> Enum.map(& &1["season_number"])
      |> Enum.reject(&(&1 in [nil, 0]))
      |> Enum.max(fn -> nil end)

    season_payload["season_number"] == latest or
      Enum.any?(season_payload["episodes"] || [], fn episode ->
        case parse_date(episode["air_date"]) do
          nil -> true
          date -> Date.after?(date, today)
        end
      end)
  end

  defp build(future, settled?, fetched_at) do
    next_event_on = Enum.min(future, Date, fn -> nil end)

    %{
      next_event_on: next_event_on,
      next_check_at: if(settled?, do: nil, else: next_check_at(next_event_on, fetched_at)),
      settled?: settled?
    }
  end

  defp next_check_at(nil, fetched_at), do: heartbeat(fetched_at)

  defp next_check_at(next_event_on, fetched_at) do
    day_after = DateTime.new!(Date.add(next_event_on, 1), @check_time, "Etc/UTC")
    Enum.min([day_after, heartbeat(fetched_at)], DateTime)
  end

  defp heartbeat(fetched_at), do: DateTime.add(fetched_at, @heartbeat_days, :day)

  defp movie_settled?(payload, window, today, future) do
    cond do
      payload["status"] == "Canceled" -> true
      window.stage == :home -> true
      future != [] -> false
      is_nil(window.primary) -> false
      ReleaseWindow.home_release(window) != nil -> false
      true -> Date.diff(today, window.primary) > @settled_after_days
    end
  end

  defp tv_dates(payload, season_payloads) do
    episode_dates =
      for season <- season_payloads, episode <- season["episodes"] || [], do: episode["air_date"]

    season_dates = for season <- List.wrap(payload["seasons"]), do: season["air_date"]

    [get_in(payload, ["next_episode_to_air", "air_date"]) | episode_dates ++ season_dates]
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil
end
```

Note: `@settled_after_days` and `@heartbeat_days` are interpolated into the moduledoc, so they must be defined **above** `@moduledoc`. Move the two attribute lines to the top of the module, before `@moduledoc`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/schedule_test.exs`
Expected: 16 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb/schedule.ex test/media_centaur/tmdb/schedule_test.exs
git commit -m "feat(tmdb): Schedule — the pure due-time rule for a stored title

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 2: Migration, schemas, and the store's write path

**Files:**
- Create: `priv/repo/migrations/20260920100000_create_tmdb_store.exs`
- Create: `lib/media_centaur/tmdb/store/title_record.ex`
- Create: `lib/media_centaur/tmdb/store/season_record.ex`
- Create: `lib/media_centaur/tmdb/store.ex`
- Modify: `lib/media_centaur/topics.ex` (add `tmdb_titles/0` after `release_tracking_updates/0`)
- Modify: `lib/media_centaur/tmdb.ex` (exports)
- Test: `test/media_centaur/tmdb/store_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.TMDB.StoreTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TMDB.Store.{SeasonRecord, TitleRecord}
  alias MediaCentaur.TmdbStubs

  @etag ~s(W/"v1")

  describe "record_fetched/3" do
    test "stores a title with its payload, etag, fetch time and schedule" do
      payload = TmdbStubs.movie_detail(%{"id" => 550, "release_date" => "2026-07-01"})

      assert {:ok, %TitleRecord{} = record} = Store.record_fetched({550, :movie}, payload, @etag)
      assert record.tmdb_id == 550
      assert record.media_type == :movie
      assert record.etag == @etag
      assert record.payload["title"] == "Sample Movie"
      assert record.changed_at == record.fetched_at
      assert record.settled_at == nil
      assert record.next_check_at == DateTime.add(record.fetched_at, 7, :day)
      assert Store.get({550, :movie}) == record
    end

    test "an identical payload moves the fetch time and nothing else" do
      record = create_title_record(%{tmdb_id: 551, media_type: :movie})
      backdated = backdate(record, :fetched_at, ~U[2026-01-01 00:00:00Z])

      assert {:ok, again} = Store.record_fetched({551, :movie}, record.payload, @etag)
      assert DateTime.compare(again.fetched_at, backdated.fetched_at) == :gt
      assert again.changed_at == record.changed_at
      assert again.payload == record.payload
    end

    test "a different payload replaces it and moves changed_at" do
      record = create_title_record(%{tmdb_id: 552, media_type: :movie})
      backdated = backdate(record, :changed_at, ~U[2026-01-01 00:00:00Z])

      new_payload = Map.put(record.payload, "overview", "A revised overview.")
      assert {:ok, again} = Store.record_fetched({552, :movie}, new_payload, ~s(W/"v2"))
      assert again.payload["overview"] == "A revised overview."
      assert again.etag == ~s(W/"v2")
      assert DateTime.compare(again.changed_at, backdated.changed_at) == :gt
    end

    test "a nil etag keeps the stored one" do
      create_title_record(%{tmdb_id: 553, media_type: :movie, etag: @etag})
      payload = Store.get({553, :movie}).payload

      assert {:ok, again} = Store.record_fetched({553, :movie}, payload, nil)
      assert again.etag == @etag
    end

    test "the images block is reduced to the logo the app selects" do
      payload =
        TmdbStubs.movie_detail(%{
          "id" => 554,
          "images" => %{
            "logos" => [
              %{"iso_639_1" => "de", "file_path" => "/de.png"},
              %{"iso_639_1" => "en", "file_path" => "/en.png"}
            ],
            "posters" => [%{"file_path" => "/p1.jpg"}, %{"file_path" => "/p2.jpg"}],
            "backdrops" => [%{"file_path" => "/b1.jpg"}]
          }
        })

      assert {:ok, record} = Store.record_fetched({554, :movie}, payload, @etag)
      assert record.payload["images"] == %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/en.png"}]}
      assert MediaCentaur.TMDB.Mapper.pick_logo_path(record.payload) == "/en.png"
    end

    test "a settled title records when it settled and has no due time" do
      payload = TmdbStubs.movie_detail(%{"id" => 555, "release_date" => "2020-01-01"})

      assert {:ok, record} = Store.record_fetched({555, :movie}, payload, @etag)
      assert record.settled_at == record.fetched_at
      assert record.next_check_at == nil
    end

    test "accepts a numeric string id, as the client's callers pass" do
      payload = TmdbStubs.movie_detail(%{"id" => 556})
      assert {:ok, %TitleRecord{tmdb_id: 556}} = Store.record_fetched({"556", :movie}, payload, @etag)
    end
  end

  describe "record_season_fetched/4" do
    test "stores the season and reschedules its series from the episode dates" do
      series = TmdbStubs.tv_detail(%{"id" => 1396, "status" => "Returning Series", "seasons" => [%{"season_number" => 1, "air_date" => "2020-01-01"}]})
      {:ok, before} = Store.record_fetched({1396, :tv_series}, series, @etag)
      assert before.next_event_on == nil

      future = Date.add(Date.utc_today(), 3)
      season = TmdbStubs.season_detail(%{"season_number" => 1, "episodes" => [%{"episode_number" => 1, "air_date" => Date.to_iso8601(future)}]})

      assert {:ok, %SeasonRecord{tmdb_id: 1396, season_number: 1, etag: @etag}} =
               Store.record_season_fetched(1396, 1, season, @etag)

      assert Store.get_season(1396, 1).payload["episodes"] |> length() == 1
      assert Store.get({1396, :tv_series}).next_event_on == future
    end

    test "a season for a series the store does not hold is stored on its own" do
      season = TmdbStubs.season_detail(%{"season_number" => 2})
      assert {:ok, %SeasonRecord{}} = Store.record_season_fetched(1397, 2, season, nil)
      assert [%SeasonRecord{season_number: 2}] = Store.seasons(1397)
    end
  end

  describe "due/1" do
    test "returns unsettled titles whose check time has passed, oldest first" do
      now = DateTime.utc_now()
      overdue = create_title_record(%{tmdb_id: 601})
      later = create_title_record(%{tmdb_id: 602})
      _settled = create_title_record(%{tmdb_id: 603, payload: TmdbStubs.movie_detail(%{"id" => 603, "release_date" => "2020-01-01"})})

      backdate(overdue, :next_check_at, DateTime.add(now, -2, :day))
      backdate(later, :next_check_at, DateTime.add(now, -1, :hour))
      _future = create_title_record(%{tmdb_id: 604})

      assert [%{tmdb_id: 601}, %{tmdb_id: 602}] = Store.due(now)
    end
  end
end
```

- [ ] **Step 2: Add the factory builders** to `test/support/factory.ex`, after the release-tracking section:

```elixir
  # ---------------------------------------------------------------------------
  # TMDB store
  # ---------------------------------------------------------------------------

  @doc """
  A stored TMDB title as a pure struct: a released sample movie with the
  heartbeat due in seven days. Override `:media_type` to `:tv_series`
  for a sample show.
  """
  def build_title_record(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    tmdb_id = Map.get(overrides, :tmdb_id, :rand.uniform(999_999))
    media_type = Map.get(overrides, :media_type, :movie)

    defaults = %{
      id: Ecto.UUID.generate(),
      tmdb_id: tmdb_id,
      media_type: media_type,
      payload: default_title_payload(media_type, tmdb_id),
      etag: ~s(W/"v1"),
      fetched_at: now,
      changed_at: now,
      next_event_on: nil,
      next_check_at: DateTime.add(now, 7, :day),
      settled_at: nil
    }

    struct(MediaCentaur.TMDB.Store.TitleRecord, Map.merge(defaults, overrides))
  end

  @doc """
  Records a title through the store, exactly as a fetch would. The
  payload defaults to a sample movie released within the last month
  (unsettled, heartbeat due) or, for `:tv_series`, a returning sample
  show.
  """
  def create_title_record(attrs \\ %{}) do
    tmdb_id = Map.get(attrs, :tmdb_id, :rand.uniform(999_999))
    media_type = Map.get(attrs, :media_type, :movie)
    payload = Map.get_lazy(attrs, :payload, fn -> default_title_payload(media_type, tmdb_id) end)
    etag = Map.get(attrs, :etag, ~s(W/"v1"))

    {:ok, record} = MediaCentaur.TMDB.Store.record_fetched({tmdb_id, media_type}, payload, etag)
    record
  end

  @doc "Records a season through the store, exactly as a fetch would."
  def create_season_record(attrs) do
    tmdb_id = Map.fetch!(attrs, :tmdb_id)
    season_number = Map.get(attrs, :season_number, 1)

    payload =
      Map.get_lazy(attrs, :payload, fn ->
        MediaCentaur.TmdbStubs.season_detail(%{"season_number" => season_number})
      end)

    {:ok, record} =
      MediaCentaur.TMDB.Store.record_season_fetched(tmdb_id, season_number, payload, Map.get(attrs, :etag, ~s(W/"v1")))

    record
  end

  defp default_title_payload(:movie, tmdb_id) do
    recent = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
    MediaCentaur.TmdbStubs.movie_detail(%{"id" => tmdb_id, "release_date" => recent})
  end

  defp default_title_payload(:tv_series, tmdb_id) do
    MediaCentaur.TmdbStubs.tv_detail(%{"id" => tmdb_id, "status" => "Returning Series", "seasons" => []})
  end
```

Check that `backdate/3` in the factory accepts any schema with the named field (it does: it forces the field by `Repo.update!` on a changeset). If it is typed to a list of schemas, extend it.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/store_test.exs`
Expected: FAIL — `module MediaCentaur.TMDB.Store is not available`.

- [ ] **Step 4: Write the migration**

Read one existing create-table migration first (`priv/repo/migrations/20260404104919_create_release_tracking.exs`) and copy its primary-key and timestamp idiom exactly. With that idiom the body is:

```elixir
defmodule MediaCentaur.Repo.Migrations.CreateTmdbStore do
  @moduledoc """
  The TMDB store (campaign `tmdb-fetch-policy`, Phase 1): one row per
  TMDB title the app knows — the detail payload as TMDB returned it, the
  ETag to revalidate it with, when it was fetched and last changed, and
  the next event and check time `MediaCentaur.TMDB.Schedule` derives —
  plus one row per stored season.

  Additive; no backfill. Rows appear as titles are fetched
  (`TMDB.Client` writes through), and `next_check_at` is read by nothing
  until Phase 2 schedules checks.
  """
  use Ecto.Migration

  def change do
    create table(:tmdb_titles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :media_type, :string, null: false
      add :tmdb_id, :integer, null: false
      add :payload, :map, null: false
      add :etag, :string
      add :fetched_at, :utc_datetime, null: false
      add :changed_at, :utc_datetime, null: false
      add :next_event_on, :date
      add :next_check_at, :utc_datetime
      add :settled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tmdb_titles, [:media_type, :tmdb_id])
    create index(:tmdb_titles, [:next_check_at])

    create table(:tmdb_seasons, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tmdb_id, :integer, null: false
      add :season_number, :integer, null: false
      add :payload, :map, null: false
      add :etag, :string
      add :fetched_at, :utc_datetime, null: false
      add :changed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tmdb_seasons, [:tmdb_id, :season_number])
  end
end
```

- [ ] **Step 5: Write the schemas**

`lib/media_centaur/tmdb/store/title_record.ex`:

```elixir
defmodule MediaCentaur.TMDB.Store.TitleRecord do
  @moduledoc """
  One TMDB title as the app knows it: TMDB's last detail answer
  (`payload`, as received except the `images` block, which
  `MediaCentaur.TMDB.Store.trim_payload/1` reduces to the selected
  logo), the `etag` to revalidate it with, when TMDB last answered
  (`fetched_at`, moved by a 200 or a 304), when the payload last
  differed (`changed_at`), and the schedule `MediaCentaur.TMDB.Schedule`
  derives: `next_event_on`, `next_check_at` (nil when settled),
  `settled_at` (set the first time the settled rule holds, cleared if a
  later check unsettles it).

  Written only by `MediaCentaur.TMDB.Store`. Keyed by `(media_type,
  tmdb_id)` — TMDB's movie and TV id spaces overlap.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "tmdb_titles" do
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :tmdb_id, :integer
    field :payload, :map
    field :etag, :string
    field :fetched_at, :utc_datetime
    field :changed_at, :utc_datetime
    field :next_event_on, :date
    field :next_check_at, :utc_datetime
    field :settled_at, :utc_datetime

    timestamps()
  end

  @fields [
    :media_type,
    :tmdb_id,
    :payload,
    :etag,
    :fetched_at,
    :changed_at,
    :next_event_on,
    :next_check_at,
    :settled_at
  ]

  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required([:media_type, :tmdb_id, :payload, :fetched_at, :changed_at])
    |> unique_constraint([:media_type, :tmdb_id])
  end
end
```

`lib/media_centaur/tmdb/store/season_record.ex`:

```elixir
defmodule MediaCentaur.TMDB.Store.SeasonRecord do
  @moduledoc """
  One season of a stored series: TMDB's `season/{n}` answer with its
  appended credits, the `etag` to revalidate it with, and when it was
  fetched and last changed. A season has no schedule of its own — it is
  checked with its series while `MediaCentaur.TMDB.Schedule.open_season?/3`
  says it is open. Written only by `MediaCentaur.TMDB.Store`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "tmdb_seasons" do
    field :tmdb_id, :integer
    field :season_number, :integer
    field :payload, :map
    field :etag, :string
    field :fetched_at, :utc_datetime
    field :changed_at, :utc_datetime

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:tmdb_id, :season_number, :payload, :etag, :fetched_at, :changed_at])
    |> validate_required([:tmdb_id, :season_number, :payload, :fetched_at, :changed_at])
    |> unique_constraint([:tmdb_id, :season_number])
  end
end
```

- [ ] **Step 6: Write the store's read and write functions** (`ensure`/`check` come in Task 4)

`lib/media_centaur/tmdb/store.ex`:

```elixir
defmodule MediaCentaur.TMDB.Store do
  @moduledoc """
  The app's knowledge of a TMDB title, one record per identity: TMDB's
  last answer, when it was learned, and when the app is next due to ask
  (`MediaCentaur.TMDB.Store.TitleRecord`, with one
  `MediaCentaur.TMDB.Store.SeasonRecord` per stored season). Everything
  the app shows or schedules about a title is a projection of this
  record; nothing else fetches (campaign `tmdb-fetch-policy`; ADR-071).

  This module is the only writer. Three ways a record changes:

    * **First contact** — `ensure/2` and `ensure_season/3` fetch a title
      the app has never held. Never a request when the title is stored.
    * **A check** — `check/2` revalidates a stored title with its own
      ETag through `MediaCentaur.TMDB.Client.detail/2`; a 304 moves the
      fetch time and re-derives the schedule (today moved), a 200
      replaces the payload. Open seasons are checked with the title. A
      change is published as `{:tmdb_title_changed, {tmdb_id, media_type}}`
      on `MediaCentaur.Topics.tmdb_titles/0`.
    * **Write-through** — `record_fetched/3` and `record_season_fetched/4`
      are also called by `TMDB.Client` for every detail payload a caller
      fetches, so the store fills while callers still fetch for
      themselves. Transitional: removed when the last detail caller
      reads through this module.

  The schedule columns are derived on every write by
  `MediaCentaur.TMDB.Schedule`, so `due/1` is a plain query. Ids arrive
  as integers or numeric strings — the client's callers pass both.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.{Mapper, Schedule}
  alias MediaCentaur.TMDB.Store.{SeasonRecord, TitleRecord}

  @type media_type :: :movie | :tv_series
  @type ref :: {pos_integer() | String.t(), media_type()}

  # --- Reads ---

  @doc "The stored title, or nil."
  @spec get(ref()) :: TitleRecord.t() | nil
  def get({tmdb_id, media_type}) do
    Repo.get_by(TitleRecord, tmdb_id: normalize_id(tmdb_id), media_type: media_type)
  end

  @doc "The stored season, or nil."
  @spec get_season(pos_integer() | String.t(), pos_integer()) :: SeasonRecord.t() | nil
  def get_season(tmdb_id, season_number) do
    Repo.get_by(SeasonRecord, tmdb_id: normalize_id(tmdb_id), season_number: season_number)
  end

  @doc "Every stored season of a series, by season number."
  @spec seasons(pos_integer() | String.t()) :: [SeasonRecord.t()]
  def seasons(tmdb_id) do
    tmdb_id = normalize_id(tmdb_id)
    Repo.all(from s in SeasonRecord, where: s.tmdb_id == ^tmdb_id, order_by: s.season_number)
  end

  @doc "Unsettled titles whose check time has passed, oldest due first."
  @spec due(DateTime.t()) :: [TitleRecord.t()]
  def due(%DateTime{} = now) do
    Repo.all(
      from t in TitleRecord,
        where: not is_nil(t.next_check_at) and t.next_check_at <= ^now,
        order_by: t.next_check_at
    )
  end

  # --- Writes ---

  @doc """
  Records a title's detail payload as fetched now. An identical payload
  moves only `fetched_at`; a different one replaces it and moves
  `changed_at`. A nil `etag` keeps the stored one (a body served by the
  response cache carries none). The schedule is re-derived either way.
  """
  @spec record_fetched(ref(), map(), String.t() | nil) :: {:ok, TitleRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_fetched({tmdb_id, media_type}, payload, etag) when is_map(payload) do
    tmdb_id = normalize_id(tmdb_id)
    now = now()
    payload = trim_payload(payload)
    existing = get({tmdb_id, media_type})

    attrs =
      existing
      |> fetched_attrs(payload, etag, now)
      |> Map.merge(schedule_attrs(existing, media_type, payload, seasons(tmdb_id), now))

    (existing || %TitleRecord{tmdb_id: tmdb_id, media_type: media_type})
    |> TitleRecord.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Records a season's payload as fetched now, then re-derives its
  series' schedule, since the season's episode dates are part of it.
  """
  @spec record_season_fetched(pos_integer() | String.t(), pos_integer(), map(), String.t() | nil) ::
          {:ok, SeasonRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_season_fetched(tmdb_id, season_number, payload, etag) when is_map(payload) do
    tmdb_id = normalize_id(tmdb_id)
    now = now()
    existing = get_season(tmdb_id, season_number)

    result =
      (existing || %SeasonRecord{tmdb_id: tmdb_id, season_number: season_number})
      |> SeasonRecord.changeset(fetched_attrs(existing, payload, etag, now))
      |> Repo.insert_or_update()

    with {:ok, _season} <- result do
      reschedule_series(tmdb_id, now)
      result
    end
  end

  @doc """
  The payload as the store keeps it: as received, except the `images`
  block, which is reduced to the one logo `Mapper.pick_logo_path/1`
  selects. Posters and backdrops are already named at the top level;
  the rest of the block is the bulk of a detail response and nothing
  reads it.
  """
  @spec trim_payload(map()) :: map()
  def trim_payload(%{"images" => _images} = payload) do
    logo_path = Mapper.pick_logo_path(payload)
    logos = get_in(payload, ["images", "logos"]) || []
    Map.put(payload, "images", %{"logos" => Enum.filter(logos, &(&1["file_path"] == logo_path))})
  end

  def trim_payload(payload), do: payload

  # --- Internals ---

  defp fetched_attrs(nil, payload, etag, now) do
    %{payload: payload, etag: etag, fetched_at: now, changed_at: now}
  end

  defp fetched_attrs(%{payload: stored, etag: stored_etag} = _existing, payload, etag, now) do
    base = %{payload: payload, etag: etag || stored_etag, fetched_at: now}
    if payload == stored, do: base, else: Map.put(base, :changed_at, now)
  end

  defp schedule_attrs(existing, media_type, payload, season_records, now) do
    season_payloads = Enum.map(season_records, & &1.payload)
    plan = Schedule.plan(media_type, payload, season_payloads, DateTime.to_date(now), now)

    %{
      next_event_on: plan.next_event_on,
      next_check_at: plan.next_check_at,
      settled_at: settled_at(existing, plan, now)
    }
  end

  defp settled_at(_existing, %{settled?: false}, _now), do: nil
  defp settled_at(%TitleRecord{settled_at: %DateTime{} = at}, %{settled?: true}, _now), do: at
  defp settled_at(_existing, %{settled?: true}, now), do: now

  defp reschedule_series(tmdb_id, now) do
    case get({tmdb_id, :tv_series}) do
      nil ->
        :ok

      %TitleRecord{} = record ->
        attrs = schedule_attrs(record, :tv_series, record.payload, seasons(tmdb_id), record.fetched_at)
        {:ok, _record} = record |> TitleRecord.changeset(attrs) |> Repo.update()
        :ok
    end
    |> tap(fn _ -> Log.debug(:tmdb, "rescheduled series tmdb:#{tmdb_id} at #{now}") end)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
end
```

Remove the `tap`/`Log.debug` line in `reschedule_series/2` if it reads as noise; it is there so the `Log` require has a use before Task 4 adds the check lines. If removed, also remove the `require` until Task 4.

Note on `schedule_attrs` in `reschedule_series/2`: the fetch time passed is the record's own `fetched_at`, not `now` — a season write does not mean the series was asked.

- [ ] **Step 7: Add the topic and the exports**

`lib/media_centaur/topics.ex`, after `release_tracking_updates/0`:

```elixir
  @doc "`{:tmdb_title_changed, {tmdb_id, media_type}}` when a stored TMDB title's payload changed (`MediaCentaur.TMDB.Store`)."
  def tmdb_titles, do: "tmdb:titles"
```

`lib/media_centaur/tmdb.ex` exports — add `Schedule`, `Store`, `Store.SeasonRecord`, `Store.TitleRecord` in alphabetical position.

- [ ] **Step 8: Migrate the test database and run the tests**

Run: `~/scripts/agents/agent-mix ecto.migrate` then `MIX_ENV=test ~/scripts/agents/agent-mix ecto.migrate` (if the test alias does not migrate on its own — check `mix.exs` `test` alias first; it usually runs `ecto.create --quiet`, `ecto.migrate --quiet`).
Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/store_test.exs`
Expected: 11 tests, 0 failures. If Boundary complains about the new exports, run `~/scripts/agents/agent-mix compile --force` once.

- [ ] **Step 9: Commit**

```bash
git add priv/repo/migrations/20260920100000_create_tmdb_store.exs lib/media_centaur/tmdb/store.ex lib/media_centaur/tmdb/store/ lib/media_centaur/topics.ex lib/media_centaur/tmdb.ex test/support/factory.ex test/media_centaur/tmdb/store_test.exs
git commit -m "feat(tmdb): the TMDB store — one record per title, seasons alongside, schedule derived on write

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 3: `Client.detail/2` and the cache pass-through

**Files:**
- Modify: `lib/media_centaur/http_client/cache.ex`
- Modify: `lib/media_centaur/tmdb/client.ex`
- Test: `test/media_centaur/http_client/cache_test.exs`
- Test: `test/media_centaur/tmdb/client_test.exs`

- [ ] **Step 1: Write the failing cache test** — add to `cache_test.exs` a new `describe` after `"reload"`:

```elixir
  describe "caller-conditional requests" do
    test "pass through untouched: the caller's validator goes out, nothing is served or stored", %{
      stub: stub,
      client: client
    } do
      test_pid = self()

      Req.Test.stub(stub, fn conn ->
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})

        case Plug.Conn.get_req_header(conn, "if-none-match") do
          [~s(W/"mine")] ->
            Plug.Conn.send_resp(conn, 304, "")

          [] ->
            conn
            |> put_headers([{"cache-control", "max-age=60"}, {"etag", ~s(W/"v1")}])
            |> Req.Test.json(%{"version" => 1})
        end
      end)

      # A fresh entry exists.
      assert {:ok, %{status: 200}} = Req.get(client, url: "/movie/1")
      assert_receive {:http_stop, %{cache: :miss}}, @wait_ms
      assert %{entries: 1} = Cache.stats(client)

      # The caller's own validator wins over the fresh entry.
      assert {:ok, %{status: 304}} =
               Req.get(client, url: "/movie/1", headers: [{"if-none-match", ~s(W/"mine")}])

      assert_receive {:stub_hit, "GET", "/movie/1", headers}, @wait_ms
      assert {"if-none-match", ~s(W/"mine")} in headers
      assert_receive {:http_stop, %{cache: :conditional, status: 304}}, @wait_ms

      # Nothing stored, nothing renewed: the entry is still the one miss.
      assert %{entries: 1} = Cache.stats(client)
    end
  end
```

Check the module aliases `Cache` at the top of `cache_test.exs`; add `alias MediaCentaur.HttpClient.Cache` if absent.

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/cache_test.exs`
Expected: FAIL — the second request is answered from the fresh entry (`status: 200`, no `:stub_hit`).

- [ ] **Step 3: Implement the pass-through** in `lib/media_centaur/http_client/cache.ex`

Replace the `lookup/1` GET clause:

```elixir
  defp lookup(%Req.Request{method: :get} = request) do
    config = Req.Request.get_private(request, :http_cache_config)

    cond do
      conditional?(request) ->
        Req.Request.put_private(request, :http_cache, :conditional)

      Coordinator.running?(config.name) ->
        key = Key.build(request.url, config.exclude_params)
        request = Req.Request.put_private(request, :http_cache_key, key)
        entry = Coordinator.lookup(config.name, key)
        now = System.monotonic_time(:millisecond)

        cond do
          request.options[:reload] == true -> lead_or_follow(request, config, :reload, nil)
          entry == nil -> lead_or_follow(request, config, :miss, nil)
          Entry.fresh?(entry, now) -> hit(request, entry)
          entry.etag == nil -> lead_or_follow(request, config, :miss, nil)
          true -> lead_or_follow(request, config, :revalidate, entry)
        end

      true ->
        request
    end
  end

  # A request the caller made conditional carries its own validator:
  # the caller holds the answer and is asking whether it changed. The
  # cache stands aside — no lookup, no store — so the caller sees the
  # 304 or the 200 as TMDB sent it.
  defp conditional?(request), do: Req.Request.get_header(request, "if-none-match") != []
```

Update `@type outcome` to `:uncached | :hit | :miss | :revalidate | :reload | :conditional`, and add to the moduledoc list:

```
    * **Caller-conditional** — a request carrying its own
      `If-None-Match` passes through: no lookup, no store; the caller
      holds the entry and reads the 304 itself. Reported as
      `:conditional`. `MediaCentaur.TMDB.Store` checks stored titles
      this way.
```

- [ ] **Step 4: Run the cache tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/cache_test.exs`
Expected: all pass, including the new one.

- [ ] **Step 5: Write the failing client tests** — add to `client_test.exs` a `describe "detail/2"`:

```elixir
  describe "detail/2" do
    setup do
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        send(test_pid, {:tmdb_hit, conn.request_path, Plug.Conn.get_req_header(conn, "if-none-match")})

        case Plug.Conn.get_req_header(conn, "if-none-match") do
          [~s(W/"held")] ->
            Plug.Conn.send_resp(conn, 304, "")

          _other ->
            conn
            |> Plug.Conn.put_resp_header("cache-control", "public, max-age=60")
            |> Plug.Conn.put_resp_header("etag", ~s(W/"fresh"))
            |> Req.Test.json(%{"id" => 7, "title" => "Sample Movie"})
        end
      end)

      :ok
    end

    test "a movie detail returns the body and TMDB's etag" do
      assert {:ok, %{body: %{"id" => 7}, etag: ~s(W/"fresh")}} = Client.detail({7, :movie})
      assert_receive {:tmdb_hit, "/3/movie/7", []}
    end

    test "a conditional request that TMDB answers 304 is unchanged, and never served from the cache" do
      assert {:ok, _} = Client.detail({7, :movie})
      assert {:ok, :unchanged} = Client.detail({7, :movie}, if_none_match: ~s(W/"held"))
      assert_receive {:tmdb_hit, "/3/movie/7", []}
      assert_receive {:tmdb_hit, "/3/movie/7", [~s(W/"held")]}
    end

    test "a conditional request that TMDB answers 200 returns the new body and etag" do
      assert {:ok, %{body: %{"title" => "Sample Movie"}, etag: ~s(W/"fresh")}} =
               Client.detail({7, :movie}, if_none_match: ~s(W/"stale"))

      assert_receive {:tmdb_hit, "/3/movie/7", [~s(W/"stale")]}
    end

    test "series and season refs address their endpoints" do
      assert {:ok, %{body: _}} = Client.detail({9, :tv_series})
      assert {:ok, %{body: _}} = Client.detail({:season, 9, 2})
      assert_receive {:tmdb_hit, "/3/tv/9", []}
      assert_receive {:tmdb_hit, "/3/tv/9/season/2", []}
    end

    test "a 304 counts as TMDB answering" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
      assert {:ok, :unchanged} = Client.detail({7, :movie}, if_none_match: ~s(W/"held"))
      assert IntegrationAvailability.up?(:tmdb)
    end
  end
```

- [ ] **Step 6: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/client_test.exs`
Expected: FAIL — `Client.detail/2 is undefined`.

- [ ] **Step 7: Implement `detail/2`** in `lib/media_centaur/tmdb/client.ex`

Add the type and function after `configuration/1`, and have the three detail getters share the request builders:

```elixir
  @typedoc "What `detail/2` fetches: a title by the app's `{tmdb_id, media_type}` ref, or one season."
  @type detail_ref :: {pos_integer() | String.t(), :movie | :tv_series} | {:season, pos_integer() | String.t(), pos_integer()}

  @doc """
  One detail payload, with the ETag to revalidate it by — the request
  path `MediaCentaur.TMDB.Store` reads through. With `if_none_match:`
  the request carries the caller's validator, the response cache stands
  aside (`MediaCentaur.HttpClient.Cache`, `:conditional`), and a 304
  comes back as `{:ok, :unchanged}`. Without it, the request takes the
  cache's ordinary path. The `get_*` functions remain for callers that
  still fetch for themselves; they go as the store takes over.
  """
  @spec detail(detail_ref(), keyword()) ::
          {:ok, %{body: map(), etag: String.t() | nil}} | {:ok, :unchanged} | {:error, any()}
  def detail(ref, opts \\ []) do
    {etag, opts} = Keyword.pop(opts, :if_none_match)
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)
    subject = detail_subject(ref)

    case Req.get(client, detail_request(ref) ++ conditional(etag) ++ opts) do
      {:ok, %{status: 200, body: body} = response} ->
        outcome = Cache.outcome(response)
        Availability.observe_request({:ok, outcome})
        Log.info(:tmdb, log_line(subject, outcome))
        {:ok, %{body: body, etag: List.first(Req.Response.get_header(response, "etag"))}}

      {:ok, %{status: 304} = response} ->
        Availability.observe_request({:ok, Cache.outcome(response)})
        Log.info(:tmdb, "checked #{subject} — unchanged")
        {:ok, :unchanged}

      {:ok, %{status: status, body: body}} ->
        Availability.observe_request({:error, {:http_error, status, body}})
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Availability.observe_request({:error, reason})
        {:error, reason}
    end
  end
```

Private builders (replace the inline request lists in `get_movie/2`, `get_tv/2`, `get_season/3` with calls to these — the `get_collection/2` list stays as it is):

```elixir
  defp detail_request({tmdb_id, :movie}) do
    [
      url: "/movie/#{tmdb_id}",
      params: [append_to_response: "credits,release_dates,images", include_image_language: "en,null"]
    ]
  end

  defp detail_request({tmdb_id, :tv_series}) do
    [
      url: "/tv/#{tmdb_id}",
      params: [append_to_response: "aggregate_credits,external_ids,images", include_image_language: "en,null"]
    ]
  end

  # `credits` rides along for per-episode cast membership: season
  # regulars come from the appended credits, guest stars ride on each
  # episode object (`Mapper.episode_attrs/2`).
  defp detail_request({:season, tmdb_id, season_number}) do
    [url: "/tv/#{tmdb_id}/season/#{season_number}", params: [append_to_response: "credits"]]
  end

  defp detail_subject({tmdb_id, :movie}), do: "movie tmdb:#{tmdb_id}"
  defp detail_subject({tmdb_id, :tv_series}), do: "TV tmdb:#{tmdb_id}"
  defp detail_subject({:season, tmdb_id, season_number}), do: "season tmdb:#{tmdb_id} S#{season_number}"

  defp conditional(nil), do: []
  defp conditional(etag), do: [headers: [{"if-none-match", etag}]]
```

So `get_movie/2` becomes `get(opts, detail_request({tmdb_id, :movie}), detail_subject({tmdb_id, :movie}))`, and likewise for `get_tv/2` and `get_season/3`. Add a `source/1` clause: `defp source(:conditional), do: "from TMDB"` — a 200 to the caller's own validator is a full fetch. Update the moduledoc's *Options* section to mention `:if_none_match` on `detail/2`, and the *console line* paragraph to add `checked … — unchanged` for a 304.

- [ ] **Step 8: Run the client tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/client_test.exs test/media_centaur/http_client/`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur/http_client/cache.ex lib/media_centaur/tmdb/client.ex test/media_centaur/http_client/cache_test.exs test/media_centaur/tmdb/client_test.exs
git commit -m "feat(http_client,tmdb): caller-conditional requests pass the cache; Client.detail/2 carries the store's validator

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 4: `Store.ensure/2`, `ensure_season/3`, `check/2`

**Files:**
- Modify: `lib/media_centaur/tmdb/store.ex`
- Test: `test/media_centaur/tmdb/store_test.exs`

- [ ] **Step 1: Write the failing tests** — add to `store_test.exs`:

```elixir
  describe "ensure/2 and ensure_season/3" do
    setup do
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        send(test_pid, {:tmdb_hit, conn.request_path})

        body =
          cond do
            String.contains?(conn.request_path, "/season/") -> TmdbStubs.season_detail(%{"season_number" => 1})
            String.contains?(conn.request_path, "/tv/") -> TmdbStubs.tv_detail(%{"id" => 1396})
            true -> TmdbStubs.movie_detail(%{"id" => 550})
          end

        conn
        |> Plug.Conn.put_resp_header("etag", ~s(W/"first"))
        |> Req.Test.json(body)
      end)

      :ok
    end

    test "a stored title is returned without a request" do
      record = create_title_record(%{tmdb_id: 550, media_type: :movie})
      assert {:ok, ^record} = Store.ensure({550, :movie})
      refute_receive {:tmdb_hit, _path}
    end

    test "an unknown title is fetched once and stored with TMDB's etag" do
      assert {:ok, %TitleRecord{tmdb_id: 550, etag: ~s(W/"first")}} = Store.ensure({550, :movie})
      assert_receive {:tmdb_hit, "/3/movie/550"}
      assert {:ok, %TitleRecord{}} = Store.ensure({550, :movie})
      refute_receive {:tmdb_hit, _path}
    end

    test "an unknown season is fetched once" do
      assert {:ok, %SeasonRecord{tmdb_id: 1396, season_number: 1}} = Store.ensure_season(1396, 1)
      assert_receive {:tmdb_hit, "/3/tv/1396/season/1"}
      assert {:ok, %SeasonRecord{}} = Store.ensure_season(1396, 1)
      refute_receive {:tmdb_hit, _path}
    end

    test "a TMDB failure is returned, and nothing is stored" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert {:error, _reason} = Store.ensure({999, :movie})
      assert Store.get({999, :movie}) == nil
    end
  end

  describe "check/2" do
    setup do
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.tmdb_titles())
      :ok
    end

    defp stub_check(test_pid, held_etag, fresh_body) do
      Req.Test.stub(:tmdb, fn conn ->
        validator = Plug.Conn.get_req_header(conn, "if-none-match")
        send(test_pid, {:tmdb_hit, conn.request_path, validator})

        if validator == [held_etag] do
          Plug.Conn.send_resp(conn, 304, "")
        else
          conn
          |> Plug.Conn.put_resp_header("etag", ~s(W/"next"))
          |> Req.Test.json(fresh_body.(conn.request_path))
        end
      end)
    end

    test "an unchanged title moves its fetch time, keeps its rows, publishes nothing" do
      record = create_title_record(%{tmdb_id: 560, media_type: :movie, etag: ~s(W/"held")})
      backdate(record, :fetched_at, ~U[2026-01-01 00:00:00Z])
      stub_check(self(), ~s(W/"held"), fn _path -> %{} end)

      assert {:ok, :unchanged, %TitleRecord{} = after_check} = Store.check({560, :movie})
      assert_receive {:tmdb_hit, "/3/movie/560", [~s(W/"held")]}
      assert DateTime.compare(after_check.fetched_at, ~U[2026-01-01 00:00:00Z]) == :gt
      assert after_check.changed_at == record.changed_at
      assert after_check.payload == record.payload
      refute_receive {:tmdb_title_changed, _ref}
    end

    test "a changed title replaces the payload and etag and publishes the change" do
      record = create_title_record(%{tmdb_id: 561, media_type: :movie, etag: ~s(W/"old")})
      revised = Map.put(record.payload, "overview", "Revised.")
      stub_check(self(), ~s(W/"held"), fn _path -> revised end)

      assert {:ok, :changed, %TitleRecord{etag: ~s(W/"next")} = after_check} = Store.check({561, :movie})
      assert after_check.payload["overview"] == "Revised."
      assert_receive {:tmdb_title_changed, {561, :movie}}
    end

    test "a series check revalidates its open seasons and leaves closed ones alone" do
      series =
        TmdbStubs.tv_detail(%{
          "id" => 562,
          "status" => "Returning Series",
          "seasons" => [%{"season_number" => 1, "air_date" => "2020-01-01"}, %{"season_number" => 2, "air_date" => "2026-01-01"}]
        })

      create_title_record(%{tmdb_id: 562, media_type: :tv_series, payload: series, etag: ~s(W/"held")})
      closed = TmdbStubs.season_detail(%{"season_number" => 1, "episodes" => [%{"episode_number" => 1, "air_date" => "2020-01-01"}]})
      latest = TmdbStubs.season_detail(%{"season_number" => 2, "episodes" => [%{"episode_number" => 1, "air_date" => "2026-01-01"}]})
      create_season_record(%{tmdb_id: 562, season_number: 1, payload: closed, etag: ~s(W/"held")})
      create_season_record(%{tmdb_id: 562, season_number: 2, payload: latest, etag: ~s(W/"held")})
      stub_check(self(), ~s(W/"held"), fn _path -> %{} end)

      assert {:ok, :unchanged, _record} = Store.check({562, :tv_series})
      assert_receive {:tmdb_hit, "/3/tv/562", [~s(W/"held")]}
      assert_receive {:tmdb_hit, "/3/tv/562/season/2", [~s(W/"held")]}
      refute_receive {:tmdb_hit, "/3/tv/562/season/1", _validator}
    end

    test "a season that changed publishes the series as changed even when the series did not" do
      series = TmdbStubs.tv_detail(%{"id" => 563, "status" => "Returning Series", "seasons" => [%{"season_number" => 1, "air_date" => "2026-01-01"}]})
      create_title_record(%{tmdb_id: 563, media_type: :tv_series, payload: series, etag: ~s(W/"held")})
      create_season_record(%{tmdb_id: 563, season_number: 1, etag: ~s(W/"old")})
      new_season = TmdbStubs.season_detail(%{"season_number" => 1, "episodes" => [%{"episode_number" => 3, "air_date" => "2026-12-01"}]})
      stub_check(self(), ~s(W/"held"), fn _path -> new_season end)

      assert {:ok, :changed, %TitleRecord{next_event_on: ~D[2026-12-01]}} = Store.check({563, :tv_series})
      assert_receive {:tmdb_title_changed, {563, :tv_series}}
    end

    test "checking a title the store does not hold is first contact" do
      stub_check(self(), ~s(W/"none"), fn _path -> TmdbStubs.movie_detail(%{"id" => 564}) end)
      assert {:ok, :changed, %TitleRecord{tmdb_id: 564}} = Store.check({564, :movie})
      assert_receive {:tmdb_title_changed, {564, :movie}}
    end

    test "a TMDB failure leaves the record as it was" do
      record = create_title_record(%{tmdb_id: 565, media_type: :movie})
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Store.check({565, :movie})
      assert Store.get({565, :movie}) == record
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/store_test.exs`
Expected: FAIL — `Store.ensure/1`, `Store.ensure_season/2`, `Store.check/1` undefined.

- [ ] **Step 3: Implement** — add to `lib/media_centaur/tmdb/store.ex` under a `# --- First contact and checks ---` heading, and add `alias MediaCentaur.TMDB.Client` and `alias MediaCentaur.Topics`:

```elixir
  @doc "The stored title, fetched on first contact when the app has never held it."
  @spec ensure(ref(), keyword()) :: {:ok, TitleRecord.t()} | {:error, any()}
  def ensure(ref, opts \\ []) do
    case get(ref) do
      nil -> first_contact(ref, opts)
      %TitleRecord{} = record -> {:ok, record}
    end
  end

  @doc "The stored season, fetched on first contact when the app has never held it."
  @spec ensure_season(pos_integer() | String.t(), pos_integer(), keyword()) ::
          {:ok, SeasonRecord.t()} | {:error, any()}
  def ensure_season(tmdb_id, season_number, opts \\ []) do
    case get_season(tmdb_id, season_number) do
      nil -> first_contact_season(tmdb_id, season_number, opts)
      %SeasonRecord{} = record -> {:ok, record}
    end
  end

  @doc """
  Revalidates a stored title with its ETag, and its open seasons with
  theirs. `{:ok, :unchanged, record}` when TMDB answered 304 for all of
  them; `{:ok, :changed, record}` when any payload was replaced, after
  publishing `{:tmdb_title_changed, ref}`. A title the store does not
  hold is first contact, reported as changed. Any TMDB failure is
  returned and leaves the records as they were.
  """
  @spec check(ref(), keyword()) :: {:ok, :unchanged | :changed, TitleRecord.t()} | {:error, any()}
  def check(ref, opts \\ []) do
    case get(ref) do
      nil ->
        with {:ok, record} <- first_contact(ref, opts) do
          publish_changed(record)
          {:ok, :changed, record}
        end

      %TitleRecord{} = record ->
        with {:ok, title_changed?} <- revalidate_title(record, opts),
             {:ok, seasons_changed?} <- revalidate_open_seasons(record, opts) do
          record = get(ref)

          if title_changed? or seasons_changed? do
            publish_changed(record)
            {:ok, :changed, record}
          else
            {:ok, :unchanged, record}
          end
        end
    end
  end

  defp first_contact({tmdb_id, media_type} = ref, opts) do
    with {:ok, %{body: body, etag: etag}} <- Client.detail(ref, opts),
         {:ok, record} <- record_fetched(ref, body, etag) do
      Log.info(:tmdb, "stored #{subject(media_type, tmdb_id)} — first contact#{schedule_words(record)}")
      {:ok, record}
    end
  end

  defp first_contact_season(tmdb_id, season_number, opts) do
    with {:ok, %{body: body, etag: etag}} <- Client.detail({:season, tmdb_id, season_number}, opts) do
      record_season_fetched(tmdb_id, season_number, body, etag)
    end
  end

  # {:ok, changed?} | {:error, reason}
  defp revalidate_title(%TitleRecord{} = record, opts) do
    ref = {record.tmdb_id, record.media_type}

    case Client.detail(ref, Keyword.put(opts, :if_none_match, record.etag)) do
      {:ok, :unchanged} ->
        {:ok, touched} = touch_title(record)
        Log.info(:tmdb, "checked #{subject(record.media_type, record.tmdb_id)} — unchanged#{schedule_words(touched)}")
        {:ok, false}

      {:ok, %{body: body, etag: etag}} ->
        {:ok, replaced} = record_fetched(ref, body, etag)
        changed? = replaced.changed_at == replaced.fetched_at
        Log.info(:tmdb, "checked #{subject(record.media_type, record.tmdb_id)} — #{if changed?, do: "changed", else: "unchanged"}#{schedule_words(replaced)}")
        {:ok, changed?}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp revalidate_open_seasons(%TitleRecord{media_type: :movie}, _opts), do: {:ok, false}

  defp revalidate_open_seasons(%TitleRecord{media_type: :tv_series} = record, opts) do
    title = get({record.tmdb_id, :tv_series})
    today = Date.utc_today()

    record.tmdb_id
    |> seasons()
    |> Enum.filter(&Schedule.open_season?(&1.payload, title.payload, today))
    |> Enum.reduce_while({:ok, false}, fn season, {:ok, any_changed?} ->
      case revalidate_season(season, opts) do
        {:ok, changed?} -> {:cont, {:ok, any_changed? or changed?}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revalidate_season(%SeasonRecord{} = season, opts) do
    ref = {:season, season.tmdb_id, season.season_number}

    case Client.detail(ref, Keyword.put(opts, :if_none_match, season.etag)) do
      {:ok, :unchanged} ->
        {:ok, _touched} = season |> SeasonRecord.changeset(%{fetched_at: now()}) |> Repo.update()
        {:ok, false}

      {:ok, %{body: body, etag: etag}} ->
        {:ok, replaced} = record_season_fetched(season.tmdb_id, season.season_number, body, etag)
        {:ok, replaced.changed_at == replaced.fetched_at}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A 304: TMDB answered, nothing changed. The fetch time moves and the
  # schedule is re-derived, because today moved.
  defp touch_title(%TitleRecord{} = record) do
    now = now()
    attrs = Map.put(schedule_attrs(record, record.media_type, record.payload, seasons(record.tmdb_id), now), :fetched_at, now)
    record |> TitleRecord.changeset(attrs) |> Repo.update()
  end

  defp publish_changed(%TitleRecord{tmdb_id: tmdb_id, media_type: media_type}) do
    Topics.publish(Topics.tmdb_titles(), {:tmdb_title_changed, {tmdb_id, media_type}})
  end

  defp subject(:movie, tmdb_id), do: "movie tmdb:#{tmdb_id}"
  defp subject(:tv_series, tmdb_id), do: "TV tmdb:#{tmdb_id}"

  defp schedule_words(%TitleRecord{settled_at: %DateTime{}}), do: ", settled"
  defp schedule_words(%TitleRecord{next_check_at: %DateTime{} = at}), do: ", next check #{DateTime.to_date(at)}"
  defp schedule_words(_record), do: ""
```

Note the `changed?` derivation: `record_fetched/3` sets `changed_at` to `now` only when the payload differs, and `fetched_at` to the same `now` — so equality of the two marks a change. Both are truncated to the second by `now/0`; a payload that changed twice within one second reads as changed, which is right.

If the write-through of Task 5 is already in place when this runs, `Client.detail/2` does **not** write through (only `get/3` does), so there is no double write here.

- [ ] **Step 4: Run the store tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/store_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb/store.ex test/media_centaur/tmdb/store_test.exs
git commit -m "feat(tmdb): Store.ensure and Store.check — first contact, conditional revalidation, open seasons, change event

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 5: Transitional write-through from `Client.get_*`

**Files:**
- Modify: `lib/media_centaur/tmdb/client.ex`
- Test: `test/media_centaur/tmdb/client_test.exs`

- [ ] **Step 1: Write the failing tests** — add to `client_test.exs`:

```elixir
  describe "write-through to the store" do
    alias MediaCentaur.TMDB.Store

    test "a movie detail fetched by a caller is stored with its etag" do
      Req.Test.stub(:tmdb, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=60")
        |> Plug.Conn.put_resp_header("etag", ~s(W/"wt"))
        |> Req.Test.json(MediaCentaur.TmdbStubs.movie_detail(%{"id" => 700}))
      end)

      assert {:ok, %{"id" => 700}} = Client.get_movie(700)
      assert %Store.TitleRecord{tmdb_id: 700, media_type: :movie, etag: ~s(W/"wt")} = Store.get({700, :movie})
    end

    test "a cache hit writes nothing" do
      Req.Test.stub(:tmdb, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=60")
        |> Req.Test.json(MediaCentaur.TmdbStubs.tv_detail(%{"id" => 701}))
      end)

      assert {:ok, _} = Client.get_tv(701)
      first = Store.get({701, :tv_series})
      backdated = backdate(first, :fetched_at, ~U[2026-01-01 00:00:00Z])

      assert {:ok, _} = Client.get_tv(701)
      assert Store.get({701, :tv_series}).fetched_at == backdated.fetched_at
    end

    test "a season detail is stored under its series" do
      Req.Test.stub(:tmdb, fn conn ->
        Req.Test.json(conn, MediaCentaur.TmdbStubs.season_detail(%{"season_number" => 3}))
      end)

      assert {:ok, _} = Client.get_season("702", 3)
      assert %Store.SeasonRecord{tmdb_id: 702, season_number: 3} = Store.get_season(702, 3)
    end

    test "a collection detail is not stored" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, MediaCentaur.TmdbStubs.collection_detail()) end)
      assert {:ok, _} = Client.get_collection(263)
      assert MediaCentaur.Repo.aggregate(Store.TitleRecord, :count) == 0
    end
  end
```

`ClientTest` is a `DataCase`, so `backdate/3` and the SQL sandbox are available.

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/client_test.exs`
Expected: FAIL — `Store.get/1` returns nil.

- [ ] **Step 3: Implement** in `lib/media_centaur/tmdb/client.ex`

Give `get/4` a store ref, pass it from the three detail getters, and write through on a fetched 200:

```elixir
  @spec get_movie(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_movie(tmdb_id, opts \\ []) do
    ref = {tmdb_id, :movie}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end

  @spec get_tv(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id, opts \\ []) do
    ref = {tmdb_id, :tv_series}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end

  @spec get_season(String.t() | integer(), integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number, opts \\ []) do
    ref = {:season, tmdb_id, season_number}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end
```

```elixir
  defp get(opts, request, subject, store_ref \\ nil) do
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)

    case Req.get(client, request ++ opts) do
      {:ok, %{status: 200, body: body} = response} ->
        outcome = Cache.outcome(response)
        Availability.observe_request({:ok, outcome})
        Log.info(:tmdb, log_line(subject, outcome))
        write_through(store_ref, outcome, body, response)
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Availability.observe_request({:error, {:http_error, status, body}})
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Availability.observe_request({:error, reason})
        {:error, reason}
    end
  end

  # Transitional (campaign tmdb-fetch-policy, Phase 1): every detail
  # payload a caller fetches is written to `TMDB.Store`, so the store
  # fills while callers still fetch for themselves. A cache hit writes
  # nothing — it asked nobody. Removed when the last detail caller reads
  # through the store.
  defp write_through(nil, _outcome, _body, _response), do: :ok
  defp write_through(_ref, :hit, _body, _response), do: :ok

  defp write_through({:season, tmdb_id, season_number}, _outcome, body, response) when is_map(body) do
    {:ok, _record} = Store.record_season_fetched(tmdb_id, season_number, body, etag(response))
    :ok
  end

  defp write_through({_tmdb_id, _media_type} = ref, _outcome, body, response) when is_map(body) do
    {:ok, _record} = Store.record_fetched(ref, body, etag(response))
    :ok
  end

  defp write_through(_ref, _outcome, _body, _response), do: :ok

  defp etag(response), do: List.first(Req.Response.get_header(response, "etag"))
```

Add `alias MediaCentaur.TMDB.Store`, and use `etag/1` in `detail/2` too. Add a *Write-through* paragraph to the moduledoc mirroring the comment.

- [ ] **Step 4: Run the client tests and the whole TMDB directory**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/`
Expected: all pass. If any other test now fails because a stubbed detail body is not a map (a stub returning a bare list, say), the final `write_through/4` clause covers it; if one fails because a stub answers a detail path with `%{"results" => []}`, that is now a stored payload with no title — acceptable for the store (no validation on shape), so it should still pass.

- [ ] **Step 5: Run the full suite once** — the write-through touches every detail fetch in the codebase.

Run: `~/scripts/agents/agent-mix test`
Expected: green. A failure here is most likely a sync test whose detail stub lacks `"id"`; the store does not require it, so investigate before changing any stub.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/tmdb/client.ex test/media_centaur/tmdb/client_test.exs
git commit -m "feat(tmdb): detail fetches write through to the store (transitional, Phase 1)

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 6: Search-query normalisation

**Files:**
- Modify: `lib/media_centaur/tmdb/client.ex`
- Test: `test/media_centaur/tmdb/client_test.exs`

- [ ] **Step 1: Write the failing test** — add to `client_test.exs` at top level (the module's `setup` starts the coordinator and stubs search):

```elixir
  test "a search that differs only in case and spacing is one request" do
    assert {:ok, _} = Client.search_movie("Sample Movie")
    assert {:ok, _} = Client.search_movie("  sample   MOVIE ")
    assert {:ok, _} = Client.search_multi("Sample Movie")
    assert {:ok, _} = Client.search_multi("sample movie")

    assert_receive {:tmdb_hit, "/3/search/movie"}
    assert_receive {:tmdb_hit, "/3/search/multi"}
    refute_receive {:tmdb_hit, _path}
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/client_test.exs`
Expected: FAIL — a third and fourth `:tmdb_hit` arrive.

- [ ] **Step 3: Implement** in `client.ex`: build every search's `query` param from `normalize_query/1`, keeping the caller's spelling for the console line.

```elixir
  # TMDB's search is case-insensitive and whitespace-tolerant; the
  # response cache's key is not. One spelling per question.
  defp normalize_query(title) do
    title |> String.trim() |> String.split() |> Enum.join(" ") |> String.downcase()
  end
```

In `search_movie/3`: `params = [query: normalize_query(title)] ++ if(year, do: [year: year], else: [])`; the same in `search_tv/3` (`first_air_date_year`) and `search_multi/2` (`params: [query: normalize_query(title)]`).

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb/client.ex test/media_centaur/tmdb/client_test.exs
git commit -m "fix(tmdb): one search request per question — the query is normalised before the cache key sees it

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 7: Delete `Identifiers.fetch/3`

**Files:**
- Modify: `lib/media_centaur/tmdb/identifiers.ex`
- Modify: `test/media_centaur/tmdb/identifiers_test.exs`

- [ ] **Step 1: Remove the three `fetch/3` tests** from `identifiers_test.exs` (the `describe` around lines 36–57 that calls `Identifiers.fetch/2`), and any stub setup used only by them.

- [ ] **Step 2: Delete `fetch/3`, `fetch_payload/3` and the `alias MediaCentaur.TMDB.Client`** from `identifiers.ex`. Trim the `@doc` and moduledoc of any sentence about fetching.

- [ ] **Step 3: Compile and run the file**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/identifiers_test.exs --warnings-as-errors`
Expected: pass, no warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur/tmdb/identifiers.ex test/media_centaur/tmdb/identifiers_test.exs
git commit -m "refactor(tmdb): remove Identifiers.fetch/3 — a TMDB-hitting entry point with no caller

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 8: Records — ADR-071, ADR-064 amendment, glossary, docs, campaign

**Files:**
- Create: `decisions/architecture/2026-09-20-071-tmdb-store-one-record-per-title.md`
- Modify: `decisions/architecture/2026-09-04-064-outbound-http-seam.md`
- Regenerate: `decisions/README.md`
- Modify: `docs/GLOSSARY.md`, `docs/tmdb.md`, `lib/media_centaur/tmdb.ex` (moduledoc), `campaigns/tmdb-fetch-policy.md`

- [ ] **Step 1: Write ADR-071**

```markdown
---
status: accepted
date: 2026-09-20
---
# TMDB knowledge is one record per title, asked only when due

## Context and Problem Statement

The app kept TMDB-derived facts in seven places and asked TMDB from
thirty call sites with no policy above the HTTP response cache: the
release-tracking refresher reloaded every tracked title every six
hours whether or not anything about it could still change, seven
surfaces fetched release facts on every open because nothing stored
them, and library metadata was frozen at import with no record of when
TMDB was last asked. The owner's rule: TMDB is consulted when the app
is *seeking new information* — whether a release date has been
announced — never on open for its own sake. Waste scales with the
library and the tracked set; a quiet day's request count is not a
ceiling.

## Decision Outcome

One record per identity, because every fetch site was a projection of
the same missing thing.

1. **`MediaCentaur.TMDB.Store` holds TMDB's last answer per
   `(media_type, tmdb_id)`** — the detail payload as received (the
   `images` block reduced to the selected logo), its ETag, when it was
   fetched and last changed — and, per stored season, the same. It is
   the only module that calls a `TMDB.Client` detail endpoint.
2. **Everything else is a projection.** Calendar rows, the render
   snapshot, the release window, the targeting universe, the library
   entity's TMDB fields, artwork paths: rebuilt from the record when it
   changes (`{:tmdb_title_changed, ref}` on `Topics.tmdb_titles/0`),
   never fetched on their own.
3. **A check is a conditional revalidation, made when due.** Due is the
   day after the title's next known event or seven days after the last
   fetch, whichever is first; a settled title — a movie past its home
   release or 180 days past its primary date with none typed, or
   canceled; a series ended or canceled with nothing ahead — is never
   due. `MediaCentaur.TMDB.Schedule` is the pure rule; the columns are
   derived on every write so due-ness is a stored fact, not a timer.
4. **Checks are scheduled for titles the user owns, listed, tracks or is
   acquiring.** A title known only through a friend's activity or a
   one-off open is stored on first contact and never scheduled.
5. **The response cache stands aside for a caller-conditional
   request.** `HttpClient.Cache` neither looks up nor stores a request
   carrying its own `If-None-Match` (`:conditional`); it keeps
   ADR-064's role for search, probes and every other upstream.

Rolled out in five phases (campaign `tmdb-fetch-policy`); in Phase 1
the store fills through a transitional write-through from
`TMDB.Client.get_*`, and nothing schedules a check yet.

### Consequences

* Good, because a settled title costs zero requests and an unsettled one
  costs one small revalidation per due check, at any library size.
* Good, because "does the app know this title" is one query, and a
  title's facts have one fetch time.
* Bad, because the store duplicates description fields the library
  entity also holds; the entity's copy is declared a projection
  (Phase 4) rather than removed, since it is the library's own model.
* Bad, because the payload is stored whole: tens of kilobytes per
  title, measured in Phase 1 before Phase 2 widens the population.
* Collections are not identities here and stay on the old path until
  `collection-identity` decides what a collection is.
```

- [ ] **Step 2: Amend ADR-064** — append to point 3 of *Decision Outcome*:

```markdown
   *Amendment 2026-09-20 (ADR-071):* a request the caller made
   conditional — carrying its own `If-None-Match` — passes the cache
   untouched, neither looked up nor stored, and reports `:conditional`.
   TMDB detail freshness is now a policy above this seam
   (`MediaCentaur.TMDB.Store`); `reload: true` remains for the
   credential probe and, until Phase 2 of `tmdb-fetch-policy`, the
   release-tracking refresher.
```

- [ ] **Step 3: Regenerate the index**

Run: `scripts/gen-decisions-index`
Expected: `decisions/README.md` gains the ADR-071 row.

- [ ] **Step 4: Glossary** — add a section after *Outbound integrations*:

```markdown
## TMDB store

The vocabulary of `tmdb-fetch-policy` (ADR-071): the app asks TMDB only
when it is seeking new information, and holds one record per title.

| Term | Meaning |
|---|---|
| **TMDB store** | `MediaCentaur.TMDB.Store`: one `TitleRecord` per `(media_type, tmdb_id)` — TMDB's last detail answer, its ETag, when it was fetched and last changed, and the derived schedule — with one `SeasonRecord` per stored season. The only module that calls a `TMDB.Client` detail endpoint. Not the **response cache** (`HttpClient.Cache`, ADR-064), which is per URL, in memory and policy-free. |
| **Fetch / request** | A fetch is a call into `TMDB.Client`; a request is a fetch that reached TMDB. A response-cache hit is not a request. |
| **First contact** | The fetch that creates a stored title the app has never held — `Store.ensure/2`. The only fetch that is not a check. |
| **Check** | A conditional revalidation of a stored title with its own ETag — `Store.check/2`; a 304 means unchanged. Open seasons are checked with their series. |
| **Release facts** | The fields that change over a title's life: typed release dates, air dates, episode lists, season count, status, next episode to air. Everything else is fixed once known. |
| **Settled title** | One whose release facts cannot change again: a movie at release stage `:home`, or 180 days past its primary date with no typed home date, or canceled; a series ended or canceled with no air date ahead. Never due. |
| **Next known event / due** | The earliest release fact ahead of today. A check is due the day after it (noon UTC) or seven days after the last fetch, whichever is first — `TMDB.Schedule.plan/5`. |
| **Open season** | A stored season still checked with its series: the latest numbered season, or one holding an episode with no air date or one ahead of today — `TMDB.Schedule.open_season?/3`. |
| **Projection** | Anything derived from a stored title — calendar rows, render snapshot, release window, targeting universe, library entity fields, artwork paths — rebuilt on `{:tmdb_title_changed, ref}`, never fetched on its own. |
```

- [ ] **Step 5: `docs/tmdb.md`** — add rows to *Module Reference* for `TMDB.Store`, `TMDB.Store.TitleRecord`, `TMDB.Store.SeasonRecord`, `TMDB.Schedule`; add a short *The store* subsection under *How It Works* stating what Phase 1 does (fills by write-through; `detail/2`; nothing scheduled yet) and pointing at ADR-071. Update the *Client* paragraph's sentence about `reload: true` to name the conditional path.

- [ ] **Step 6: `lib/media_centaur/tmdb.ex` moduledoc** — replace "TMDB owns no domain data and broadcasts no PubSub events" with: "TMDB owns the store — one record per title the app knows (`Store`, ADR-071) — and publishes `{:tmdb_title_changed, ref}` on `Topics.tmdb_titles/0` when a stored payload changes." Add `Store` and `Schedule` to the sentence listing exports.

- [ ] **Step 7: Campaign file** — in `campaigns/tmdb-fetch-policy.md` set `last_updated`, update *Status* to "Phase 1 shipped on main <date>: store filling by write-through; Phase 2 next", add a Decisions line `2026-09-20 — Phase 1 landed (ADR-071; commits …)`, and in *Next steps* put "Phase 2 plan: checks replace the refresher" first. Note under Next steps that the Phase 1 migration needs its *Migration safety* line in the CHANGELOG at the next release (two additive tables, no backfill).

- [ ] **Step 8: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASSED with zero warnings. Fix anything it reports (formatting via Quokka, Credo, Boundary, Sobelow) before committing.

- [ ] **Step 9: Commit**

```bash
git add decisions/ docs/GLOSSARY.md docs/tmdb.md lib/media_centaur/tmdb.ex campaigns/tmdb-fetch-policy.md
git commit -m "docs: ADR-071 TMDB store; ADR-064 amended; glossary and tmdb.md for the store; campaign Phase 1 landed

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

## Verification on the dev node (after precommit)

The dev service (`media-centaur-dev`) reloads code from this checkout. After the commits:

1. Run the migration against the dev database: `~/scripts/agents/agent-mix ecto.migrate` is **not** the right tool here (it builds under the agent build root); instead let the running node migrate — `~/scripts/agents/mc-eval 'Ecto.Migrator.run(MediaCentaur.Repo, :up, all: true)'`, or restart the dev service, which migrates on boot. Check `~/scripts/agents/mc-eval 'MediaCentaur.Repo.aggregate(MediaCentaur.TMDB.Store.TitleRecord, :count)'` returns `0`.
2. Wait for the next refresher tick (or open an unowned title in the UI) and confirm rows appear: the same `mc-eval` count rises, and `~/scripts/agents/mc-eval 'MediaCentaur.TMDB.Store.get({<tmdb_id>, :movie}) |> Map.take([:etag, :fetched_at, :next_event_on, :next_check_at, :settled_at])'` shows a schedule.
3. Measure payload size: `~/scripts/agents/mc-eval 'MediaCentaur.Repo.all(MediaCentaur.TMDB.Store.TitleRecord) |> Enum.map(&byte_size(:erlang.term_to_binary(&1.payload))) |> Enum.sort()'` — record min/median/max in the campaign file for the §7 decision 6 check.
4. Console: filter to `:tmdb` and confirm the `fetched … — from TMDB` lines are unchanged and no new line is louder than `info`.

## Self-review notes

* Spec coverage — Phase 1 items in design §5: schema and migration ✔ (Task 2); `Store` with `ensure`/`season`/`check`/`get`/`due` ✔ (Tasks 2, 4; `ensure_season` is the design's `season`); `Schedule` ✔ (Task 1); cache pass-through ✔ (Task 3); write-through ✔ (Task 5); search-key normalisation ✔ (Task 6); `Identifiers.fetch/3` deleted ✔ (Task 7); ADR + ADR-064 amendment + glossary ✔ (Task 8). The design's `scheduled` column is deferred to Phase 2 with the references logic that defines it — recorded in the migration moduledoc as "read by nothing until Phase 2".
* Type consistency — the store ref is `{tmdb_id, media_type}` everywhere (matching `TMDB.Title.ref/1`), seasons are `{:season, tmdb_id, season_number}`; `Client.detail/2` returns `{:ok, %{body, etag}} | {:ok, :unchanged} | {:error, reason}`; `Store.check/2` returns `{:ok, :unchanged | :changed, record} | {:error, reason}`.
* The `Log` `require` in `store.ex` is used from Task 4; Task 2's optional debug line exists only to keep the module warning-free between tasks.
