# TMDB fetch policy — Phase 4: import and the library are projections

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No module but `TMDB.Store` calls a TMDB detail endpoint for a movie, a series or a season. Import is first contact when the library does not hold the title and a read of the store otherwise; an owned title is a reference that schedules checks; the library's TMDB fields and every season's episode list are rebuilt from the store when its record changes; the three Maintenance backfill buttons go; the transitional write-through goes.

**Architecture:** `TMDB.Store` grows the one fetch it lacked — `fetch_full/2` and `fetch_full_season/3`, TMDB's whole answer with the credits the library keeps and the store does not; the answer replaces the stored record as a changed check would and is returned untrimmed. `Pipeline.Stages.FetchMetadata` asks the library whether it owns the title (and the episode) before choosing between `Store.ensure` and `Store.fetch_full`. A new `Pipeline.TmdbProjection` (listener on `tmdb:titles` + `reapply/1`) re-applies `TMDB.Mapper` output to owned movies, series, seasons and episodes through Library context functions; a new `Pipeline.TmdbReferences` makes owned titles scheduled references. `ImageRefresh`, `ImageRepair` and the showcase seeder read the store (rows R-part and W pulled into this phase so the write-through and `Client.get_movie/get_tv/get_season` can be deleted here). Design: [`2026-09-20-tmdb-fetch-policy-design.md`](../specs/2026-09-20-tmdb-fetch-policy-design.md) §3 rows P, Q, R (detail reads), W; §2.1 credits amendment; §7 item 5.

**House rules:** as Phases 1–3 (`agent-mix`, test-first, no real titles, zero warnings, factories, session trailer on every commit, gate in the foreground with `timeout: 600000`).

