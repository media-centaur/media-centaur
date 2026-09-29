---
status: in-progress
started: 2026-09-29
last_updated: 2026-09-29
---
# Review coherence: identity in Review, position in Episode mapping

## Glossary

* **Match.** What a file is: a TMDB type and id (its **identity**), and
  for a TV episode also its **position** — a season and episode number
  on TMDB's episode list.
* **Claim.** What a file's name says about itself: parsed title, year,
  season, episode, episode title. Evidence, never a decision.
* **Identity queue.** `Review.PendingFile`, the Review tab "Identity":
  files whose identity needs a person.
* **Position queue.** `AwaitingFile` in the episode-mapping context (the
  tab "Episode mapping"): files of a known series whose position needs a
  person.
* **Link / link outcome.** As in `Library.Inbound`: the `WatchedFile` or
  `ExtraFile` that puts a file in the library, and the report of whether
  one was made.
* **Open item.** A queue row whose file is not linked and not dismissed.
* **Settled file.** Linked, dismissed in the identity queue, or in the
  position queue. Discovery does not search a settled file again.
* **Startup recovery.** The boot pass (ADR-023) that settles both queues
  against the library and re-sends stranded files.

## Goal

The audit of 2026-09-29 found that the two halves of one match are
decided in two queues that have drifted apart, and that several failures
strand or duplicate items. The worst: a file parked in the position
queue returns to the identity queue on every restart — the symptom the
v1.47.0 report was about. This campaign makes each half of the match
decided in exactly one place, makes queue membership follow the library,
and fixes every defect the audit found.

## Status

Planning done; Layer 1 next.

## Design

1. **Position is decided in one place.** Import resolves a TV file's
   position when its claim names a season TMDB lists and an episode
   number. Otherwise — no season, no episode, or an unlisted season — the
   file goes to the position queue. An episode number beyond TMDB's list
   in a listed season still links (the list lags an airing show). Review
   never asks for a position: its episode picker, `EpisodeChoice`,
   `episode_choices/1`, `set_episode/3`, `needs_episode?/1`,
   `chooses_episode?/1` and the `:no_episode` reason are removed.
   `EpisodeChoice.preselect/2` becomes a year model in the episode-mapping
   engine, reading a new `claimed_year` and the spine's air dates.
2. **Claims are named as claims.** `PendingFile.season_number` /
   `episode_number` become `parsed_season` / `parsed_episode`: with
   position out of Review they only ever hold the claim.
3. **Membership follows the library.** Both queues list only open items,
   read against `Library.Files.linked_paths_subquery/0`. A link outcome
   deletes the row and notifies; startup recovery deletes what a dropped
   message left. The position queue's `:resolved` status goes: a
   confirmed file is linked, and its row is deleted.
4. **Approval is one synchronous, validated decision.** A file needs an
   identity to be approved; a group is approvable when its pending files
   share one identity. No task, no `GroupApproved`/`GroupError`, no
   `processing` state.
5. **A not-linked outcome carries the identity** it was imported under, so
   an item created for an automatic match keeps the match and "approve it
   again" is available.
6. **Settled includes the position queue.** Discovery skips files there;
   the position queue drops rows on `{:files_removed, paths}` like the
   identity queue.
7. **Dismissals can be undone.** Each queue page lists dismissed files
   with Restore.
8. **Handlers do no media I/O** (ADR-044): Review's delete and delete-target
   resolution, and the episode-mapping page's spine assembly, run async.

## Layers

Each layer leaves the product working and is committed on its own.

1. **Correctness.** Discovery settled check + position-queue removal
   (A1); validated synchronous approval (A2, A3, B6, D12); identity on
   not-linked outcomes and a generic ingest-without-link reason (A4, B5);
   per-file group state, one-unit header chips, startup settle broadcast
   (B7, B8, B9); stale event docs (D13).
2. **Rename.** `Reconciliation` → `EpisodeMapping` (ADR-075), `/reconcile`
   → `/episode-mapping`; startup recovery names
   (`Watcher.Rescan.recover/0`, `Review.settle_with_library/0`).
3. **Position converges.** Design 1 and 2.
4. **Membership follows the library.** Design 3.
5. **Dismissed lists.** Design 7.
6. **Async I/O.** Design 8 (C10, C11).
7. **Docs and wiki.** `docs/pipeline.md`, `docs/library.md`,
   `docs/GLOSSARY.md`, the wiki's Review pages; retire this file.

## Decisions made

* `2026-09-29` — Scope: every audit fix plus option 2 (position converges
  on the episode-mapping context), the claim column rename and derived
  membership. Owner request.
* `2026-09-29` — An episode number beyond TMDB's list in a listed season
  keeps linking; only no season, no episode or an unlisted season divert.
  Owner ruling.
* `2026-09-29` — A name conflict matters only within one bounded context
  (`CLAUDE.md`, commit `8f3e590e`). `Review` / `PendingFile` keep their
  names.
* `2026-09-29` — Bounded contexts are named for their capability
  ([ADR-075](../decisions/architecture/2026-09-29-075-bounded-context-naming.md));
  `Reconciliation` becomes `EpisodeMapping`.
* `2026-09-29` — The boot pass is "startup recovery".
* `2026-09-29` — Dismissals get a Dismissed list with Restore on both
  queue pages. Owner ruling.
* `2026-09-29` — This campaign supersedes `review-closes-on-link.md`'s
  Layer 2 (the episode picker in Review). That campaign's remaining step,
  the reporter's check of the yearly special, moves here.

## Next steps

1. Layer 1.

## Completion criteria

* A file is asked for its identity only in Review and for its position
  only in Episode mapping.
* A parked file never reappears in Review, including after a restart.
* No approval can publish a match without an identity; approval has no
  background task.
* Both queues list only open items, and a dismissal can be restored.
* No Review or Episode mapping handler or render touches a media path or
  TMDB synchronously.
* The reported yearly special is offered S01E22 in Episode mapping on the
  reporter's install and appears in the library after confirming.
* Docs and wiki describe the shipped behaviour.

## Pointers

* Audit (2026-09-29 session): findings A1–E.
* `lib/media_centaur/review.ex`, `review/*`, `reconciliation.ex`,
  `reconciliation/*`, `pipeline/stages/fetch_metadata.ex`,
  `pipeline/discovery.ex`, `library/inbound.ex`,
  `media_centaur_web/live/review_live.ex`, `reconcile_live.ex`.
