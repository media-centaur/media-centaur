---
status: accepted
date: 2026-06-14
---
# Derived data is recomputable, never frozen

## Context and Problem Statement

A library record mixes two kinds of fact with very different economics:

* **Identity** — which show/movie a file is, its TMDB link, its external IDs.
  Expensive to compute (a network round-trip plus matching), and stable once
  known. Recomputing it is costly and pointless.
* **Derived** — values a deterministic local rule reads off the file path: the
  display name of a bonus feature, its season/episode number. Cheap to compute
  (re-read one filename), and *wrong whenever the rule has a bug*.

The discovery pipeline freezes both at import behind a single boolean,
`Discovery.already_linked?/1`: once a file is linked it is skipped on every
later scan. That skip is correct for identity — it stops the pipeline re-hitting
TMDB and creating duplicates. But by bundling "linked" and "named" into one bit,
it also freezes the derived values forever. When a parsing rule is *improved*,
records already on disk never benefit.

This surfaced as the Frieren "Web Previews" bug (v0.95.2): a parser fix corrected
the rule, but the 28 already-imported extras stayed blank and needed a
hand-written backfill. That backfill is a symptom — the design makes every
parser improvement require a bespoke data migration.

## Decision Outcome

Chosen option: **treat derived data as recomputable**, because a value that is a
pure function of inputs the system still holds (the file path) should never be
frozen — it should be re-derivable on demand, with no network and no bespoke
migration.

Concretely:

1. **Separate identity from derived.** Identity stays frozen behind the link
   gate. Derived fields (today: `Extra.name`) are refreshable.
2. **Correctness is version-free.** Re-derivation re-parses the path and updates
   the value only where the freshly-derived result differs and is non-empty. It
   is pure, idempotent, and network-free. A version stamp may be added later
   purely to *optimize* which files to re-parse on a normal scan — it is never a
   correctness dependency.
3. **The link gate becomes a reconciliation decision**, not a boolean: `fresh`
   (full intake — the only path that hits TMDB), `relink` (moved/renamed),
   `refresh` (derived value stale → re-derive, no network), `up_to_date`.
4. **Never persist an empty derived value** — enforced at the writer (changeset),
   so no producer, present or future, can store a blank.

The rollout is tracked in `campaigns/deriver-model.md`.

### Consequences

* Good, because a parsing-rule fix heals existing records on the next sweep or
  scan, with no hand-written backfill — the class of work the Frieren bug forced.
* Good, because re-derivation is cheap and safe (no TMDB, idempotent), so it can
  run on ordinary scans without cost or duplication risk.
* Good, because separating identity from derived makes the model honest and gives
  the long-planned relink-on-move work a natural home (the `relink` branch).
* Bad, because the link gate grows from one `if` into a four-way decision plus
  (optionally) a version stamp — more surface to test and reason about.
* Bad, because re-derivation must not overwrite a human edit. Today no edit
  affordance exists for derived names, so this is latent; if one is added, a
  "user-edited" guard must land with it. We design the seam to accept that guard
  but do not build it pre-emptively.
