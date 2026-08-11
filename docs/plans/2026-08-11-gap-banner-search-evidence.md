# Gap Banner Search Evidence — Adaptive Diagnosis Verdict

> Design plan (2026-08-11). Describes WHAT the UI should be, not how to
> build it. Decision: [UIDR-022](../../decisions/user-interface/2026-08-11-022-gap-banner-adaptive-verdict.md).

## Problem Statement

The plan board's gap banner ("N not available right now") asserts a
conclusion without evidence — which queries ran, how many results came
back, why none qualified, and how fresh the check was. The user cannot
distinguish "the world has nothing" from "the app rejected what the world
offered", so they can't decide whether to hunt manually, force a live
re-search, or trust the verdict. Matcher false-negatives are completely
silent and indistinguishable from genuine scarcity.

## Design Objectives

* **Honesty with receipts** — the verdict names the diagnosed world; the
  evidence rides in the same banner as one muted line.
* **Actionability** — each world's copy points at the lever that applies:
  view the rejected results, search again live, or trust it.
* **Recourse over perfection** — the matcher will be wrong sometimes; the
  rejected results are one click away and assignable.
* **Mechanical diagnosis only** — the verdict states what the counts
  prove, never an inferred cause.
* **The pursuit is a story** — search evidence is part of the pursuit's
  narrative record: it survives modal re-open and is cleaned up when the
  pursuit concludes, like the rest of its record.

## User-Facing Behavior

The gap banner renders one of four verdicts (blind, from UIDR-016, takes
precedence and is unchanged):

1. **Results rejected**: "14 results came back, but none looked like this
   movie." Muted evidence line: "Searched 'Sample Movie 1990' and 'Sample
   Movie' live just now." Buttons: **Show them anyway** · Track these
   later · Search again. *Show them anyway* opens the existing
   alternatives panel listing every rejected release with a muted reason
   (didn't match this title / flagged suspicious / you excluded this
   earlier); choosing one assigns it to the unit, exactly like the
   below-floor grab.
2. **Zero raw results (live)**: "No indexer had anything for this title."
   Evidence: "2 searches across 6 indexers, live just now — nothing came
   back." No escape hatch.
3. **Corpus-served emptiness**: "Nothing in the last known results (from
   6 hours ago)." Evidence: "Search again asks your indexers live."
4. **Blind** (UIDR-016): "Couldn't check availability — …" — unchanged.

The below-floor banner is unchanged and coexists; quality rejections never
count toward world 1's number. On TV plans the descent panel keeps
narrating per rung; the gap banner uses the same adaptive sentence
aggregated across the gap units' searches.

Visuals: existing glass-inset warning row. Amber confined to icon +
verdict line; evidence line muted; no chips, chevrons, tables, or new
panels.

## Acceptance Criteria

- [ ] After a completed search, the gap banner never renders the bare
      "not available" claim — it always states one of the diagnosed
      worlds, with real counts.
- [ ] The evidence line shows the literal query strings and whether
      results were live or cached (with age when cached).
- [ ] When ≥1 raw result was rejected on a movie plan, "Show them
      anyway" appears and opens the rejected list with a per-result
      reason; choosing one assigns it, same as below-floor's grab.
      (TV plans state the aggregate rejected count without the hatch —
      per-unit recourse is deferred with per-unit diagnosis.)
- [ ] Zero-rejected worlds show no escape hatch.
- [ ] Re-opening the plan modal later (or after a refresh) shows the same
      evidence — no dependence on having watched the ticker live.
- [ ] "Search again" produces an updated evidence line whose freshness
      reads live.
- [ ] Blind world copy and precedence (UIDR-016) unchanged; below-floor
      banner unchanged.
- [ ] Keyboard/gamepad nav reaches the new button like the existing two.
- [ ] Evidence is cleaned up with the pursuit's record when its story
      ends (same retention discipline as the rest of the pursuit).

## Anti-patterns

- **Confident misdiagnosis**: only state what the counts mechanically
  prove; no inferred causes. Wrong-but-confident is worse than
  vague-but-true.
- **Second rejected-results surface**: the escape hatch opens the
  existing alternatives panel, never a new list component.
- **Log dump**: no per-term tables, no console idiom; evidence stays one
  prose line.
- **Reason chips**: rejection reasons are muted text; amber remains the
  only accent.
- **Ticker dependence**: evidence renders from durable pursuit state,
  never from the transient activity feed.

## Deferred

- Per-indexer result breakdown (Status page territory).
- Editing/adding a custom query from the banner (separate feature).
- Per-unit world diagnosis on TV plans (aggregate sentence only), and
  with it the TV escape hatch — a rejected pick needs a specific unit
  to assign to.

## Decisions

See [UIDR-022 — Gap banner states the diagnosed world, with its
evidence](../../decisions/user-interface/2026-08-11-022-gap-banner-adaptive-verdict.md).
Extends [UIDR-016 — Needs attention / gap-banner blind-search
honesty](../../decisions/user-interface/2026-08-01-016-needs-attention-section.md).
