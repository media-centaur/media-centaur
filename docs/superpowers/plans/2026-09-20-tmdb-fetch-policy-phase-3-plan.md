# TMDB fetch policy — Phase 3: surfaces read the store

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No LiveView, job or context outside the import pipeline calls a TMDB detail endpoint. The unowned title preview, the plan board and plan preview, series targeting, cour detection, the reconcile spine, the movie plan door and the artwork warm read `TMDB.Store`; the title intent's embedded snapshot goes; listed and planned titles schedule checks.

**Architecture:** `TMDB.Store` grows the two projections the surfaces need — `snapshot/1` and `snapshots/1` (the `TMDB.Title` render snapshot from a stored payload) — publishes `{:tmdb_title_changed, ref}` on first contact too, and keeps the ten top-billed cast entries and the directing crew in the trimmed payload (owner decision 2026-09-20: the unowned preview re-reads them). Every surface swaps `TMDB.Client.get_*` for `Store.ensure/2` or `Store.ensure_season/3`; the artwork warm's first contact is what gives a freshly listed title its record. `TitleIntent.title` becomes a virtual field attached from the store (`Discovery.Titles.attach/1`, the pattern `ReleaseTracking.Titles` set), and the `title_intents.title` column is dropped. Design: [`2026-09-20-tmdb-fetch-policy-design.md`](../specs/2026-09-20-tmdb-fetch-policy-design.md) §3 rows G, I–O, V.

**House rules:** as Phases 1–2 (`agent-mix`, test-first, no real titles, zero warnings, factories, session trailer on every commit, gate in the foreground).

