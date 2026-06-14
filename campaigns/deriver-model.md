---
status: in-progress
started: 2026-06-14
last_updated: 2026-06-14
---
# Deriver model: separate recomputable derived data from frozen identity

## Goal

A file's record carries two kinds of fact: **identity** (which show/movie it
is, its TMDB link — expensive to compute, stable once known) and **derived**
data (the display name, season/episode read straight off the filename — cheap,
and wrong whenever a parsing rule has a bug). Today the pipeline freezes both at
import behind a single boolean (`Discovery.already_linked?/1`): once a file is
linked, every later scan skips it, so a parser fix never reaches records already
on disk. The Frieren "Web Previews" bug (28 blank extra names; fixed in
v0.95.2) needed a hand-written backfill purely because of this freeze.

This campaign makes derived data **recomputable**: a parser improvement heals
existing records on the next sweep, with no network calls and no hand-written
migrations — while leaving the expensive identity work frozen exactly as it is.

## Status

Phases 0–2 complete (unpushed). The campaign's *core intent is delivered*:
derived names heal with no hand-written backfill, no network, and can never be
blank. **Phase 3 is a deliberate stop** — it is the live-ingest-risky, entangled
part (see "Phase 3 is a decision" below). The 28 Frieren extras heal
automatically the next time prod boots the new release (Phase 2), or instantly
via the Settings button (Phase 1).

What shipped:
- Phase 1 — re-derive sweep (`Maintenance.rederive_extra_names/0` →
  `Pipeline.ExtraRederive`), writer invariant (`Library.update_extra_name/2`),
  Settings → Library-maintenance button.
- Phase 2 — boot auto-heal (`Maintenance.heal_extra_names_on_boot/1`, wired in
  `Application.init_services`): the network-free sweep runs in the background on
  every non-test boot, so a parser fix in an update reaches existing records on
  the next restart with zero operator action.

### Why Phase 2 dropped the `deriver_version` column

Implementation confirmed ADR-057's framing: the per-extra version stamp exists
*only* to let the **scan path** skip re-parsing unchanged files — i.e. it is an
optimization **for** the Phase 3 Discovery reconciliation. Building it now, with
no consumer, is speculative scaffolding (YAGNI). Boot auto-heal delivers
"self-healing after an update" without it: re-parsing all extras on boot is
network-free, bounded, and milliseconds. The column lands in Phase 3 *with* its
consumer, or never.

### Phase 3 is a decision

The original Phase 2/3 "turn `Discovery`'s boolean into a 4-way reconciliation
decision + fold in relink + resolve the deferred `ExtraFile` writer" is one
entangled change to the **live ingestion path**, and it overlaps two other
tracked initiatives (the `ExtraFile` "Task G" deferral; the relink-on-move
planning). It carries real regression risk and a design fork (how to unify
file-link tracking across `WatchedFile`/`ExtraFile`). Per the "stop for genuine
decisions" rule, this is surfaced to the user rather than driven autonomously —
see Next steps.

## Decisions made

* `2026-06-14` — Derived data is recomputable, never frozen; correctness is
  version-free (re-parse + compare), the version stamp is only a scan-path
  optimization. ([ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md))
* `2026-06-14` — Phase 1 sweep is enabled even at zero blank names (idempotent +
  network-free), so an app update's naming improvements can be applied on demand.
* `2026-06-14` — `Extra.name` re-derive only runs when the path still parses as an
  extra (`type: :extra`); a `content_url` that now parses as a movie is left
  untouched, protecting collection-backfilled extras from a wrong name.
* `2026-06-14` — Phase 2 ships boot auto-heal instead of the `deriver_version`
  column + Discovery rewrite. The column is an optimization *for* the on-scan
  reconciliation (Phase 3) and is YAGNI without it; boot auto-heal delivers
  self-healing-after-update at near-zero risk. (commit pending)

## Design summary

Three principles, delivered as three independently-shippable slices:

1. **Derived data is recomputable; identity is not.** The only filename-derived
   *display* field in the library today is `Extra.name`. Everything else that
   looks derived is either already gone (`WatchedFile.parsed_*` were stripped in
   Library Schema v2) or actually identity (`Episode.name` comes from TMDB).
   So v1's concrete surface is exactly one field — small and well-bounded —
   while the *mechanism* is built to generalise.

2. **Correctness is version-free.** A re-derive pass re-parses each extra's
   `content_url` and updates `name` only where the freshly-derived value differs
   and is non-empty. It is pure, idempotent, network-free, and needs no schema
   change. The `deriver_version` stamp (Phase 2) is purely an *optimization* so
   the normal scan path can decide "skip vs re-derive" without re-parsing —
   it is never a correctness dependency.

3. **The skip becomes a reconciliation decision.** `already_linked?` (one bool)
   becomes a four-way decision per file — `fresh` (full intake, the only path
   that hits TMDB), `relink` (moved/renamed — already partly built), `refresh`
   (rule stale → re-derive, no network), `up_to_date` (leave it). Two of these
   don't exist today.

### Why no clobbering risk (today)
There is **no UI, changeset, or DB path** for a user to rename an Extra or
Episode (verified: `Extra`/`Episode` expose only `create_changeset/1`; no web
form binds these). So a re-derive sweep cannot stomp a human edit. We design the
mechanism so a future "user-edited" guard slots in cleanly, but we **do not
build that guard now** (YAGNI until an edit affordance exists).

## Findings (code map — resume context)