**Decisions made in this plan:**
- **Placement.** `Library` depends on nothing TMDB-shaped (ADR-029) and stays that way: the projection and the owned-titles provider live in the `Pipeline` boundary, which already depends on both `TMDB` and `Library` and is the library's TMDB-facing side. The design's provisional `Library.TmdbProjection` becomes `Pipeline.TmdbProjection`.
- **Which fields TMDB may overwrite on an owned entity** (design §7 item 5): everything `Mapper.movie_attrs/3`, `tv_attrs/2` and `episode_attrs/2` produce **except** the credits (`cast`, `crew`, `cast_person_ids` — fetched whole once at materialisation, not stored) and the collection facts (`position`, `movie_series_id` — a collection is not a store identity, row X). No library field is person-edited, so nothing else is protected. `imdb_id` is re-put on `library_external_ids`.
- **Credits are one fetch per materialised entity, through the store.** `Store.fetch_full/2` is the same detail request first contact makes; the store keeps the trimmed record and the import keeps the credits. A batch import of one season is one season request — the response cache (ADR-064) answers the rest. An owned series gets no request for its next episode file; an owned episode gets none for a re-import.
- **The three Maintenance buttons are removed** (owner decision 2026-09-20, measured: 30 movies, 14 series, 676 episodes, 47 seasons on the owner's instance, none lacking credits or episode lists). *Refresh episode lists* is what the projection does on every change; the credits backfills served libraries imported by pre-credits versions.
- **A season the store lacks is first-contacted by the projection only when open** — the series' latest numbered season, or one whose library episode list names an undated or future episode — mirroring `TMDB.Schedule.open_season?/3` on the library's own list. A closed season the store never held stays as imported.
- **`Mapper.episode_list/1`** becomes the one builder of `Season.episode_list` entries (three copies today: the import stage, Maintenance, the showcase).
- Collections stay on `Client.get_collection/2` (row X, `collection-identity`).

---

### Task 1: The store's full fetch

**Files:** `lib/media_centaur/tmdb/store.ex`, `test/media_centaur/tmdb/store_test.exs`.

- [x] Tests (new `describe "fetch_full/2 and fetch_full_season/3"`): an unheld movie is fetched, stored trimmed (`Store.get` payload has ≤ 10 cast, Directing crew only) and returned whole (12 cast, a Writer in the crew); a held movie is fetched again without `If-None-Match` (stub sends `{:tmdb_hit, path, validator}`; validator `[]`), a changed payload replaces the record and publishes `{:tmdb_title_changed, ref}`, an identical one publishes nothing; a season is returned with `credits` and per-episode `guest_stars` while the record has neither, and a changed season publishes the **series'** ref; `client:` is passed through; a TMDB error is returned and the record left as it was.
- [x] Implement:

```elixir
  @doc """
  The title as TMDB returns it today — credits included — for the one
  reader that keeps them: the import, when it materialises a library
  entity (design §2.1, amended 2026-09-20). Unconditional: the answer
  replaces the stored record the way a changed check would (trimmed,
  schedule re-derived, `{:tmdb_title_changed, ref}` published when the
  payload changed) and is returned whole. Not a check — nothing asks
  whether the title is due. The response cache absorbs a batch.
  """
  @spec fetch_full(ref(), keyword()) :: {:ok, map()} | {:error, any()}
  def fetch_full({tmdb_id, media_type} = ref, opts \\ []) do
    with {:ok, %{body: body, etag: etag}} <- Client.detail(ref, opts),
         {:ok, record, changed?} <- write_fetched(ref, body, etag) do
      Log.info(:tmdb, "fetched #{subject(media_type, tmdb_id)} whole#{schedule_words(record)}")
      if changed?, do: publish_changed(record)
      {:ok, body}
    end
  end

  @spec fetch_full_season(pos_integer() | String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, any()}
  def fetch_full_season(tmdb_id, season_number, opts \\ []) do
    with {:ok, %{body: body, etag: etag}} <- Client.detail({:season, tmdb_id, season_number}, opts),
         {:ok, _season, changed?} <- write_season_fetched(tmdb_id, season_number, body, etag) do
      if changed?, do: publish_changed({tmdb_id, :tv_series})
      {:ok, body}
    end
  end
```

  `record_fetched/3` and `record_season_fetched/4` keep their signatures and call the new private `write_fetched/3` / `write_season_fetched/4`, which return `{:ok, record, changed?}` (the parse + `payload_for?` + store steps they hold today). `publish_changed/1` accepts a ref as well as a record (`{tmdb_id, media_type}` with a parsed id). Moduledoc: the store's three fetches are first contact, a check, and the full fetch.
- [x] Commit `feat(tmdb): the store's full fetch — TMDB's whole answer for the import, stored trimmed`.

### Task 2: Import reads the store

**Files:** `lib/media_centaur/pipeline/stages/fetch_metadata.ex`, `lib/media_centaur/tmdb/mapper.ex` (`episode_list/1`), `test/media_centaur/pipeline/stages/fetch_metadata_test.exs`, `test/media_centaur/tmdb/mapper_test.exs`.

- [x] Tests (existing stubs keep answering — a first contact is still a request). Add: a series the library owns is not fetched for a new episode — `create_tv_series` + `create_external_id(source: "tmdb")` + `create_title_record` (tv, seasons `[1]`), then `stub_tmdb_error("/tv/1396", 500)` with the season route stubbed: `run/1` succeeds and the season carries the stubbed episodes; a movie the library owns (second file) is read from the store — `stub_tmdb_error("/movie/550", 500)` after `create_title_record`: `run/1` succeeds; a new movie is fetched whole — stub a `movie_detail` with 12 cast and a `Writer` crew entry: `entity_attrs.cast` has 12 and a Writer, while `Store.get({550, :movie}).payload["credits"]["cast"]` has 10; an episode the library holds (a present file for S01E01 via factories) reads the stored season — `stub_tmdb_error("/tv/1396/season/1", 500)` after `create_season_record`: `run/1` succeeds and `season.episode.attrs.name` is the stored name; a new episode fetches the season whole even when the store holds it — stub a season with `credits` and `guest_stars`: `season.episode.attrs.cast_person_ids` non-empty and the stored season record still has no `credits`; the divert case reads `seasons` from the stored payload (existing test, now against a stored title); a movie detail failure is still `{:error, _}`. `mapper_test`: `episode_list/1` maps number, name and air date and turns `""` into nil.
- [x] Implement. `alias MediaCentaur.Library.ExternalIds`, `alias MediaCentaur.TMDB.{Client, Mapper, Store}` (`Client` stays for `get_collection/1`).

```elixir
  defp fetch_metadata(%Payload{tmdb_id: tmdb_id, parsed: parsed}, :movie) do
    with {:ok, data} <- title_payload({tmdb_id, :movie}) do
      case data["belongs_to_collection"] do
        %{"id" => collection_id} -> fetch_movie_in_collection(tmdb_id, data, parsed, collection_id)
        _ -> build_standalone_movie(tmdb_id, data, parsed)
      end
    end
  end

  defp fetch_metadata(%Payload{tmdb_id: tmdb_id, parsed: parsed}, :tv) do
    with {:ok, data} <- title_payload({tmdb_id, :tv_series}), do: build_tv(tmdb_id, data, parsed)
  end

  # Import is first contact when the library does not hold the title and a
  # read of the store otherwise (ADR-071). A title the library owns needs
  # no credits — the entity exists and this file only links to it — so the
  # stored copy serves; a new one is fetched whole, credits included, and
  # that answer becomes (or refreshes) the stored record.
  defp title_payload({tmdb_id, media_type} = ref) do
    result =
      if is_nil(ExternalIds.find_by_external_id(media_type, to_string(tmdb_id))),
        do: Store.fetch_full(ref),
        else: with({:ok, %{payload: payload}} <- Store.ensure(ref), do: {:ok, payload})

    result
  end

  # A season is fetched whole for an episode the library does not hold —
  # its guest stars are the episode's credits; a held episode, or an
  # extra with no episode, reads the stored season.
  defp season_payload(tmdb_id, %{season: season_number, episode: nil}),
    do: with({:ok, %{payload: payload}} <- Store.ensure_season(tmdb_id, season_number), do: {:ok, payload})

  defp season_payload(tmdb_id, %{season: season_number, episode: episode_number}) do
    case ExternalIds.find_present_episode(to_string(tmdb_id), season_number, episode_number) do
      {:ok, _file_path} -> with({:ok, %{payload: payload}} <- Store.ensure_season(tmdb_id, season_number), do: {:ok, payload})
      :not_found -> Store.fetch_full_season(tmdb_id, season_number)
    end
  end
```

  `build_ingest_metadata/5` calls `season_payload(tmdb_id, parsed)` in place of `Client.get_season/2`; `build_season/2` uses `Mapper.episode_list(season_data)`; the stage's `episode_list_entry/1` and `presence/1` go. Log lines say "read" when the store served and "fetched" when TMDB did — pass the source back from `title_payload/1` as `{:ok, payload, :stored | :fetched}` if that is the only way to say it honestly, else log at the store. Moduledoc: the stage reads the store; the collection fetch is the one detail request it still makes itself.
- [x] Commit `feat(pipeline): import reads the TMDB store — first contact for a new title, the stored copy for an owned one`.

### Task 3: The library is re-projected on change

**Files:** create `lib/media_centaur/pipeline/tmdb_projection.ex`, `test/media_centaur/pipeline/tmdb_projection_test.exs`; modify `lib/media_centaur/library/movie.ex` (`update_changeset/2`), `lib/media_centaur/library/containers.ex` (Movie clause; moduledoc), `lib/media_centaur/library/episode.ex` (`update_changeset/2`), `lib/media_centaur/library/episodes.ex` (`update/2`), `lib/media_centaur/library/seasons.ex` (`update_episode_list/2`), `lib/media_centaur/library/season.ex` (doc), `lib/media_centaur/pipeline.ex` (export `TmdbProjection`), `lib/media_centaur/application.ex` (`pubsub_listeners`).

- [x] Tests (`DataCase`): a movie's TMDB fields follow the store — `create_movie(%{name: "Old Name", cast: [...]})` + `create_external_id` + `create_title_record(payload: movie_detail(%{"title" => "New Name", "status" => "Released", "overview" => "New overview"}))`, `reapply({550, :movie})`: name, description and status updated, `cast` untouched, `imdb` external id put, `{:entities_changed, %EntitiesChanged{}}` received after `Library.subscribe()`; a series follows the store — name and `status: :ended` updated, `Season.episode_list` rebuilt from the stored season, an episode named "TBA" takes its stored name and date, an episode the stored season lacks is untouched, `cast_person_ids` untouched; an open season the store lacks is first-contacted (the series' latest season; stub its route; `Store.get_season` then holds it) and a closed one is not (`stub_tmdb_error` on its route; `reapply/1` still `:ok`); an unowned ref and an unstored ref are `:ok` no-ops.
- [x] Implement the Library seams first: `Movie.update_changeset/2` casting `@projected_fields` (`[:name, :description, :date_published, :duration_seconds, :director, :content_rating, :url, :aggregate_rating_value, :vote_count, :tagline, :original_language, :studio, :country_code, :genres, :status]`); `Containers.update(%Movie{}, attrs)`; `Episode.update_changeset/2` casting `[:name, :description, :duration_seconds, :date_published]`; `Episodes.update/2`; `Seasons.update_episode_list/2` (wraps `Season.episode_list_changeset/2`). Rewrite `Containers.update/2`'s moduledoc: containers are re-projected from the TMDB store on change (`Pipeline.TmdbProjection`), so a series that ends does end.
- [x] Implement the projection:

