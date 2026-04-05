# Auto-approve rate metric on the Status page

**Source:** design-audit 2026-04-06, DS23
**Severity:** Moderate (planned feature)
**Scope:** `lib/media_centaur/pipeline/stats.ex`, `lib/media_centaur_web/live/status_live.ex`, `DESIGN.md`

## Context

`DESIGN.md` promises:

> **Auto-approve rate**: % of files auto-approved vs needed review (confidence threshold effectiveness)

Not implemented. There is no counter in `Pipeline.Stats` tracking auto-approved vs needs-review, and the Status page doesn't render anything of the sort.

The metric's point is to answer: "is my confidence threshold too aggressive (manual work piling up) or too lax (bad matches getting auto-approved)?"

## What to do

1. **Add lifetime counters to `Pipeline.Stats`.** Two new fields in the stats state:
   - `auto_approved_total` — incremented when a file lands in Review and is auto-approved without user intervention because its confidence exceeded the threshold
   - `needs_review_total` — incremented when a file lands in Review and requires user action (low confidence, tied, or no results)

   These are lifetime since BEAM start, matching the existing `total_failed` / `total_downloaded` fields.

2. **Hook the counters.** The auto-approve path runs in the pipeline's Import stage when confidence is ≥ the configured threshold. Find the branch and add a telemetry event or direct `GenServer.cast` to `Pipeline.Stats`. The `needs_review` path runs when the file is persisted into `review_pending_files`. Instrument both sides symmetrically.

3. **Expose via snapshot.** `Stats.get_snapshot/0` already returns a map — add `auto_approved_total` and `needs_review_total` to it, plus a derived `auto_approve_rate` (percent float, or `nil` if the sum is zero).

4. **Render on Status.** Add a small metric block in the pipeline card or the external integrations card. Format:
   ```
   Auto-approve rate    87%
                        1,240 auto / 182 reviewed
   ```
   Use `text-base-content/60` for the label, colored `text-success` / `text-warning` / `text-error` for the rate based on thresholds (say ≥80% green, 50-80% yellow, <50% red). The `text-xs` breakdown line uses `items-baseline` (UIDR-008) with the main number.

5. **Persist counters across restarts?** Optional. The existing `Pipeline.Stats` counters are in-memory only, reset on BEAM restart. If you want this to survive restarts, persist via `Settings.Entry` with a debounced write. If the metric is cheap to reset ("since last restart"), leave it in-memory — just label it clearly in the UI.

6. **Tests.** `Pipeline.Stats` gets tests covering the new counters. The Status LiveView integration test covers that the assign is present.

7. **Update DESIGN.md.** Move "Auto-approve rate" from Planned additions to the shipped Status sections list.

## Acceptance criteria

- Status page shows auto-approve rate with breakdown.
- Counters advance in real time during a pipeline run.
- The rate is colour-coded by threshold.
- `mix precommit` clean.
- DESIGN.md updated.