- **Derived write path (single seam):** `Parser.parse/2` →
  `Stages.FetchMetadata.build_extra/1` (`fetch_metadata.ex:284`, maps
  `parsed.title` → `name`) → `Inbound.create_extra/3` (`inbound.ex:707`) →
  `Library.find_or_create_extra_by_owner/1` → `Extra.create_changeset/1` →
  `Repo.insert` (`library.ex:1653`). Name is set once; **no update path exists**.
- **Skip gate:** `Discovery.already_linked?/1` (`discovery.ex:220–231`) — exists
  in `WatchedFile` **or** `ExtraFile` by `file_path`. Called from
  `Discovery.process/1` (`discovery.ex:137`), Broadway `handle_message`.
- **Scan triggers / sweep host candidates:** Watcher live detection
  (`watcher.ex:521`), startup `:reconcile` (`producer.ex:49`),
  `Watcher.Supervisor.rescan_unlinked/0` (`supervisor.ex:355` — re-emits
  `FilePresence` rows absent from both link tables), Console "Rescan Library"
  button (`console_live/shared.ex`).
- **Maintenance pattern to mirror:** `Maintenance.repair_missing_images/0` +
  `repair_missing_images_async/1` (`reply_to` message) + `missing_images_summary/0`
  for the button/count (`maintenance.ex:101, 472, 504`). The re-derive sweep
  copies this shape exactly.
- **Relink already partly built:** `Library.relink_moved_files/3`
  (`library.ex:739`) with `MoveMatcher` + `FilePresence.list_relink_candidates/1`,
  run from batch `scan_directory/2` (`watcher.ex:458`). Phase 3 *formalises* this
  into the reconciliation decision rather than building it fresh.
- **Latent inconsistency (Phase 3 dependency):** the `ExtraFile` writer is
  **deferred** — extras carry `content_url` directly, yet `already_linked?`
  checks `ExtraFile`. Extras may therefore not be reliably "linked" by the gate's
  own test. Reconciliation needs one authoritative "is this extra-file linked?"
  answer; resolving the ExtraFile gap is a Phase 3 precondition.

## Next steps

### Phase 0 — Decision record ✅ done
1. ✅ [ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md).

### Phase 1 — Re-derive sweep ✅ done
2. ✅ `Pipeline.ExtraRederive.rederive_all/0` (+ `Maintenance.rederive_extra_names[/_async]`).
3. ✅ `Extra.update_name_changeset/2` + `Library.update_extra_name/2` (non-empty invariant).
4. ✅ Settings → Library-maintenance "Re-derive bonus-feature names" button + blank count.
5. ◻ Acceptance: prod sweep heals the 28 Frieren extras — happens on the next prod
   boot (Phase 2 auto-heal) once the campaign ships; no manual backfill needed.

### Phase 2 — Boot auto-heal ✅ done (reframed; see "Why Phase 2 dropped the column")
6. ✅ `Maintenance.heal_extra_names_on_boot/1` wired into `Application.init_services`
   (async, non-test). Self-healing-after-update with no schema change, no Discovery
   surgery, no `ExtraFile` dependency.

### Phase 3 — DECISION REQUIRED (deferred, not abandoned)
The on-scan reconciliation is the entangled, live-ingest-risky remainder. Options
to put to the user:
- **(a) Stop here** — Phases 0–2 satisfy ADR-057's intent; close the campaign and
  let the deferred `ExtraFile` work + relink-on-move campaign carry the rest.
- **(b) Do Phase 3 as its own reviewed effort** — add `deriver_version`, turn
  `Discovery.process/1` into the 4-way decision (`fresh`/`relink`/`refresh`/
  `up_to_date`), resolve the `ExtraFile` "Task G" deferral so "linked" is
  authoritative, fold in `relink_moved_files`. Bundle with the relink-on-move
  campaign; verify against live ingestion, not just DataCase.
- Open sub-question if (b): version-bump discipline — manual `Parser.version/0`
  constant guarded by a test, vs. a compile-time hash of the naming rules.

### Phase 4 — Generalise (only if earned)
7. Apply the identity-vs-derived discipline to any other silently-frozen derived
   field. Do not pre-build; let real need pull it.

## Completion criteria

- ✅ A parser/naming rule fix reaches existing records with **no hand-written
  backfill** — via the sweep button (Phase 1) and automatically on boot (Phase 2).
- ✅ Re-derivation performs **zero TMDB/network calls** and never duplicates or
  re-links records (idempotent; regression-tested).
- ✅ An `Extra` can never be persisted with a blank name (writer-level invariant).
- ◻ `Discovery` exposes a typed reconciliation decision, not a boolean; `relink`
  and `refresh` are real branches — **Phase 3, pending the (a)/(b) decision**.
- ✅ ADR recorded. Campaign file removed on completion (after the Phase 3 decision).

## Pointers

- Origin: Frieren "Web Previews" parser bug, fixed in **v0.95.2**
  (`fix(parser): WEB source token no longer eats curated extra titles`).
- Plain-language design report: `~/.agent/diagrams/deriver-design.html`.
- Sibling/overlap: relink-on-move planning (memory `project-relink-on-move`) —
  Phase 3 is its natural home.
- Key seams: `lib/media_centaur/parser.ex`,
  `lib/media_centaur/pipeline/discovery.ex`,
  `lib/media_centaur/pipeline/stages/fetch_metadata.ex`,
  `lib/media_centaur/maintenance.ex`, `lib/media_centaur/library.ex`.