```elixir
defmodule MediaCentaur.Pipeline.TmdbProjection do
  @moduledoc """
  The library's TMDB fields are a projection of the TMDB store (ADR-071,
  design §2.6). Subscribes to `Topics.tmdb_titles/0`; on
  `{:tmdb_title_changed, ref}` re-applies `TMDB.Mapper`'s output to the
  owned movie or series — every field the mapper derives except the
  credits (fetched whole once, at import; `Store` does not keep them) and
  the collection facts — and, for a series, rebuilds each library
  season's episode list and each episode's name, overview, runtime and
  air date from the stored season. A season the store lacks is
  first-contacted when it is open (the series' latest, or one naming an
  undated or future episode); a closed one stays as imported.

  Lives in the pipeline, the library's TMDB-facing side: `Library`
  depends on nothing TMDB-shaped (ADR-029). Skipped in `:test`; tests
  call `reapply/1` directly.
  """
  use GenServer
  ...
  @spec reapply(TMDB.Store.ref()) :: :ok
  def reapply({tmdb_id, :movie} = ref) do
    case {ExternalIds.find_by_external_id(:movie, to_string(tmdb_id)), Store.get(ref)} do
      {%Movie{} = movie, %{payload: payload}} ->
        attrs = Mapper.movie_attrs(tmdb_id, payload, nil)
        {:ok, movie} = Containers.update(movie, Map.take(attrs, @movie_fields))
        _ = ExternalIds.put(:imdb, movie, attrs.imdb_id)
        Library.broadcast_entities_changed([movie.id])
        :ok
      {nil, _record} -> :ok
      {_movie, nil} -> :ok
    end
  end
```

  Series: `Containers.update(series, Map.take(Mapper.tv_attrs(id, payload), @series_fields))`, imdb put, then `for season <- Seasons.list_for_tv_series(series.id)` → `season_payload(tmdb_id, season, payload)` (`Store.get_season`, else `Store.ensure_season` when `open_season?/3`, else `nil`) → `Seasons.update_episode_list(season, Mapper.episode_list(season_payload))` and `for episode <- Episodes.list_for_season(season.id)`, when the payload names it, `Episodes.update(episode, Map.take(Mapper.episode_attrs(season_payload, n), @episode_fields))`. Log one `:library` info line per re-projected entity. Register in `pubsub_listeners/1` after `ReleaseTracking.TmdbListener`; export from `Pipeline`.
