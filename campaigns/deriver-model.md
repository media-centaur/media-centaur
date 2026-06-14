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

Phases 0–1 complete (unpushed). ADR-057 recorded; the re-derive sweep
(`Maintenance.rederive_extra_names/0` → `Pipeline.ExtraRederive`) + writer
invariant (`Library.update_extra_name/2`) + a Settings → Library maintenance
button all ship, fully tested. Phase 2 (version stamp + reconciliation) next.
The 28 Frieren extras are still blank on prod — they heal once prod runs the new
release and the sweep button is clicked (or the on-scan path from Phase 2 lands).

## Decisions made

* `2026-06-14` — Derived data is recomputable, never frozen; correctness is
  version-free (re-parse + compare), the version stamp is only a scan-path
  optimization. ([ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md))
* `2026-06-14` — Phase 1 sweep is enabled even at zero blank names (idempotent +
  network-free), so an app update's naming improvements can be applied on demand.
* `2026-06-14` — `Extra.name` re-derive only runs when the path still parses as an
  extra (`type: :extra`); a `content_url` that now parses as a movie is left
  untouched, protecting collection-backfilled extras from a wrong name.

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

### Phase 0 — Decision record
1. Write an ADR: *Derived data must be recomputable, never frozen* — the
   identity-vs-derived split and the recompute-on-improvement principle. The
   campaign enacts it. (Repository-wide principle → ADR, per ADR-042.)

### Phase 1 — Re-derive sweep (Slice A · smallest, zero-risk, no schema change)
2. `Maintenance.redrive_extra_names/0` (+ `_async/1` + a summary fn): stream all
   `Extra`s, re-parse `content_url` via `Parser.parse/2`, update `name` where the
   derived value differs and is non-empty. Test-first (DataCase): blank-name
   extra → sweep fills it; correct-name extra → untouched; user-style mismatch
   → updated to the rule's value (documents the no-edit-UI assumption).
3. Add an `Extra.update_name_changeset/2` (the missing update path; validates
   non-empty name — the writer-level invariant from the report).
4. Wire a Console/Settings "Re-derive names" action mirroring image-repair
   (button + count of stale/blank extras). Page smoke + the action's pure logic
   unit-tested.
5. Acceptance: run the sweep against prod → the 28 Frieren extras gain names.
   This *replaces* the manual backfill.

### Phase 2 — Version stamp + on-scan auto-heal (Slice B · the spine)
6. Add `deriver_version` column to `Extra` (paired migration; backfill existing
   rows to a sentinel "pre-v1" so they read as stale once). `Parser.version/0`
   exposes the current rule version.
7. Turn `Discovery.process/1`'s boolean into the four-way reconciliation
   decision; the `refresh` branch re-derives + restamps with no TMDB call.
   Now auto-healing happens on ordinary scans, not just the manual sweep.
8. Decide version-bump discipline: manual `Parser.version/0` constant guarded by
   a test that fails if extra-naming behaviour changes without a bump, **or** a
   compile-time hash of the relevant rules. (Open question — resolve in Phase 2.)

### Phase 3 — Relink unification + ExtraFile cleanup (Slice C · later)
9. Fold the existing `relink_moved_files` into the reconciliation decision as the
   `relink` branch; resolve the deferred-`ExtraFile` inconsistency so "linked"
   has one authoritative answer. Coordinate with / absorb the relink-on-move
   planning work.

### Phase 4 — Generalise (only if earned)
10. Apply the identity-vs-derived discipline to any other silently-frozen derived
    field surfaced by Phases 1–3. Do not pre-build; let real need pull it.

## Completion criteria

- A parser/naming rule fix reaches existing records with **no hand-written
  backfill** — proven by the Frieren extras self-healing via the sweep (Phase 1)
  and via an ordinary scan (Phase 2).
- Re-derivation performs **zero TMDB/network calls** and never duplicates or
  re-links records (idempotent; regression-tested).
- An `Extra` can never be persisted with a blank name (writer-level invariant).
- `Discovery` exposes a typed reconciliation decision, not a boolean; `relink`
  and `refresh` are real branches (Phases 2–3).
- ADR recorded; this campaign file removed on completion (git is the archive).

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
