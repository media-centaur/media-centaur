---
status: in-progress
started: 2026-05-22
last_updated: 2026-05-23
---
# Pursuit lifecycle stage tracking

## Goal

A pursuit (a tracked download) should follow its file through the real
pipeline — *downloaded → in review queue → landed in media library* —
mark itself **complete only when the file lands in the library**, and for
anything stuck in between, show **exactly which stage it's at** instead of
the cryptic "Not visible in your download client." This closes a class of
orphaned pursuits: manual (`prowlarr_query`) grabs have **no** completion
path at all today, and even TMDB grabs that complete-then-vanish from the
download client surface a confusing status. It matters now because real
pursuits are stranding in production (Top Gun Maverick, Remarkably Bright
Creatures, Exit 8 — all `prowlarr_query`, all showing "not visible").

## Status

Phases 1–4 complete, committed, and **shipped in v0.70.0** (feature commit
`8bdcf549` = `v0.70.0~2`, 2026-05-22; on `main` this is the same change,
crash-fix predecessor `51cbb686`). The migration
`20260522160000_add_download_identity_to_acquisition_targets.exs` shipped
with it. Completion now fires at library-landing for *all* pursuits via the
unified `LibraryReconciler` (content_path exact/under-dir → TMDB id →
release-title fallback); the cryptic "not visible in your download client"
is replaced by the real post-download stage ("Downloaded" / "In review" via
`PursuitStatus.derive/4`, fed by a batched `Review.pending_file_paths/0`
membership test). Storybook variations updated.

**Reconciled 2026-05-23.** The earlier "not yet shipped" status was wrong —
the code went out three releases ago, and the **wiki was already updated**
(`673c416`, 2026-05-22: full 5-stage lifecycle in `Prowlarr-Integration.md`
+ the "Downloaded — not landed" troubleshooting entry). The **cross-path
audit is done and clean** (2026-05-23): the single `Satisfy` command is fed
by the recipe-agnostic `LibraryReconciler`, `PursuitStatus.derive` has zero
recipe gates, and the three remaining `recipe_type == "tmdb"` queries
(`find_active_for_target` fast-path, `find_by_tmdb_recipe` idempotency-create,
`cancel_active_targets_for` item-removed) are all legitimately tmdb-scoped
with no missing tmdb-less analog — no other path can orphan a non-tmdb
pursuit. **The user-facing CHANGELOG entry was missed**, though: v0.70.0–
v0.72.0 release notes never describe the lifecycle feature (v0.70.0 shipped
it silently). Two items remain to fully close: (1) verify the 3 stranded
production pursuits actually resolved post-deploy (needs prod-REPL approval),
(2) decide whether to retro-document the changelog gap.

## Background — root cause (investigated 2026-05-22)

`prowlarr_query` pursuits carry no `tmdb_id`. **Both** completion paths key
on `tmdb_id`:

* Primary (seconds latency): `Pipeline Ingest broadcast → InboundListener →
  IdentityVerifier → Commands.Satisfy`. `InboundListener` builds a target
  from the *published entity's* `tmdb_id` and calls
  `find_active_for_target/1`, which hard-filters `recipe_type == "tmdb"`.
* Safety-net (15-min cron): `LibraryReconciler.reconcile_active/0` filtered
  to `recipe_type == "tmdb"`.

So a manual grab can never be satisfied; once qBittorrent drops the
completed torrent, the pursuit is orphaned (`Target` status `acquired`, no
queue item → "not visible").

## Lifecycle map (the signals we have)

