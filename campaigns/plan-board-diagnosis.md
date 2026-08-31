---
status: implementing
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

Implementation largely landed 2026-08-31 (unpushed, commits on main):

- TV below-preference counting per unit (Planner solve returns
  `below_floor` map; persisted via `unfound_changeset/3`).
- Stop-searching: run observes plan status between search terms; board
  footer is one-press "Stop searching" while planning; Discard+confirm
  only when ready.
- Per-title acceptance: Quality "any" minimum; item validation admits
  it; manual plans resolve tracked-title bounds at creation;
  `Plans.accept_lower_quality/1` (tracks title — owner decision — sets
  item min "any", snapshots criteria, replans) and
  `undo_lower_quality/1`.
- Board model: grouped `PlanBoard.BelowPreference`, cell state
  `:below_preference` in CellVocabulary, `lower_quality_accepted?`.
- GapVerdict `:below_preference` world; verdict leads the ready board
  as a calm headline; descent panel collapses to a "How we searched"
  disclosure when ready. Stories updated (Murphy-Brown-shape +
  accepted-state variations).

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
- Acceptance on an untracked title TRACKS it (owner decision
  2026-08-31) — the tracking item is the one per-title preference home;
  no standalone preference store.
- `plan.criteria` was never dormant (drop planner writes it): it stays
  the per-plan snapshot; ADR-063 §2 amended accordingly.
- Implemented copy says "lower quality", never "SD" (imprecise) and
  never "floor" (banned).

## Next steps

1. Owner look at the live board (dev restarted with the new code;
   Murphy Brown re-solved). Pressing "Take lower quality for this
   show" there is the real acceptance — it tracks the show and grabs
   SD on approval.
2. Focusable grid cells + caption line (input-system nav-graph work) —
   deferred from the rebuild; hover titles carry the per-episode facts
   meanwhile.
3. Manage-surface visibility of the per-title acceptance (item
   auto-grab settings already hold it; surface a labeled row + reset).
4. Wiki sync (done in this pass — verify pages read right after owner
   look); marketing screenshots intentionally untouched.
5. Ship when the owner says so (/ship).

## Completion criteria

All acceptance criteria in the design plan check off against the real
app (real-click verification, not render_click); precommit green;
wiki updated; campaign file removed.
