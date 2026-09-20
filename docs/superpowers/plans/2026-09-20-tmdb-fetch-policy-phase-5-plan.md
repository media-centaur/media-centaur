# TMDB fetch policy — Phase 5: retention and the gate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stored title nothing references ages out after seven days with its seasons; a Credo check makes "no module but `TMDB.Store` calls a detail endpoint" a compile-time fact; the records agree with the code; the campaign is closed by destination.

**Architecture:** The store's retention is one more `MediaCentaur.Retention` policy (`TMDB.RetentionPolicies`, subsystem `:tmdb`, mode `:sweep`, `run: &Store.sweep/0`), so the daily `Retention.SweepJob` runs it and the Status › Metadata drill-in's retention panel shows it beside the artwork policy — the two sweeps answer "who references this identity" through the same `TMDB.References.all/0`. `Store.sweep/0` deletes every `TitleRecord` whose ref no provider holds and whose `fetched_at` is older than seven days, plus a series' `SeasonRecord`s. Credo `MC0038 TmdbDetailSeam` flags `Client.detail/2` outside `lib/media_centaur/tmdb/store.ex` and `Client.get_collection/2` outside the import stage and the two artwork paths (row X: a collection is not a store identity). Design: [`2026-09-20-tmdb-fetch-policy-design.md`](../specs/2026-09-20-tmdb-fetch-policy-design.md) §2.4, §2.8, §3 row R, §5 item 5.

**House rules:** as Phases 1–4.

**Decisions made in this plan:**
- **No Status aggregate** (owner decision 2026-09-20; the design marked it droppable). Tiles carry no fact lines today; the Metadata drill-in's retention panel and the console lines are the store's observability.
- **Retention is `fetched_at`-based, not use-based.** A read never writes, so "last used" is unknowable for a record; "last fetched" is what the store knows. An unreferenced title someone opens weekly costs one first contact a week; that is the design's "one-off open" cost and is accepted. The artwork sweep stays mtime-based — different medium, same reference set, same seven days.
- **Two policies, one reference set.** The store's records and the artwork files are swept by their own policies, both asking `TMDB.References.all/0`; the design's "together with its artwork" is satisfied by the shared rule, not by one sweep deleting both.
- **`MC0038` matches the receiver by alias shape** (`Client`, `TMDB.Client`, `MediaCentaur.TMDB.Client`) like MC0003 does for `PubSub`; no other `Client` module in `lib/` exposes `detail/2` or `get_collection/2` (checked 2026-09-20). Tests are exempt.

---

### Task 1: The store's retention

**Files:** `lib/media_centaur/tmdb/store.ex` (`sweep/0`), create `lib/media_centaur/tmdb/retention_policies.ex`, `lib/media_centaur/tmdb.ex` (Boundary dep on `MediaCentaur.Retention`), `config/config.exs` (`:retention_policy_providers`), `lib/media_centaur/tmdb_artwork/retention_policies.ex` (description), `test/media_centaur/tmdb/store_test.exs`, create `test/media_centaur/tmdb/retention_policies_test.exs`.

- [x] Tests (`store_test.exs`, new `describe "sweep/0"`): a referenced title older than seven days survives (a tracked item's record backdated); an unreferenced title fetched eight days ago is removed with its seasons and counted; an unreferenced title fetched today stays; a movie and a series sharing a tmdb id — the movie unreferenced and old, the series held — lose only the movie (the series' seasons stay). `retention_policies_test.exs`: the policy is `:sweep` under `:tmdb` with `run` pointing at `Store.sweep/0`; `Retention.policies/0` includes `:tmdb_store`.
- [x] Implement `Store.sweep/0` (`@retention_days 7`; `References.all/0` for the held set; stale rows selected by `fetched_at < cutoff`, filtered in Elixir against the held set, deleted in one transaction with the seasons of removed series, chunked by 500 ids; one `:tmdb` info line naming the count). `TMDB.RetentionPolicies` with key `:tmdb_store`, label "TMDB store", description "Removed 7 days after the last fetch, once nothing references the title — no library entry, list entry, tracked title, plan or friend's activity." Register after `TmdbArtwork.RetentionPolicies`. Artwork description → "Removed 7 days after last use, once nothing references the title." `MediaCentaur.TMDB` adds `MediaCentaur.Retention` to its deps. Store moduledoc: retention paragraph.
- [x] Commit `feat(tmdb): the store's retention — unreferenced titles age out after seven days`.

### Task 2: The gate — MC0038

**Files:** create `credo_checks/tmdb_detail_seam.ex`, `test/media_centaur/credo/checks/tmdb_detail_seam_test.exs`; modify `.credo.exs`.

- [x] Tests: `Client.detail/2` in a `lib/` module that is not the store is flagged (`Client.detail`, `TMDB.Client.detail`, `MediaCentaur.TMDB.Client.detail`); the store is exempt; `get_collection/2` is flagged in `lib/media_centaur/discovery.ex` and exempt in the import stage and the artwork paths; a test file is exempt.
- [x] Implement the check (`category: :design`, `base_priority: :high`; exempt path lists checked at compile time like MC0029's seam path). Register in `.credo.exs` with a comment naming the campaign and ADR-071.
- [x] Commit `feat(credo): MC0038 — only TMDB.Store calls a detail endpoint`.

### Task 3: Records and closure

- [x] ADR-071: dated amendment — implemented 2026-09-20 in five phases; the transitional write-through is gone; MC0038 enforces the single caller; the Phase 4 placement (`Pipeline.TmdbProjection`, `Pipeline.TmdbReferences`). `docs/tmdb.md`: retention sentence and the gate. `docs/architecture.md`: `ReleaseTracking` and `TMDB` rows, the listener list (`Pipeline.TmdbProjection`). Design row R landed note; §5 unchanged. Glossary: merge the two *Projection* rows into one. Wiki `Troubleshooting.md`: the built-in policies list gains **TMDB store** and the artwork bullet is reworded (committed locally, not pushed).
- [x] Campaign: Status → **Complete on main 2026-09-20 (unreleased)**; Decisions → Phase 5 landed (the two decisions above); Next steps → the release: CHANGELOG lines (three migrations; interval setting gone, *Refresh from TMDB* new, three Maintenance buttons gone), push app and wiki together; closure by destination — ship: everything on main; verify after release: the boot tick on the production instance first-contacts its library; deferred: collections → `collection-identity`, response-cache persistence declined (row Z), the artwork sweep's mtime basis accepted. `campaigns/README.md`: entry moved to *Complete* with a closure summary. Memory: `project-tmdb-fetch-policy.md` → complete on main, awaiting release (merge into the shipped ledger at release).
- [x] Commit.

### Task 4: Gate and the dev node

- [x] `agent-mix precommit` (foreground). Restart `media-centaur-dev`; confirm `Retention.policies/0` lists `:tmdb_store`; run `Store.sweep/0` by hand and confirm it removes nothing (every record referenced or fresh); confirm the Metadata drill-in's retention panel names the policy; record in the campaign.
