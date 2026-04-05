# Empty state for the console log list

**Source:** design-audit 2026-04-06, DS20
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/components/console_components.ex` (the `log_list/1` component)

## Context

Every other page in the app has an empty-state message when there's no data to show: Library ("Nothing in progress" / "No entities found"), Review ("All clear"), Status ("No errors.", "No changes yet.", etc.). The console log list doesn't. When the buffer is empty — or when every entry is filtered out — the log area is a blank `<main>` with no message, no hint about filter state, nothing.

## What to do

In `log_list/1`:

1. Render a centered empty-state block when `@streams.entries` has no items. The LiveView stream doesn't expose its count directly, so either:
   - Pass a count into the component from the parent LiveView, OR
   - Use the DOM-based trick `:empty` selector — a CSS `.console-log:empty::before { content: "..." }` styled block in `app.css` — which handles both "truly empty" and "filter matches nothing" without any LiveView plumbing. Prefer this: the display logic is purely presentational and the stream's DOM state is the truth.
2. The message should distinguish the "buffer empty" case from the "filter hides everything" case if possible. If using CSS `:empty`, a single message ("No log entries") is fine. If using an assign, branch on `@filter` to show "No log entries — all components are muted, click a chip to show entries" when the filter is restrictive.
3. Include a small hint about the backtick toggle for the sticky drawer variant. Skip that hint on the full-page `/console` (there's nothing to toggle from there).

## Acceptance criteria

- Opening the console with an empty buffer shows a centered "No log entries" message, not a blank area.
- Muting every component shows the empty state too.
- Adding a log entry makes the empty state disappear.
- `mix precommit` clean.
