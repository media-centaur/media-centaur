---
status: accepted
date: 2026-08-11
---
# Gap banner states the diagnosed world, with its evidence — never a bare "not available"

## Context and Problem Statement

When a plan finishes with gaps, the board's gap banner asserts a conclusion
("N not available right now") without its supporting evidence. The sentence
collapses four different worlds into one claim:

* raw results came back but every one was rejected (identity mismatch,
  red-flag, prior exclusion) — the user would likely find the title manually,
  and the app looks broken;
* no indexer returned anything at all — manual hunting with the same queries
  is pointless;
* the emptiness was served from the corpus cache — "right now" is actually
  hours old;
* quality-floor rejections (already surfaced separately by the below-floor
  banner).

The user cannot distinguish "the world has nothing" from "the app rejected
what the world offered", so they cannot decide whether manual hunting, a live
re-search, or loosening something is worth their time. The search evidence
(terms, raw counts, rejection reasons, freshness) is computed during the plan
run and then discarded; the activity ticker shows only the last line, only
live, and evaporates on re-open.

UIDR-016 already made the banner honest about *blind* searches ("couldn't
check availability"). This extends the same honesty to searches that *did*
run.

## Decision Outcome

Chosen option: "adaptive diagnosis verdict", because it fixes the trust
damage at the sentence level — where it happens — without new panels or
disclosure machinery.

The gap banner states the diagnosed world, derived **mechanically from
counts the plan run already computes** (never inferred causes):

* **Results rejected** — "14 results came back, but none looked like this
  movie." Evidence line beneath, muted: the literal query strings and
  freshness. A third button, **Show them anyway**, opens the *same
  alternatives panel* the below-floor banner uses, listing rejected releases
  with a muted per-result reason (didn't match this title / flagged
  suspicious / you excluded this earlier). Choosing one assigns it — the
  manual override for a matcher false-negative.
* **Zero raw results, live** — "No indexer had anything for this title."
  Evidence: search count, indexer count, "live just now". No escape hatch.
* **Corpus-served emptiness** — "Nothing in the last known results (from
  6 hours ago)." Evidence: "Search again asks your indexers live."
* **Blind** (UIDR-016) — unchanged, and takes precedence.

The below-floor banner is untouched; quality rejections never count toward
the "came back" number. TV plans keep the descent panel as the per-rung
narration; their gap banner gains the same adaptive sentence in aggregate.

Visual scope: the existing glass-inset warning row. Amber stays confined to
the icon and verdict line; the evidence line is muted prose; no chips, no
chevrons, no tables.

**The evidence is part of the pursuit's story.** A pursuit is a narrative —
what was wanted, what was tried, what the world offered, what was decided —
so search evidence persists with the pursuit rather than living in the
transient ticker, and is cleaned up when the pursuit's story ends (same
retention discipline as the rest of its record). The banner must render
identically on a re-opened modal days later.

### Consequences

* Good, because the user's real question — "should I go hunt for this
  myself?" — is answered by the verdict itself, per world.
* Good, because matcher false-negatives stop being silent: the rejected
  results are one click away, with assignment as the override.
* Good, because it reuses the alternatives panel and the existing banner
  row — no new surfaces to maintain.
* Good, because the diagnosis vocabulary is closed and mechanical, so the
  banner can never claim a cause the counts don't prove.
* Bad, because the plan run must persist a small search report it currently
  discards — the bulk of the implementation cost.
* Bad, because TV gaps get only an aggregate sentence; per-unit world
  diagnosis is deferred.