- [x] Commit `feat(pipeline): the library is re-projected from the TMDB store when a title changes`.

### Task 4: Owned titles are scheduled references

**Files:** create `lib/media_centaur/pipeline/tmdb_references.ex`, `test/media_centaur/pipeline/tmdb_references_test.exs`; modify `lib/media_centaur/library/external_ids.ex` (`list_tmdb_refs/0`), `config/config.exs`, `lib/media_centaur/pipeline.ex` (export), `test/media_centaur/tmdb/references_test.exs` (the configured list), `test/media_centaur/library/external_ids_test.exs`.

- [x] Tests: `list_tmdb_refs/0` returns `{id, :movie}` / `{id, :tv_series}` for every `tmdb` external id on a movie or series, ignores collections and unparsable ids; the provider's `references/0` is that set and `schedules_checks?/0` is true; `References.providers/0` lists five.
- [x] Implement. `ExternalIds.list_tmdb_refs/0`: `from(e in ExternalId, where: e.source == "tmdb" and e.owner_type in [:movie, :tv_series], select: {e.owner_type, e.external_id})`, ids parsed with `Integer.parse/1`, the rest dropped. `Pipeline.TmdbReferences` moduledoc: an owned title is a standing reference — its record and artwork never age out, and its release facts are checked while unsettled, so the library's projection has something to follow. Append to `:tmdb_reference_providers`.
- [x] Commit `feat(pipeline): owned titles are TMDB references that schedule checks`.

### Task 5: The last detail callers move; the write-through goes

**Files:** `lib/media_centaur/pipeline/image_refresh.ex`, `lib/media_centaur/pipeline/image_repair.ex`, `lib/media_centaur/showcase.ex`, `lib/media_centaur/tmdb/client.ex`, tests `image_refresh_test.exs`, `image_refresh_worker_test.exs`, `image_repair_test.exs`, `showcase_test.exs`, `showcase/stubs_test.exs`, `client_test.exs`.

