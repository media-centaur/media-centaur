---
status: in-progress
started: 2026-09-29
last_updated: 2026-09-29
---
# Review closes on link: a review item stays open until its file is in the library

## Glossary

* **Match.** The decision about what a file is: a TMDB type and id, and for
  a TV episode also a season number and an episode number. The parser
  proposes the season and episode, Discovery proposes the title, and a
  reviewer can confirm or correct any part of it.
* **Link.** The library record that attaches a file to its movie or
  episode: a `WatchedFile` on a `PlayableItem`. A file with no link does
  not appear in the library.
* **Link outcome.** Whether the library attached a file, and if not, why.
* **Review item.** A `Review.PendingFile` row: a file whose match needs a
  person. `:pending` means it awaits a decision; `:approved` means a
  decision was made and the link has not happened yet.

## Goal

A user reported that choosing a match in Review makes the item disappear,
the title never appears in the library, and the item returns to Review
after the next restart. The cause is that Review treats an item as done
before its file is linked, and nothing reports a link that did not happen.
The reported file (`Show.Name.2025.1080p.WEBRip.x264.AAC-[GRP].mp4`, a yearly
special) parses as a movie with no season or episode; TMDB lists it only as
a TV episode (S01E22 of its series). The reviewer picked the series, the
library created it but had no episode to attach the file to, the link was
skipped with an info-level log line, and the review item was deleted
anyway. This campaign makes the library report every link outcome, makes
Review close or reopen an item only on that report, and lets a reviewer
choose the episode for a TV match the filename does not number.

## Status

Layer 1 implemented 2026-09-29 (close on link, reopen with a reason; not
pushed). Layer 2 (choose the episode) next.

## Decisions made

* `2026-09-28` — Scene-release filenames prefixed with the release group
  (`group-show.s01e05` inside `Show.S01...-GROUP`) take their title from the
  folder. (commit `75c80473`)
* `2026-09-28` — A hyphen inside a title is not read as a release group;
  only a whole release name loses its trailing group. (commit `a4c38f33`)
* `2026-09-28` — A file awaiting review that a re-run matches with
  confidence carries its review item's id to Import so the item is
  completed. (commit `bde03a89`) **Superseded by the 2026-09-29 decision to
  close items by link outcome; the `pending_file_id` plumbing it extended
  is removed in Layer 1.**
* `2026-09-29` — The library reports the link outcome by file path on
  `library:file_events`: `{:file_linked, path}` or
  `{:file_not_linked, path, reason}`. Library cannot depend on Review, and
  Review already consumes this topic by path (`Review.FileEventHandler`).
  Chosen over passing the review id into the library (carries an id the
  library has no use for, and misses links that do not come from Review)
  and over Review polling `Library.Files.linked?/1` (timing-dependent, no
  reason).
* `2026-09-29` — Review closes items only on link outcomes. Linked removes
  the item; not linked returns it to `:pending` with the reason in
  `error_message`. An Import failure before the library reports the same
  way. `pending_file_id` is removed from `Pipeline.Payload`, the Import
  producer, every `{:file_matched, ...}` message, Discovery,
  `Import.handle_complete` and `Review.Intake`'s `{:review_completed, id}`
  handler. Three ways of closing an item (by id from Import, by path at
  boot, by path on removal) become one: by path.
* `2026-09-29` — At boot, one reconciliation removes items whose file is
  linked and returns `:approved` items whose file is not linked to
  `:pending` with "import did not finish". Nothing is in flight at boot,
  so an unlinked `:approved` item is stale. It replaces
  `Review.sweep_completed_reviews/0`.
* `2026-09-29` — The match carries season and episode. The
  `{:file_matched, ...}` message includes them (from the parse for
  Discovery, from the review item for Review) and Import uses them instead
  of re-parsing the path for them. A reviewer's episode choice would
  otherwise be ignored.
* `2026-09-29` — Review refuses to approve a TV match without a season and
  episode. The reviewer picks the episode from the series' TMDB episode
  list, one picker per file. When the parsed year matches exactly one
  episode's name or air date, that episode is preselected; it is never
  applied without the reviewer.
* `2026-09-29` — Between approval and link the item stays in Review,
  marked as importing. It disappears on `{:file_linked, _}` and shows the
  reason on `{:file_not_linked, _, _}`. Chosen over removing it at
  approval and bringing it back on failure.
* `2026-09-29` — Built in two layers, each shipped on its own. Layer 1
  makes every failure visible and correct; Layer 2 makes the TV-without-
  episode case resolvable.
* `2026-09-29` — A third link outcome, `{:file_parked, path}`: a file the
  pipeline diverted to the reconciliation queue reaches the library with no
  link by design. The Ingest event carries `parked: true`; Review closes the
  item, because the reconciliation queue owns the file from there.
* `2026-09-29` — A not-linked outcome for a file with no review item queues
  it with the reason. An automatic match that linked nothing (a season-pack
  name, say) used to leave no trace and be re-searched on every restart.
* `2026-09-29` — Approving a returned item clears its reason; approval is
  the retry.
* `2026-09-29` — Two regression tests of `sweep_completed_reviews/0`
  changed meaning on purpose (an approved-unlinked row at boot is reopened,
  a pending-linked row is removed) and one ReviewLive test (an approved
  group stays listed as importing). Each carries a dated comment.

## Next steps

### Layer 1 — close on link, reopen with a reason

Implemented 2026-09-29 (commit pending push). Remaining: push the wiki
(`Review-Queue.md` § After confirming, `Troubleshooting.md`, committed
locally) together with the release that ships it.

### Layer 2 — choose the episode

1. Review: `set_group_match` for a TV match on files without season and
   episode leaves them unset; approval is refused until each such file has
   both.
2. Review: a per-file episode choice stored in the item's
   `season_number` / `episode_number`, sourced from `TMDB.Store.ensure/1`
   and `ensure_season/2` (`Mapper.episode_list/1`).
3. Preselection: a pure function choosing the single episode whose name or
   air-date year equals the parsed year; unit tested.
4. Review page: the episode picker as a kit component with a story.
5. Wiki: the Review page documents choosing an episode.

## Completion criteria

* A review item leaves Review only when its file is linked, on any path
  (review approval, a confident re-run, a rescan).
* Every approval that does not end in a link returns the item to
  `:pending` with a reason the reviewer can read, including after a
  restart.
* No `pending_file_id` remains in the pipeline or Review.
* A TV match for a file without season and episode cannot be approved
  without an episode, and a chosen episode is the one the file is linked
  to.
* The reported file can be matched to S01E22 of its series from Review and
  appears in the library.
* `docs/pipeline.md` and the wiki describe the shipped behaviour.

## Pointers

* `lib/media_centaur/review.ex` — `approve_and_process/1`,
  `set_group_match/2`, `complete_review/1`, `sweep_completed_reviews/0`.
* `lib/media_centaur/review/file_event_handler.ex`,
  `lib/media_centaur/review/intake.ex`.
* `lib/media_centaur/pipeline/import.ex` (`process_payload/1`,
  `handle_complete/1`), `pipeline/import/producer.ex` (`build_payload/1`),
  `pipeline/discovery.ex`, `pipeline/payload.ex`,
  `pipeline/stages/fetch_metadata.ex` (`build_ingest_metadata`).
* `lib/media_centaur/library/inbound.ex` — `link_file`,
  `leaf_container_for`.
* `lib/media_centaur_web/live/review_live.ex` — `approve`, `select_match`,
  the `GroupApproved` handler.
* `docs/pipeline.md`.
