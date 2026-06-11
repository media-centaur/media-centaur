---
status: planning
started: 2026-06-11
last_updated: 2026-06-11
---
# Duplicate episode copies: clarify and resolve the multi-file policy

## Goal

Define and implement the policy for what happens when the library ends
up with **two playable copies of the same unit** (e.g. an episode at
1080p from a season pack *and* at 4K from a single grab). Plan-level
deduplication is solved — the solver never *assigns* overlapping
releases — but physical duplicates still arrive through known paths,
and today the library's behavior is accidental: playback picks an
arbitrary copy, both files persist on disk, and nothing surfaces the
duplication to the user.

## Context (investigated 2026-06-11, v0.88.4)

How overlap is handled today, layer by layer — verified in code:

* **Plan time — duplicates impossible by construction.**
  `Acquisition.Planner` consolidates broad-first; claimed units are
  subtracted from the remaining set, so a full S2 1080p pack claims
  everything and overlapping 4K singles are never assigned
  (`planner.ex` `consolidate/2`). Consolidation outranks per-unit
  quality (campaign `plan-solver-consolidation`, shipped v0.88.2);
  upgrades are offer-as-swap only.
* **Swap time — accounting stays clean, bytes don't.**
  `Plans.choose_release/2` (`plans.ex:318`) reassigns ownership
  per-unit, but swapping one pack-covered episode to a 4K single does
  **not** shrink the pack torrent: its 1080p copy of that episode still
  downloads, lands, and imports. Duplicate data with clean bookkeeping.
* **Landing time — pursuit-level duplicates are protected.**
  `Satisfy` checks units off by the landed target's coverage, and a
  terminal refold closes in-flight sibling targets
  (`pursuits/commands/satisfy.ex`) — a snoozed `PursueTarget` can't
  wake and re-grab.
* **Library — the unresolved layer.** Duplicate files collapse to one
  Episode entity (no UI double), but an episode `has_many` playable
  items and `Library.populate_leaf_content_url/1` takes the **first
  WatchedFile with no ordering** — playback picks an insertion-order
  copy, both files persist on disk, and no surface shows the user that
  duplicates exist or how much disk they cost.

Known ingress paths for physical duplicates:

1. Swap a pack-covered unit to a higher-quality single (the pack still
   contains it).
2. A pack lands carrying episodes beyond what was wanted — the
   2026-06-11 prod verification saw a series pack ingest ~30 unwanted
   episodes, any of which may duplicate existing library copies at a
   different quality.
3. Manual release-mode grabs overlapping existing content.
4. Historical residue from the pre-v0.88.2 solver overlap (a real
   S2+S3 plan left ~11.6 GB of duplicated content on disk).

## Decisions made

* `2026-06-11` — Campaign opened to own the library-side duplicate
  policy, taking over the "deterministic file pick" follow-up that
  `plan-solver-consolidation` explicitly scoped out (see its Pointers
  section).

## Open questions

1. **Playback pick** — when a unit has multiple files, which plays?
   Likely deterministic quality-aware (highest quality wins), but
   interaction with language preferences / track selection needs a
   look.
2. **Coexist vs reclaim** — is a duplicate an upgrade (keep both?) or
   waste (offer deletion)? MC never deletes user files unprompted, so
   reclamation must be explicit — Library maintenance is the natural
   surface ("N units have multiple copies, M GB reclaimable").
3. **Swap-time mitigation** — when swapping a pack-covered unit,
   should MC warn ("this episode also arrives inside the pack"),
   deselect the file in the torrent client, or accept-and-document?
   File deselection is in tension with the client-hygiene principle
   (clients own retention; MC hygiene = visibility only — commits
   `73d716ff` / `31af0920`).
4. **Visibility** — where do duplicates surface? Detail page badge,
   maintenance audit, both?

## Next steps

1. **Verify the stray-import path end-to-end** (it's currently
   code-read inference, not a repro): swap a pack-covered unit to a
   single, let both land, confirm the second playable item appears and
   that playback pick is insertion-order-arbitrary.
2. Decide and implement the deterministic playback pick (open
   question 1) — smallest user-visible harm, highest confidence.
3. Design the visibility + reclamation surface (open questions 2/4).
4. Decide swap-time mitigation (open question 3).
5. Document the settled policy in the wiki (Searching & Downloading +
   Troubleshooting) — the current wiki describes the bookkeeping
   honestly but the multi-copy end state is undocumented.

## Completion criteria

* Playback file choice is deterministic and documented when a unit has
  multiple files.
* Duplicate copies are visible to the user somewhere, with sizes, and
  an explicit (user-driven) reclamation path exists.
* The swap/pack physical-overlap path is either mitigated at grab time
  or deliberately accepted — decided, recorded, and documented in the
  wiki either way.
* Regression tests pin the chosen behaviors (append-only per ADR-027).

## Pointers

* Solver (context, solved): `lib/media_centaur/acquisition/planner.ex`.
* Swap ownership: `lib/media_centaur/acquisition/plans.ex` —
  `choose_release/2`.
* Per-unit satisfaction: `lib/media_centaur/acquisition/pursuits/commands/satisfy.ex`.
* Arbitrary file pick: `lib/media_centaur/library.ex` —
  `populate_leaf_content_url/1` (first WatchedFile, no ordering).
* Sibling campaigns: [`plan-solver-consolidation.md`](plan-solver-consolidation.md)
  (solver-side, scoped this out), [`pursuit-identity-and-lifecycle.md`](pursuit-identity-and-lifecycle.md)
  (landing-side identity; its 2026-06-11 prod verification produced
  ingress path 2 above).
* Client-hygiene principle: commits `73d716ff`, `31af0920`.