- [x] Tests: `ImageRefresh.refresh_entity/2` twice makes one request (second call after `stub_tmdb_error`); `ImageRepair` rebuilds a poster path from a held title without a request; the client's `write-through to the store` describe is deleted; `get_movie/get_tv/get_season` tests become `detail/2` tests or go; showcase stubs tests still pass with the seeder reading `fetch_full`.
- [x] Implement: `ImageRefresh.fetch_metadata/2` → `Store.ensure({id, :movie | :tv_series})` payload (collections stay on `Client.get_collection`); `ImageRepair.derive_source_url/4` → `Store.ensure` / `Store.ensure_season`; `Showcase` → `Store.fetch_full(ref, client: client)`, `Store.fetch_full_season(id, n, client: client)`, `Mapper.episode_list/1`. `Client`: delete `get_movie/2`, `get_tv/2`, `get_season/3`, `write_through/4`, `note_write/2`, the `store_ref` argument of `get/4`, the `Store` alias; moduledoc: `detail/2` is the store's, `get_collection/2` the one detail endpoint outside it (row X). `TmdbStubs.stub_get_*` helper names stay — they name routes.
- [x] Commit `refactor(tmdb): image refresh, image repair and the showcase read the store; the write-through and Client.get_movie/get_tv/get_season go`.

### Task 6: The Maintenance backfills go

**Files:** `lib/media_centaur/maintenance.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/maintenance_section.ex`, `lib/media_centaur/library/{movie,tv_series,person,episode,episodes,writable,season,episode_list_entry}.ex`, `test/media_centaur/maintenance_test.exs`, `test/media_centaur_web/live/settings_live_test.exs`, wiki `Settings-Reference.md` (and `Browsing-Your-Library.md` if it names a button).

- [x] Delete: `refresh_movie_credits/0`, `refresh_series_credits/0`, `refresh_episode_lists/0`, their `_async` variants and every private function only they used (`refresh_credits/1` through `build_series_credits_attrs/1`, `records_with_tmdb_id/*`, `season_complete?/1`, `episode_list_entry/1`, `backfill_episode_cast_membership/2`, `series_credits_refreshed?/1`); the `Client`/`Mapper` aliases and `MediaCentaur.TMDB` from `Maintenance`'s Boundary deps if nothing else in the module uses them; the three buttons, their attrs, handlers, result handlers and assigns; `Movie.update_credits_changeset/2`, `TVSeries.update_credits_changeset/2`, `Person.put_credits/2`, `Episode.cast_membership_changeset/2`, `Episodes.update_cast_membership/2`, the `update_credits_changeset` callback and table row in `Writable`; the three `describe`s in `maintenance_test.exs` and the *Refresh episode lists* describe in `settings_live_test.exs`. Reword the docs that name the buttons (`season.ex`, `episode_list_entry.ex`, `Maintenance` moduledoc, `maintenance_section.ex` moduledoc).
- [x] Wiki: replace the three bullets with one paragraph under the maintenance list — episode lists, air dates, names, status and the rest of a title's TMDB facts follow TMDB on their own through the scheduled checks; *Refresh from TMDB* on a title asks now; credits are fetched when a title is imported. Commit the wiki locally (not pushed).
- [x] Commit `refactor(maintenance): the credits and episode-list backfills go — the library follows the TMDB store`.

### Task 7: Records

- [x] `docs/tmdb.md`: the architecture diagram (FetchMetadata → Store → Client), the "consumed by" paragraph, the store paragraph (Phase 4 state: import through the store, the projection, owned titles scheduled, write-through gone), the module table (`Pipeline.TmdbProjection`, `Pipeline.TmdbReferences`). `docs/pipeline.md` FetchMetadata rows. Design rows P, Q, W landed with dated notes; row R's detail-read half noted as landed here. Glossary: *Reference* row (owned titles schedule), new rows *Full fetch* and *Projection*. `campaigns/tmdb-fetch-policy.md`: Status, Decisions (Phase 4 landed: placement, the field rule, the buttons, the full fetch), Next steps → Phase 5, Completion criteria (a full fetch at materialisation is the fifth kind of fetch), and correct the Phase 3 verification note (the tick first-contacts *scheduled* references only; the three listed-only titles were stored by the write-through). `campaigns/README.md`.
- [x] Commit.

### Task 8: Gate and the dev node

- [x] `agent-mix precommit` (foreground). Restart `media-centaur-dev`; confirm the `@reboot` tick first-contacts the owned titles the store lacks (about 36 on the owner's instance; 50 per tick); confirm `Pipeline.TmdbReferences.references/0` matches the owned count; force one owned series through `Store.check/1` and confirm its library season lists and status agree with the store; confirm the Settings › Maintenance section renders without the three buttons; record in the campaign.
