---
status: planning
started: 2026-06-10
last_updated: 2026-06-10
---
# Pursuit identity & lifecycle: provenance over filenames

## Goal

Make composite (multi-unit) pursuits survive real landings. A live
S2+S3 pursuit (The Orville, 2026-06-10, v0.88.1) was system-cancelled
the moment its first file landed: `IdentityVerifier` fuzzy-matched the
filename against the pursuit's *lead* unit (S02E01), saw S03E07,
declared "identity mismatch", and `Cancel`led all 24 units while six
torrents kept downloading — orphaned into "Other downloads". End
state: file→unit identity comes from grab-time provenance (the
`Pursuits.Identity` ladder), verification never cancels a composite,
and a pursuit concludes only when its units do.

## Status

Verifier rework implemented 2026-06-10 (same session as diagnosis):
`InboundListener` passes the landed unit's season/episode in job args;
`IdentityVerifier` is now a landing satisfier (satisfies the landed
unit's target span via `Satisfy` + `fallback_unit_id`, no-ops on
unwanted/duplicate landings, defers identity-less landings to
`LibraryReconciler`) — TitleMatcher gate, mismatch event producer, and
whole-pursuit `Cancel`/`Satisfy` all retired from this path. Regression
tests pin the Orville shape (composite pursuit, out-of-order non-lead
landing). REMAINING: the cancelled-pursuit ↔ live-torrent contract
(next step 1) and prod verification with a real multi-release plan. Settled design principle
recorded below. Sibling campaign:
[`plan-solver-consolidation.md`](plan-solver-consolidation.md)
(overlapping grabs made this fire sooner, but any multi-release plan
hits it — even a clean 2-pack plan dies on the twin `Satisfy` path,
which closes the whole pursuit on the *first* verified file).

## Decisions made

* `2026-06-10` — **Provenance over filenames (user-settled).** TMDB
  pursuits know what they're looking for; identity is settled at grab
  time by the recorded mapping (infohash → release → assigned units,
  content path captured atomically — `Pursuits.Identity` strategies
  1–2, already documented as authoritative and "never second-guessed
  by a title"). Filename *title*-matching keeps exactly two jobs:
  `prowlarr_query` recipes and the hashless fallback (strategy 4).
  Episode-number extraction inside a known pack (which unit is this
  member file) is constrained parsing, not identity matching — keyed
  to the unit by TMDB identity (strategy 3).
* `2026-06-10` — **Mismatch handling is per-unit and non-destructive.**
  A genuinely suspicious file flags its unit for review; it never
  cancels a composite pursuit. `IdentityVerifier`'s
  mismatch→`Cancel`-whole-pursuit and match→`Satisfy`-whole-pursuit
  are both single-unit-era logic to be retired.
* `2026-06-10` — Pursuit conclusion is an aggregate over unit states
  (all units terminal → pursuit concludes), not a reaction to any
  single landing.
* `2026-06-10` — Implemented: listener job args carry unit identity;
  the verifier satisfies the landed unit's target span
  (`Satisfy.fallback_unit_id` scopes target-less units to one unit);
  unwanted-episode and duplicate landings are no-ops;
  TV landings without unit identity defer to `LibraryReconciler`.
  `identity_mismatch` event kind and cancel reason stay registered so
  historical rows keep rendering — they just have no producer.

## Next steps

1. Decide the cancelled-pursuit ↔ live-torrent contract (today: cancel
   is DB-only; torrents keep downloading with no owner, files still
   ingest via the watcher) — NEEDS USER: re-link surface vs. explicit
   orphan adoption vs. client cleanup prompt. Also covers cleaning up
   the 2026-06-10 orphaned Orville torrents.
2. Verify on prod with a real multi-release plan after the next
   release ships.

## Completion criteria

* A multi-unit TMDB pursuit with N releases landing in any order
  concludes with per-unit accuracy; no whole-pursuit cancel/satisfy
  from a single landing.
* No filename title-matching on the landing path for tmdb-recipe
  pursuits with a captured envelope.
* Regression tests pin the Orville shape (append-only, ADR-027).
* The cancelled-vs-live-torrents contract is explicit and tested.

## Pointers

* `lib/media_centaur/acquisition/pursuits/identity.ex` — the ladder
  (the architecture this campaign enforces).
* `lib/media_centaur/acquisition/pursuits/identity_verifier.ex` —
  reworked 2026-06-10 into the landing satisfier (was: `TitleMatcher`
  on basename vs. `Units.lead/1`, then `Cancel`/`Satisfy` on the whole
  pursuit).
* `lib/media_centaur/acquisition/pursuits/{inbound_listener,
  library_reconciler, download_identity}.ex` — landing path.
* Prod evidence: incident `2968cf13`; Reactor crash storm 20:41–21:11
  UTC was the separate prod-DB-migrated-under-0.87.1 footgun
  (memory: default mix tasks target the prod DB), resolved by the
  0.88.1 update.
