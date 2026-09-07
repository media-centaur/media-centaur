---
status: in-progress
started: 2026-09-07
last_updated: 2026-09-07
---
# Watchlist and release tracking

## Goal

Collapse four representations of one idea — a watchlist entry, a tracked title,
`Item.status`, `Item.auto_grab_mode` — into one authored intent and one derived
machine, and the three title modals that render them into two. A person should
declare "I want to watch this" once, arm it once, and see the same control
wherever the title appears.

Phases 0–5 did that and shipped. A sixth phase — a title resolving to *one*
surface — was opened and then **abandoned**; the brief survives below as a record
of a known, accepted defect.

## Status

**Phases 0–5 shipped in v1.16.0 (2026-09-07).** The model is one authored intent
and one derived machine: `tracking_mode` replaces `status` + `auto_grab_mode`,
`source` is gone, existence is reconciled from reasons, and
`ReleaseTracking.arm/2` is the person's act. Three title modals became two. The
`:watching` / `:ignored` vocabulary is out of the app, the stragglers line is
retired, and the guide and wiki teach the new model.

| Phase | | |
|---|---|---|
| 0 | records and vocabulary | [ADR-065], [UIDR-035], five glossary terms |
| 1 | the model | `6740acb6` |
| 2 | one title surface for everything without files | `206eca0f` |
| 3 | library detail mounts the same components; the bell goes | `71a52275` |
| 4 | Coming up is the schedule; stragglers retire | `7ff2e95f` |
| 5 | guide and wiki | `07b97886`, wiki `5d05c0e` |

**Migrated on this machine 2026-09-07** against the real library DB
(`~/.local/share/media-centaur/media-centaur.db`, which the `media-centaur-dev`
daily driver uses): Fae backup first (`media-center-db`, success), service
stopped, `ecto.migrate` + `ecto.migrate_data`, service restarted and serving.
Result: 13 tracked titles (12 `global`, 1 `watch`), 9 watchlist rows, and **0
active tracked titles with no reason** — the invariant holds on real data.

**Open: the owner's check of the shipped surfaces.** That is the only thing left.
Phase 6 was abandoned on 2026-09-07 before it was planned — see the brief below,
which stays as the record of a defect we are choosing to live with.

[ADR-065]: ../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md
[UIDR-035]: ../decisions/user-interface/2026-09-07-035-two-title-surfaces.md

## Decisions made

* `2026-09-07` — A watchlist entry is authored intent; a tracked title is
  derived machinery. A tracked title exists while a **tracking reason** holds:
  the library owns an active container, or a person armed the watchlist entry.
  `Item.source` is removed — it is write-once first-cause metadata, wrong for
  any title with both causes.
* `2026-09-07` — One **tracking mode** (None / Watch / Ask / Grab / Global)
  replaces `Item.status` and `Item.auto_grab_mode`. Set only by a person or
  seeded once at creation; **never raised by the system**. `Global` follows the
  ambient setting only while the mode has never been set explicitly.
* `2026-09-07` — Auto-grab is opt-in. A watchlist entry seeds **Watch**, not the
  global default: adding something to your list must never start a download.
  Library auto-track seeds **Global**, preserving today's behaviour.
* `2026-09-07` — Adding to the watchlist is free (no tracked title). Arming is a
  second act.
* `2026-09-07` — **The two reasons are not equivalent.** The library reason is a
  *default* and evaporates when the library stops owning the title; the
  watchlist reason is an *act* and outlives it. **Arming is a watchlist act** —
  choosing to track a title puts it on the watchlist, whatever surface the
  control was operated from. So: delete a series from the library and tracking
  continues iff a person had armed it; it stops if the global default was the
  only thing tracking it. Today's `detach_library_containers/1` keeps *every*
  item and so grabs forever regardless — a behaviour fix, not just a refactor.
* `2026-09-07` — **An explicit disarm is durable.** A row at mode None survives
  with no reason held — inert, invisible, no refresh, no wants — so re-acquiring
  or re-listing a title can never silently re-arm what a person turned off.
* `2026-09-07` — Invariant: **every *active* tracked title (mode above None) is
  either owned or on the watchlist.** Inert None rows exempt. This is what lets
  the straggler concept retire.
* `2026-09-07` — Three title modals become two, split by "does this have files"
  rather than by which table it came from. The release timeline and the
  tracking-mode control become shared components mounted by both.
