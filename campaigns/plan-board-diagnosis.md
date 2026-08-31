---
status: planning
started: 2026-08-31
last_updated: 2026-08-31
---
# Plan Board Diagnosis

## Goal

Rebuild the plan board popup as a verdict-led diagnosis (grid chassis +
outcome rows + receipts) on a single per-unit outcome model; add the
per-title quality acceptance ("Take SD for this show") and real
mid-search stop. Design records: UIDR-029, ADR-063; design plan
`docs/plans/2026-08-31-plan-board-diagnosis.md`; reference mockups in
`docs/plans/plan-board-diagnosis-mockups/`.

## Status

Design phase complete (2026-08-31): decisions recorded, plan + mockups
committed. No implementation started.

## Decisions made

- Per-unit outcome (kept / below_preference / nothing) is the one
  representation, computed identically for movies and TV, persisted on
  plan units (ADR-063 §1).
- Quality bound resolves unit override → per-title preference → global
  default; acceptance writes the per-title layer, resettable in Manage
  (ADR-063 §2). `plan.criteria["min_quality"]` becomes the snapshot or
  is removed — decide during implementation planning.
- Plan status is the cancellation channel; the run observes it at
  search-term boundaries (ADR-063 §3).
- Board layout + copy rules per UIDR-029: verdict headline (GapVerdict
  promoted, sole sentence-maker), enlarged outcome grid, outcome rows
  with the decision attached, receipts footnote + "How we searched"
  disclosure; descent panel headline retired. "Stop searching" one
  press mid-search; Discard confirmation only when ready.

## Next steps

1. Implementation planning (test-first per automated-testing): outcome
   model in the solve loop + unit persistence for both media types.
2. Verdict template family over the outcome vocabulary (extend
   GapVerdict; retire DescentNarrative headline duty).
3. Board view models + modal body rebuild + stories (MC0009 bundles
   component + story rewrites).
4. Per-title preference storage + Manage surface + acceptance flow.
5. Stop-searching status checks in the run.
6. Wiki sync at ship (Settings-Reference, Using pages, FAQ for the
   SD-acceptance behavior); final copy pass through writing-copy.

## Completion criteria

All acceptance criteria in the design plan check off against the real
app (real-click verification, not render_click); precommit green;
wiki updated; campaign file removed.
