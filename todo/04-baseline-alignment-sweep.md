# Fix mixed-size `items-center` flex rows per UIDR-008

**Source:** design-audit 2026-04-06, DS8 + DS9 + DS10 + DS12
**Severity:** Minor (4 instances)
**Scope:** `lib/media_centaur_web/live/status_live.ex`, `lib/media_centaur_web/live/review_live.ex`

## Context

[UIDR-008](../decisions/user-interface/2026-03-15-008-flex-row-text-baseline-alignment.md) says text/text flex rows (label + value in different font sizes) use `items-baseline`; `items-center` only applies to text/control rows. The following four sites drift from this rule — each mixes text sizes under `items-center` and produces a visible baseline offset.

The playback-card row (DS2/DS11) is covered separately in `03-playback-card-hierarchy.md`; do not duplicate that work here.

## Sites

1. **Status pipeline-card header** — `status_live.ex:400-407`
   ```heex
   <div class="flex items-center gap-3 text-sm">
     <span :if={...} class="text-info text-sm">{queue_depth} queued</span>
     <span :if={...} class="text-error text-xs">{total_failed} failed</span>
   </div>
   ```
   `text-sm` + `text-xs` — swap `items-center` → `items-baseline`.

2. **Status directory row** — `status_live.ex:550-581`
   ```heex
   <div class="flex items-center gap-3 mb-1">
     <span class="text-xs text-success ...">images: ok</span>
     <code class="text-sm truncate-left flex-1">...</code>
     <span class="text-xs font-mono ...">...</span>
   </div>
   ```
   `text-xs` + `text-sm` — `items-baseline`.

3. **Status external integrations** — `status_live.ex:643-651`
   ```heex
   <div class="flex items-center gap-2">
     <span class="text-sm font-medium">TMDB</span>
     <span :if={...} class="text-success text-xs">configured</span>
   </div>
   ```
   `text-sm` + `text-xs` — `items-baseline`.

4. **Review "Parsed" row** — `review_live.ex:537-552`
   ```heex
   <div class="glass-inset rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
     <span class="text-[0.625rem] font-semibold uppercase ...">Parsed</span>
     <span class="text-sm font-medium">{@file.parsed_title || "Unknown"}</span>
     ...
   </div>
   ```
   Micro label + `text-sm` + the `badge-sm badge-outline` type badge. `items-baseline` works for the text; verify the badge doesn't look worse on baseline (it should be fine, daisyUI badges sit on the baseline at the bottom edge of the text).

## What to do

Replace `items-center` with `items-baseline` on each of the four rows above. Check the rendered output — for row 2 (directory row) the `<progress>` and drive-usage number below it are in a separate flex row, so the change is localized.

## Acceptance criteria

- All four rows use `items-baseline`.
- Rendered pages look correct (no sudden vertical misalignment).
- `mix precommit` clean.
