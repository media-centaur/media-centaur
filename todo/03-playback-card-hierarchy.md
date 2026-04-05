# Restore UIDR-005 hierarchy on the Status playback card

**Source:** design-audit 2026-04-06, DS2 + DS11
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/live/status_live.ex` (the `playback_summary_card/1` component, around line 716)

## Context

[UIDR-005](../decisions/user-interface/2026-03-06-005-playback-card-hierarchy.md) specifies a three-row layout for the playback summary card:

1. **Header row:** "Playback" title left, state label right.
2. **Identity block:** Show/movie name on its own line (`text-base font-medium`), episode detail below.
3. **Progress row:** bar + timestamps, bar color matches state.

The current per-session render at `status_live.ex:733-740` (path is now Status, not Dashboard) collapses the state label and the title onto the **same** flex row:

```heex
<div class="flex items-center gap-2">
  <span class={["text-xs", playback_text_class(session.state)]}>
    {session.state}
  </span>
  <span class="text-base font-medium truncate">
    {now_playing_title(session.now_playing)}
  </span>
</div>
```

Two violations:
- **UIDR-005:** the identity block is no longer on its own line; the state label is inline with the title instead of in the header row.
- **UIDR-008 (baseline alignment):** `text-xs` + `text-base` on an `items-center` row produces a visible baseline drift.

The card has also evolved to handle multiple concurrent sessions, which UIDR-005 didn't anticipate. Any fix needs to keep multi-session working.

## What to do

1. Re-read UIDR-005 to make sure the three-row model is fresh.
2. For each session, emit three rows:
   - **Identity row:** title on its own line, `text-base font-medium truncate`, no sibling text on this row.
   - **Detail row:** `text-sm text-base-content/60`, shows S01E03 · Episode Name (TV), nothing (movies), or extra name (extras). Use `now_playing_detail/1` which already exists.
   - **Progress row:** the existing `<progress>` bar and right-aligned remaining timestamp.
3. The state label belongs in the multi-session "header" area — either inline next to the title *without* mixed sizing (bump the state label to `text-base`, or use a small coloured dot instead), or keep it only in the header row at the top of the card and drop it from per-session rendering. The card already puts state at the top via the border-left colour + the "N active" counter; the per-session state label may be redundant.
4. If you keep a per-session state indicator, use `items-baseline` on any row that still mixes text sizes, or drop the mixed sizing entirely.
5. The idle state is already correct — leave it alone.

## Acceptance criteria

- Series name is on its own line for the TV-episode case.
- No `items-center` flex row with mixed-size text children.
- Multi-session rendering still works.
- Progress bar colour still matches state.
- Idle card still renders "Idle" muted text with no progress bar.
- `mix precommit` clean.