* `2026-09-07` — `MediaCentaur.Discovery` / `MediaCentaur.Pipeline.Discovery`
  is **not** a collision — two contexts may use one word for different things.
* `2026-09-07` — UI phases are implemented with the Fable model; context,
  schema and migration phases stay on Opus.
* `2026-09-07` — Phase 0 landed: ADR-065, UIDR-035, five glossary terms.
* `2026-09-07` — Phase 1 landed and was migrated on this machine; the invariant
  verified on real data (0 orphans). Inert `:none` rows are never pruned —
  pruning one would re-arm the title.
* `2026-09-07` — Phase 2 landed. **Watchlist rows show the tracking mode as a
  quiet marker and never set it.** UIDR-035 says a row shows its mode; a
  five-option control repeated down a list reads as a chip palette and breaks
  `title_row.ex`'s own contract ("state is shown, never acted on here: every
  verb lives in the modal"). Arming stays one click away on the row's modal, so
  the watchlist is still the arming surface. Reverted after seeing it rendered.
* `2026-09-07` — `arm/2` takes an explicit `tracking_mode`, and re-arming a
  disarmed title raises it to the seed. Not the system raising a mode: every
  caller is a person's click. `disarm/1` / `arm/2` write their
  `:stopped_tracking` / `:began_tracking` audit events so the modal's recent
  activity still records a stop.
* `2026-09-07` — `TitleDetailHost` is the shared host trait for the merged
  modal, and `TitleRef` owns the `?title=` ref spelling now that both Discovery
  and Incoming use it.
* `2026-09-07` — Phase 3 landed: the library detail mounts the same timeline and
  mode control, the bell is gone, and `tracking_status` became `tracking_mode`
  through the view models.
* `2026-09-07` — **Suite flakes here are contention, not regressions.** Two
  agents running the full suite at once race for the test database and produce a
  rotating cast of ~4–5 failures; the committed baseline shows the same rate.
  Verify a change against its own test surface repeated, and run one full
  precommit at a time.

* `2026-09-07` — Shipped as **v1.16.0**. Assets verified, wiki pushed.
* `2026-09-07` — **Phase 6 opened** by the owner: unify the watchlist and
  release-tracking modals. Those two were already one (Phase 2); the surviving
  seam is that an owned title opened from the watchlist gets a stub. Reframed as
  "a title resolves to one surface" and left unplanned by decision — it gets its
  own planning session.
* `2026-09-07` — **Phase 6 abandoned entirely** by the owner, at the start of
  that planning session and before any approach was chosen. The stub an owned
  title opens to, and the `In library` hop that bridges it, are accepted
  behaviour. UIDR-035's two-surface split stands as written, boundary included.
  The brief is kept below so the defect is recorded rather than rediscovered.

## Next steps

1. ~~**Phase 0 — records and vocabulary.**~~ Done 2026-09-07:
   [ADR-065](../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md),
   [UIDR-035](../decisions/user-interface/2026-09-07-035-two-title-surfaces.md),
   and five glossary terms (*watchlist entry*, *tracked title*, *tracking
   reason*, *tracking mode*, *arming* — none existed, which was the diagnosis in
   miniature). *Straggler* marked retired-pending-Phase-4.
2. ~~**Phase 1 — the model.**~~ Done 2026-09-07. `tracking_mode` replaces `status` +
   `auto_grab_mode`; `source` dropped; existence reconciled from reasons;
   `ReleaseTracking.WatchlistListener` mirroring `LibraryListener`;
   `TrackingStarted` broadcast moves to Discovery. `detach_library_containers/1`
   becomes a reconcile rather than a detach. Four paired migrations per the
   spec, including backfilling watchlist entries for `source: :manual` items —
   without it the invariant fails on first reconcile and manually tracked titles
   are stranded. Existing controls keep working: the bell writes `tracking_mode`
   via `EntityModal.toggled_tracking_mode/1`. No visible change.

   Landed beyond the plan: `Item.grab_mode/2` is now the single resolver of
   mode → grab decision (it had been copied three ways, in `AutoGrabSettings`,
   `Present` and `UpcomingFeed`, each reaching into `item.auto_grab_mode`
   directly — the actual boundary violation under the duplication);
   `list_watching_items/0` → `list_active_items/0`; a
   `DropOrphanedTrackedTitles` data migration sweeps rows the old
   keep-everything `detach` left behind. Inert `:none` rows are deliberately
   never pruned — pruning one re-arms the title.