**Decisions made in this plan:**
- The stored payload keeps `credits.cast` / `aggregate_credits.cast` to the ten top-billed and `credits.crew` to the Directing department (the preview's facet strip shows the director). Everything else in the credits goes as before.
- First contact publishes `{:tmdb_title_changed, ref}` like a changed check: a record appearing is a change to whoever renders the title.
- `TmdbArtwork.ensure/2` reading the store is what first-contacts a newly listed or ingested title — no new task in `Discovery.put_rung/3`.
- `mix media_centaur.refresh_tracking_images` is retired: no undersized artwork exists on the owner's instance (checked 2026-09-20), and its only job was a one-time migration of legacy thumbnails.
- `RungChanged.title` may be nil (a title forgotten before the store ever held it); `Activities.Publisher` shares a listing only when it has one.

---

### Task 1: The store — cast kept, snapshots, first contact publishes, a subscribe door

**Files:** `lib/media_centaur/tmdb/store.ex`, `test/media_centaur/tmdb/store_test.exs`.

- [x] Tests (add to `store_test.exs`):
  - `trim_payload/1` keeps the ten top-billed `credits.cast` (sorted by `"order"`) and `credits.crew` entries with `"department" == "Directing"` for a movie; keeps ten `aggregate_credits.cast` for a series; drops the rest; season credits still dropped.
  - `snapshot/1` returns a `%TMDB.Title{}` built from the payload (`Title.from_tmdb/2`) or nil; `snapshots/1` batches by ref.
  - `ensure/2` on first contact publishes `{:tmdb_title_changed, ref}`; a stored title does not.
  - `subscribe/0` subscribes the caller to `Topics.tmdb_titles/0`.
- [x] Implement: `trim_credits/1` inside `trim_payload/1`; `snapshot/1`, `snapshots/1`, `subscribe/0`; `first_contact/2` publishes. Moduledoc updated.
- [x] Commit `feat(tmdb): the store keeps the preview's cast, renders snapshots, and announces first contact`.

### Task 2: Surfaces read the store

**Files:** `lib/media_centaur_web/live/title_detail_host.ex` (`fetch_payload/1` → `Store.ensure`; subscribe to TMDB and refresh the open detail on `{:tmdb_title_changed, ref}` for its ref), `lib/media_centaur_web/live/incoming_live.ex` (`load_targeting/2` movie branch and `maybe_load_plan_release_window/3` → `Store.ensure`; comment rewritten), `lib/media_centaur/acquisition/targeting.ex` (`series_selection/1` → `Store.ensure` + `Store.ensure_season` per season; the `client` parameter goes), `lib/media_centaur/acquisition/plans.ex` (`movie_plan_attrs/1` → `Store.ensure`), `lib/media_centaur/acquisition/cours.ex` (→ `Store.ensure_season`), `lib/media_centaur/reconciliation/spine.ex` (→ `Store.ensure` / `ensure_season`), `lib/media_centaur/tmdb_artwork.ex` (`fetch_missing/2` → `Store.ensure` payload), `lib/media_centaur/acquisition/tmdb_references.ex` (`schedules_checks?` → true), delete `lib/mix/tasks/media_centaur.refresh_tracking_images.ex`, `lib/media_centaur_web/live/subscriptions.ex` unchanged (`TMDB.Store` gets `subscribe/0`, so `Subscriptions.subscribe(socket, {MediaCentaur.TMDB.Store, :subscribe})`).

- [x] Tests: each surface's existing tests keep their stubs (a first contact still answers from the stub); add one assertion per surface that a **second** call makes no request (`refute_receive {:tmdb_hit, …}`): targeting (`targeting_test.exs`), cours (`cours_test.exs` if present, else `acquisition_test.exs` list_alternatives), spine (`spine_test.exs`), the host's preview (`title_detail_host` or `discovery_live_test` open-a-title test), the artwork warm (`tmdb_artwork_test.exs`).
- [x] Implement each swap. Where a caller passed string ids, `Store` parses them.
- [x] Commit `feat: the preview, plan board, targeting, cours, spine, plan door and artwork warm read the TMDB store`.

### Task 3: The intent's snapshot comes from the store

**Files:** create `priv/repo/migrations/20260920150000_title_intents_read_the_store.exs` (remove `title`; `down` re-adds `:map`), `lib/media_centaur/discovery/titles.ex` (`attach/1`, `attach_one/1` from `Store.snapshots/1`; a missing record attaches `%Title{tmdb_id, media_type, name: nil}` so a row renders blank until first contact lands); modify `lib/media_centaur/discovery/title_intent.ex` (virtual `title`; `create_changeset/3` takes the `Title` for its identity only; `rung_changeset/2` drops the title), `lib/media_centaur/discovery.ex` (`put_rung` → creation from the given title, no embed; `get_intent`, `list_watchlist` attach; `announce` uses the given title on creation and the attached one otherwise; `forget` uses the attached one, which may be nil), `lib/media_centaur/discovery/events.ex` (`title` optional in `RungChanged`), `lib/media_centaur/activities/publisher.ex` (share a listing only with a `%Title{}`), `lib/media_centaur/discovery/tmdb_references.ex` (`schedules_checks?` → true), `lib/media_centaur_web/live/discovery_live.ex` (subscribe `{MediaCentaur.TMDB.Store, :subscribe}`; `handle_info({:tmdb_title_changed, _ref}, …)` → `load_items`), `test/support/factory.ex` (`create_title_intent` stores a title record carrying the name, like `create_tracking_item`).

- [x] Tests: `discovery_test.exs` — a listed title's watchlist row carries the stored snapshot; a listing whose title the store lacks renders with a nil name until first contact; `forget/2` of a never-stored title still broadcasts. `publisher_test.exs` — the listing is shared with the snapshot. Discovery/watchlist LiveView tests: stub the detail where a test asserts a name after `put_rung`.
- [x] Commit `feat(discovery): the title intent reads its snapshot from the store — embed dropped`.

> Executed 2026-09-20. Two departures from the text above: `put_rung/3` announces the title the person acted on in **both** branches (always named, so a listing from Ignored can still be shared — the store may not hold a title that was only ever ignored), and a record the store lacks attaches a *bare identity* `%Title{}` rather than nil, so the row and `title_poster_url/1` render without a nil guard; `RungChanged.title` therefore stays required. The host's snapshot chain reads `Store.snapshot/1` directly instead of the intent's title. Discovery live tests seed the store through a `list/4` helper (`TmdbStubs.detail_for/1`) rather than stubbing a detail per test.

### Task 4: Records

- [ ] `docs/tmdb.md` store paragraph (Phase 3 state), design doc rows G/I–O/V marked landed with a dated note, `campaigns/tmdb-fetch-policy.md` (Status, Decisions, Next steps → Phase 4), `campaigns/README.md`; glossary *Reference* row (listed and planned now schedule). Wiki: nothing user-visible changed in this phase beyond speed; no edit.
- [ ] Commit.

### Task 5: Gate and the dev node

- [ ] `agent-mix precommit` (foreground). Restart `media-centaur-dev`; confirm the migration ran; open an unowned title and confirm no request on the second open; confirm the boot tick now first-contacts the 8 listed titles; record in the campaign.
