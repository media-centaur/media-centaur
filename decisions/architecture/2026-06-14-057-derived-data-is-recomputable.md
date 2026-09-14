---
status: accepted
date: 2026-06-14
---
# Derived data is recomputable, never frozen

## Context and Problem Statement

A library record mixes identity (which title a file is, its TMDB link —
expensive to compute, stable once known) with derived values a local rule
reads off the file path (a bonus feature's display name, a season or episode
number — cheap to compute, wrong whenever the rule has a bug). The discovery
pipeline froze both behind one boolean, `Discovery.already_linked?/1`, so a
parser improvement never reached records already on disk; a tracked show's
28 blank extras needed a hand-written backfill after a parser fix.

## Decision Outcome

Derived data is recomputable: a value that is a pure function of inputs the
system still holds is never frozen.

1. **Identity is separate from derived.** Identity stays frozen behind the
   link gate, which is the only path that hits TMDB. Derived fields (today
   `Extra.name`) are refreshable.
2. **Re-derivation is version-free.** It re-parses the path and updates the
   value only where the fresh result differs and is non-empty; it is pure,
   idempotent and network-free. A version stamp may later optimize which
   files to re-parse, never decide correctness.
3. **An empty derived value is never persisted**, enforced at the writer
   (`Extra.update_name_changeset/2`), so no producer can store a blank.
4. **Re-derivation must not overwrite a human edit.** No edit affordance
   exists for derived names today; whoever adds one adds the guard with it.

What shipped: `Pipeline.ExtraRederive`, run through
`Maintenance.rederive_extra_names/0`. The link gate is still the boolean; the
four-way reconciliation decision this record proposed (`fresh` / `relink` /
`refresh` / `up_to_date`) was not built, so re-derivation is a maintenance
sweep rather than a scan-path step.

### Consequences

* A parser fix heals existing records on the next sweep with no bespoke
  migration; it does not heal them on an ordinary scan until the gate
  becomes a decision.