3. ~~**Phase 2 — merge the no-files surfaces**~~ Done 2026-09-07 (`206eca0f`). `ReleaseTracking.TitleModal`
   absorbed into `Discovery.TitleDetailModal`; shared release-timeline and
   tracking-mode components extracted; watchlist rows gain the mode control;
   the `Track` verb retired in favour of add + arm. Ships a working product;
   the bell remains a knowingly-stale second representation until Phase 3 — an
   explicit scheduled convergence, not a silent one.
4. ~~**Phase 3 — library detail**~~ Done 2026-09-07 (`71a52275`). Mounts the same two shared components;
   the bell is removed. The convergence point for Phase 2's debt.
5. ~~**Phase 4 — retire the stragglers line**~~ Done 2026-09-07 (`7ff2e95f`). `UpcomingFeed.Straggler`
   removed, Coming up reduced to the schedule, UIDR-017 amended.
6. ~~**Phase 5 — docs.**~~ Done 2026-09-07 (`07b97886`; wiki `5d05c0e`). `priv/guide/release-tracking-and-upcoming.md` rewritten
   around the new vocabulary (it currently teaches Track-vs-watchlist), a guide
   page for the watchlist (there is none today), wiki sync, glossary elevation.
7. ~~**Phase 6 — a title resolves to one surface.**~~ **Abandoned 2026-09-07**,
   unplanned and unbuilt. Nothing here is outstanding. The brief below is a
   record, not a queue.

## Phase 6 — a title resolves to one surface (abandoned)

**Abandoned 2026-09-07, before planning. Do not start writing code from this
section.** It is kept because the defect it describes is real, verified live, and
now accepted — a future reader should find it recorded here rather than discover
it again from scratch. Reopening it is a fresh decision, not a resumption.

### The defect

UIDR-035 split the title surfaces by whether the title has files. That is right
at the centre and wrong at the boundary. Open a title you *own* from the
watchlist and you get a stub: hero, "Tracking since Aug 2026", TMDB metadata and
cast, and an `In library →` button. No episodes, no release timeline, no
tracking control. It knows you own it and knows it is tracked, and shows you
neither. Verified live on `?title=tv_series-3219` (a series with ten seasons in
the library) after v1.16.0.

The `In library` primary action exists only to bridge that gap.

### The framing

The owner's words were "unify the watchlist modal and the release tracking
modal". Those two were already unified in Phase 2 — `release_tracking/title_modal.ex`
is deleted and both hosts open `Discovery.TitleDetailModal` through
`TitleDetailHost`. So **frame the phase as "a title resolves to one surface",
not "unify the modals"**: that names the actual defect and rules out the wrong
fix.

### The wrong fix, and why

Merging `DetailPanel` into the title modal. `DetailPanel` is 751 lines and
`EntityModal` 1809; the title surface is 386 + 410. The result is ~3,300 lines
of one component that is mostly `if has_files`, in the most load-bearing UI in
the app — exactly what UIDR-035 avoided. And there is little duplication left to
collapse: the hero, release timeline and tracking-mode control are *already*
shared components after Phase 3. That merge would be speculative abstraction,
not de-duplication.

### The likely fix

The real defect is **addressing**, not components. Two identity spaces:

| Surface | URL | Identity |
|---|---|---|
| Library detail | `?selected=<entity uuid>` | a Library entity |
| Title detail | `?title=<tmdb ref>` | `{tmdb_id, media_type}` |

An owned title has both, and the app currently makes the person traverse from
one to the other by hand. So: **opening a title that has files resolves to the
library surface.** `TitleDetailHost` already resolves the ref and already knows
the library owner id — it uses that to render a link where it could route. One
click from the watchlist, right destination, no stub, no hop.

Falls out of it: the `In library` primary action disappears, and
`TitleDetail.primary` loses a variant.

### The counter-argument, for the planning session to weigh

The coherent extreme is one surface for every title, with file-bound sections
appearing when there are files — "one representation per idea" taken all the
way, and a title would never change surface as it moves through the library.
Defensible. The case against: the two surfaces answer different questions (*what
do I have and how do I play it* vs *do I want this and what is coming*), so the
merge buys coherence in the model at the cost of coherence in the code.

