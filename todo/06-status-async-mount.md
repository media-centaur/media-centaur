# Status page async mount for slow data sources

**Source:** design-audit 2026-04-06, DS18
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/live/status_live.ex`

## Context

`StatusLive.mount/3` fans out to ten-ish data sources synchronously:

- `Status.fetch_stats/0` (DB queries: library counts, pending review, recent errors, recent changes)
- `Stats.get_snapshot/0` (GenServer call — fast)
- `ImagePipeline.Stats.get_snapshot/0` (GenServer call — fast)
- `Watcher.Supervisor.statuses/0` (GenServer call — fast)
- `Watcher.Supervisor.image_dir_statuses/0`
- `Storage.measure_all/0` (hits the filesystem — can be slow)
- `check_dir_health/0` (File.dir? per watch dir — cheap)
- `load_config/0`
- `fetch_rate_limiter/0`
- `fetch_retry_status/0`
- `build_playback_state/0`

Most are in-memory GenServer calls, but `Storage.measure_all/0` and `Status.fetch_stats/0` (which hits the DB) are the slow ones. Today the LiveView blocks on all of them before rendering.

## What to do

Split the mount into "fast path" (in-memory GenServer reads → render immediately) and "slow path" (DB + filesystem → `assign_async`):

1. In `mount/3`, set every slow-path assign to a loading placeholder:
   - `library_stats: :loading`
   - `recent_changes: :loading`
   - `recent_errors: :loading`
   - `recently_watched: :loading`
   - `storage_drives: :loading`
2. Keep the fast in-memory pipeline/image-pipeline/watcher/playback reads synchronous.
3. Kick off two `assign_async` tasks:
   - One for `Status.fetch_stats/0`, assigning `library_stats`, `pending_review_count`, `recent_changes`, `recently_watched`, `recent_errors`.
   - One for `Storage.measure_all/0`, assigning `storage_drives`.
4. In the render, handle the `:loading` sentinel: show a skeleton shimmer for the stats row, an empty card body with a spinner for the errors table and storage drives, etc. Use `animate-pulse` on skeleton elements (they are not in a LiveView stream, so the CLAUDE.md keyframe-on-stream rule does not apply).
5. The existing `:tick_pipeline` and `:refresh_storage` timers should still work, but consider suppressing the first tick until the async results have landed so a half-loaded state doesn't flicker.

## Acceptance criteria

- `/status` renders the pipeline/watcher/playback section immediately on mount.
- Library stats, recent changes, recent errors, and storage metrics each appear as soon as their underlying query finishes.
- Nothing flickers between loaded and loading back to loaded.
- `mix precommit` clean.
- Verify by opening `/status` in the browser while the library has a few thousand files (or simulate slowness by adding a `Process.sleep(500)` into `Status.fetch_stats/0` temporarily).