The pipeline **does not rename or move files** — the path the watcher
detects (the download client's completed dir) flows *unchanged* into
review (`Review.PendingFile.file_path`, unique) and into the library
(`Library.WatchedFile.file_path`). So **file path is an exact stable key**
across stages — *if we capture it*.

| Stage | Detected by | Source of truth |
|---|---|---|
| Searching | `Target` `seeking`, no release | acquisition |
| Downloading | torrent in qB by hash, <100% | `Downloads.QueueMonitor` / `QueueItem` |
| Downloaded | torrent by hash at completed/100% | `QueueItem.state == :completed` |
| In review | file path is a pending `Review.PendingFile` | `Review` |
| **Landed in library** | file path is a `WatchedFile` | `Library` |
| Didn't import | torrent gone + path not in review/library | inferred |

What's missing today: nothing durable links a pursuit to its file. The
only link is normalized-title (`QueueMatcher`), which dies when the torrent
is removed. `QueueItem.id` is the torrent **hash** but exposes no save /
content path; `Target` persists neither hash nor path. Duplicate imports
(a UHD upgrade for a movie you already own) re-link/clean-up **silently** —
no signal to the pursuit (this is the Top Gun case: its UHD file never
became a `WatchedFile`; the clean-named `Top Gun- Maverick (2022) 4K.mkv`
is a *pre-existing* copy, since the pipeline never renames).

## Design

**Completion rule:** satisfy **only** at "landed in library." Everything
else stays active but reports its real stage. Top Gun therefore reads
"Downloaded — not imported (already in your library)", not "not visible."

**The one structural addition:** persist the **torrent hash + content
path** on `Target` when a release is grabbed (qBittorrent's API exposes
`content_path`; `QueueItem` just doesn't surface it yet). With the path
persisted, stage detection is exact lookups against the file-path-keyed
`PendingFile` / `WatchedFile` tables — robust to torrent removal and to
duplicates. Title-match remains as a **fallback** for path-less pursuits
(pre-existing ones, or grabs from before Phase 2).

## Decisions made

* `2026-05-22` — Completion = "file landed in the library" (a `WatchedFile`
  exists), not download-completion and not entity-presence. Duplicate /
  not-imported grabs are surfaced as a stage, never silently satisfied.
* `2026-05-22` — Link a pursuit to its file via **torrent hash + content
  path persisted on `Target`** at grab time; file path is the exact key
  across review/library because the pipeline never renames.
* `2026-05-22` — Phase 1 interim (title-match library detector) is **held,
  not shipped**; it becomes the path-less fallback inside the full build.
* `2026-05-22` — Capture lives in a dedicated `DownloadIdentity` module
  called from the Watcher tick (not `Observations` — keeps its two
  responsibilities intact per the modularity rule), matched by normalized
  title (`QueueMatcher`), write-once so a mid-move snapshot can't clobber
  the original landing path.

## Next steps

1. ~~**Phase 2 — persist download identity on `Target`.**~~ ✅ done
   2026-05-22 — `torrent_hash` + `content_path` columns, `QueueItem`
   `content_path`, `DownloadIdentity.capture!/3` write-once from the
   Watcher tick. (Optional follow-up: enrich `DownloadStarted.infohash`,
   currently hardcoded `nil`, from the observed queue item.)
2. ~~**Phase 3 — compute the stage + wire completion.**~~ ✅ done
   2026-05-22 — unified `LibraryReconciler` (content_path → tmdb →
   title), `PursuitStatus.derive/4` stage-aware display fed by
   `Review.pending_file_paths/0`, copy replaced, storybook updated.
   (Stage encoded directly in `derive/4` rather than a separate
   `PursuitStage` struct — the derive function already *is* the resolver.)
3. ~~**Phase 4 — UI.**~~ ✅ folded into Phase 3 — card + detail show the
   stage, actions for "didn't import" are `[:cancel, :change_target]`
   (re-grab), storybook variations added. (No separate page-smoke needed;
   `acquisition_live_test` already asserts the rendered status.)
4. ~~**Cross-path audit.**~~ ✅ done 2026-05-23 — clean. Completion flows
   through one `Satisfy` command whose catch-all caller (`LibraryReconciler`)
   is recipe-agnostic (content_path → tmdb → title); `PursuitStatus.derive`
   has no recipe gate; the three `recipe_type == "tmdb"` queries are all
   legitimately tmdb-scoped. No remaining path can orphan a non-tmdb pursuit.
5. ~~**Wiki.**~~ ✅ already done 2026-05-22 (`673c416`) — full 5-stage
   lifecycle in `Prowlarr-Integration.md`, "Downloaded — not landed" in
   `Troubleshooting.md`. Accurate and complete; no changes needed.
6. **Production verification** (BLOCKED on prod-REPL approval) — confirm the
   3 stranded pursuits resolved on the deployed build (Remarkably + Exit 8
   satisfy via fallback; Top Gun shows "downloaded, not imported"). Read-only
   diagnostic staged at `/tmp/mc_pursuit_check.exs` (lists rows via context
   functions); run with `~/scripts/mc-rpc < /tmp/mc_pursuit_check.exs`.
7. ~~Full `mix precommit` before ship; CHANGELOG note for the migration.~~
   The code shipped in v0.70.0 (precommit was green then). **Open decision:**
   the user-facing CHANGELOG entry was never written — retro-document in the
   next release's notes, or leave it (shipped three versions back)?

## Completion criteria

* A `prowlarr_query` grab whose file lands in the library auto-satisfies
  (verified end-to-end against the running app).
* A grab that completes but never imports (duplicate / rejected) shows a
  clear, accurate stage — never "not visible in your download client" and
  never silently satisfied.
* `Target` durably links to its download (hash + content path); stage
  detection survives torrent removal.
* The 3 currently-stranded production pursuits resolve (Remarkably + Exit 8
  satisfy via fallback; Top Gun shows "downloaded, not imported").
* Stage surfaced in the UI with story + page-smoke coverage; `mix
  precommit` green; wiki updated.

## Pointers

* Predecessors: [`done/pursuits-maturation.md`](done/pursuits-maturation.md),
  [`done/library-presence-unification.md`](done/library-presence-unification.md).
* Key modules: `lib/media_centarr/acquisition/pursuits/{inbound_listener,
  identity_verifier,library_reconciler,watcher,observations}.ex`,
  `lib/media_centarr/acquisition/{target,queue_matcher}.ex`,
  `lib/media_centarr/acquisition/view_models/pursuit_status.ex`,
  `lib/media_centarr/downloads/{queue_monitor,queue_item}.ex`,
  `lib/media_centarr/review.ex` (`PendingFile`), `lib/media_centarr/library.ex`
  (`find_present_*`, `list_present_file_paths`).