### Open questions for planning

* What does a bookmark to `?title=<ref>` do once the title is owned — redirect,
  or render the library surface at that URL? A saved link should keep working.
* Does the Discovery watchlist row navigate to `/library`, or open the library
  detail in place on `/discovery`? The second keeps the person on their list.
* Where does provenance go (who recommended it, the note) once an owned title
  opens in the library — the library surface has no place for it today.

## Remaining, by destination

Per the closure convention, every leftover is bucketed rather than left implicit:

* **Ship** — done. v1.16.0, 2026-09-07: tag pushed, workflow green, both
  tarballs and `SHA256SUMS` verified; wiki pushed (`5d05c0e`). The CHANGELOG
  entry states in plain words that a series deleted from the library stops being
  tracked unless it was armed — a live behaviour change on every existing
  install — under `### Upgrade note`.
* **Verify (closes the campaign)** — the owner uses the new watchlist, merged
  title surface and library detail, on the desktop and on the TV with a
  remote/gamepad. Nav zones were added for both
  (`title_detail_tracking`, `detail_tracking`) but only mouse-verified, per
  [[feedback-no-nav-work-during-volatile-design]]; run `mc-nav-trace` if a key
  path misbehaves.
* **Abandoned** — Phase 6. Not deferred: no one is expected to pick it up.
* **Defer** — the two follow-ups below (both lost their Phase 6 home and are now
  standalone, whenever that code is next opened), and marketing screenshots
  (stale by standing preference, not regenerated).

## Follow-ups found while building

* **A past-dated release reads as two contradictory things on one surface.**
  `next_event/2` skips past-dated releases, so the featured slot says "Nothing
  scheduled" while a row below it shows that release — and `relative_day/2`
  prints "Today" for any past date, so the row claims today. Pre-existing
  semantics surfaced by the merged modal, not introduced by it. Shipped in
  v1.16.0 unfixed, and still unfixed now that Phase 6 is abandoned — a standalone
  fix in `next_event/2` and `relative_day/2`, not a component patch. Do not paper
  over it in the timeline component. The shelf half is fixed (2026-09-07): an
  owned series in Global mode arms every episode it is missing, which put a
  1998 episode on Coming up as "Tonight · Will grab"; `UpcomingFeed` now keeps
  a past armed or landed release for a week only, and an older one is a
  library gap. The timeline half above is still open.
* **The timeline half-duplicates the seasons list on the library panel.** A
  series' announced episodes already appear as Upcoming rows inside its seasons;
  the timeline repeats their codes, but carries the per-release grab status and
  the pursuit deep-link, which the seasons do not. Mounted whole. If it reads as
  noise in use, `release_timeline/1` can take a `list` attr and show the
  featured next release alone.

## Completion criteria

* `release_tracking_items` has one `tracking_mode` and no `status` or `source`.
* A tracked title's existence is reconciled from reasons; nothing writes it directly.
* The invariant holds on real data: no *active* tracked title that is neither owned nor listed.
* Deleting a series from the library stops tracking it unless a person armed it; an explicit disarm survives every list change.
* Two title surfaces, both mounting the same release-timeline and tracking-mode components.
* No bell, no `Track` verb, no straggler line.
* Guide and wiki describe one intent and one machine; glossary carries all four terms.
* `mix precommit` green; migrations idempotent and CHANGELOG-mentioned.
* The owner has used the shipped surfaces on the desktop and on the TV.

## Pointers

* Design: `docs/superpowers/specs/2026-09-07-watchlist-release-tracking-reconciliation-design.md`
* Prior watchlist design: `docs/superpowers/specs/2026-08-18-watchlist-foundation-design.md`
* [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md) — wants
* [UIDR-017](../decisions/user-interface/2026-08-03-017-coming-up-title-depth.md) — Coming Up title depth; straggler half superseded here
* Key modules: `lib/media_centaur/discovery.ex`, `lib/media_centaur/release_tracking.ex`,
  `lib/media_centaur/release_tracking/{item,auto_track,library_listener,wants}.ex`,
  `lib/media_centaur_web/components/{discovery/title_detail_modal,release_tracking/title_modal}.ex`,
  `lib/media_centaur_web/live/entity_modal.ex`
