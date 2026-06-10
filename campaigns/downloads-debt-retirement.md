---
status: in-progress
started: 2026-06-10
last_updated: 2026-06-10
---
# Downloads debt retirement

## Goal

Close the gap between the downloads system as it evolved and the system
we would build from scratch knowing the final model. The 2026-06-10
audit found the composite-pursuit/plan/corpus architecture sound but
carrying the journey to it: five identity-matching mechanisms (the
highest-churn, highest-bug subsystem — ~700 fix lines across 5 commits),
ADR-055 migration scar tissue (interim resolvers, dual identity schema),
UI session state living in the Search context, a download-client seam
that can't actually host a second client, and a handful of UI gaps
(unguarded plan discard, split cell vocabulary).

## Status

Audit complete; campaign created. Executing items in priority order —
nothing shipped yet.

## Work items (priority order)

1. **Guard plan discard.** `plan_discard` (`acquisition_live.ex:823`)
   destroys a solved-and-steered draft plan on one click while the
   adjacent download-cancel gets a confirmation modal. Add the same
   confirmation gate.
2. **Unify identity matching.** Five mechanisms (QueueMatcher,
   DownloadIdentity, LibraryReconciler's 3-stage fallback,
   IdentityVerifier, InfoHash) re-implement hash/path/tmdb/release-name
   strategies per lifecycle stage. Consolidate the *strategies* into one
   module with explicit precedence that all stages consult; capture the
   full durable identity envelope (hash + content_path) atomically at
   grab/first-observation time. Production bug history lives here
   (v0.77.3→.4 regression pair, orphaned packs, tracker-prefixed names).
3. **Retire the ADR-055 interim layer.** Migrate legacy pursuit-level
   season/episode onto units (idempotent backfill), then delete the
   dual-schema fallback in `CommitPlan.claimed_units`, point
   `IdentityVerifier.describe/1` at unit identity, and grow `unit_id`
   args through the `Units.lead/1` call sites (PickTarget, ChangeTarget,
   decision card).
4. **Syncer seam on the DownloadClient behaviour.** Incremental sync is
   qBittorrent-shaped outside the behaviour (`rid`, `torrents` map in
   QueueMonitor state). Add a sync driver callback so QueueMonitor is
   driver-agnostic. Prerequisite for the
   [usenet campaign](usenet-download-client.md).
5. **Move SearchSession to the web layer.** It's transient UI workflow
   state (query, selections, grab feedback) living in the Search
   context, re-exported by ~13 pure-delegation clauses on the
   Acquisition facade (`acquisition.ex:209-285`). Relocate beside
   AcquisitionLive; Search keeps only pure operations.
6. **Cell vocabulary alignment + gaps slot.** Plan-board cells and
   pursuit-card segments share shape grammar but diverge on palette
   (UIDR-014 promises "one language"); align the visual mapping at the
   approve→pursuit carry-over moment. Add the disabled "track these
   later" slot on the gaps row (wiring stays with media-search Phase 4).
7. **Small UX polish.** Empty-state CTA pointing at the omnibox;
   pursuit-modal `not_found` story.

## Decisions made

* `2026-06-10` — Campaign created from the downloads-system audit
  (session artifact; findings summarized in Goal).
* `2026-06-10` — Item 4 lands here, not in the usenet campaign: the
  seam refactor is torrent-only-verifiable today and de-risks that
  campaign's Phase 1.
* `2026-06-10` — Item 6 ships only the *disabled* gaps slot; the
  release-tracking handoff wiring remains media-search Phase 4 scope.

## Next steps

Execution order chosen to land small/mechanical items first and the
high-blast-radius identity work with a design pass:

1. Item 1 — discard guard (test-first: LV test that discard requires
   confirm).
2. Item 5 — SearchSession relocation (mechanical, self-contained,
   shrinks the facade).
3. Item 4 — syncer seam (behaviour callback + QueueMonitor
   driver-state opacity; verify with existing qBit stub tests).
4. Item 3 — ADR-055 retirement (migration first, idempotent backfill
   per the safe-migration house rule; then the code deletions).
5. Item 2 — identity unification (design pass first; biggest blast
   radius, land in reviewable slices).
6. Items 6–7 — UI alignment + polish.

## Completion criteria

* Plan discard cannot fire from a single click.
* One module owns identity-strategy precedence; QueueMatcher /
  DownloadIdentity / LibraryReconciler consume it rather than
  re-implementing strategies; identity envelope (hash + content_path)
  is captured atomically.
* No code path reads pursuit-level season/episode where a unit exists;
  `CommitPlan` overlap check has a single schema.
* `DownloadClient` behaviour carries the sync contract; QueueMonitor
  holds no qBittorrent-native state.
* `MediaCentaur.Search` no longer exports SearchSession; the
  Acquisition facade's delegation block is gone.
* Plan board and pursuit segments share one documented cell mapping;
  gaps row shows the disabled track-later slot.
* `mix precommit` green at every commit; every behavior change
  test-first.

## Pointers

* Audit findings: this session's report (2026-06-10); fix-history
  forensics identified identity matching as rank-1 rework source.
* [ADR-055](../decisions/architecture/2026-06-09-055-composite-pursuits.md)
  — composite pursuits (the model items 2–3 finish landing).
* [media-search-tmdb-acquisition.md](media-search-tmdb-acquisition.md)
  — sibling campaign; Phase 4 owns the gaps-handoff wiring.
* [usenet-download-client.md](usenet-download-client.md) — consumer of
  item 4's seam.
* Identity mechanisms today: `acquisition/queue_matcher.ex`,
  `pursuits/download_identity.ex`, `pursuits/library_reconciler.ex`,
  `pursuits/identity_verifier.ex`, `acquisition/info_hash.ex`.
