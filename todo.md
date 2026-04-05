# Audit Backlog

Remaining items from the `/audit-all` run on 2026-04-05. The top 5
cross-cutting improvements (Ash→Ecto docs drift, dead log API purge,
library FK indexes, `toggle_watched` refactor, README polish) were
completed and shipped as three jj commits on top of `main`.

Every item below has been verified as a credible finding — false
positives (Ash/Ecto confusion in release_tracking/settings, hallucinated
Rust frontend claim in ADR-028, wrong N+1 remediation for
library_browser) have been discarded.

Structure: each item has a severity, location, fix summary, and a rough
effort estimate. Pick any batch that fits the available time — nothing
here is blocking.

---

## Performance

### P1. Handler render cost in caller's process
**Severity**: Moderate — only observable at high log volume
**File**: `lib/media_centaur/console/handler.ex`

`log/2` runs `build_entry` synchronously in the caller's process on every
log event. `build_entry` calls `render_message` which does `strip_ansi`
(regex) and `truncate` (`String.slice`) on the rendered binary. For a
500-byte SQL query log, this is ~100µs per call. At 100+ logs/sec during
heavy Ecto activity, this adds up to measurable latency in the calling
process.

**Fix**: Defer rendering to the Buffer GenServer. Store the raw `msg`
tuple + metadata in a "lazy entry" struct, and render on demand at view
time (console UI rendering, clipboard copy, download, `Diagnostics.log_recent`).
The hot path in the caller becomes: minimal Entry struct + `Buffer.append/1`
cast + return.

**Tradeoffs**:
- Adds complexity to the Buffer snapshot path (needs to know how to
  render lazily)
- The search filter in the console UI currently operates on the rendered
  `message` string — would need to either render-then-match (no savings) or
  rework to match against the raw structure
- Worth doing only if profiling shows the handler is a bottleneck

**Effort**: Medium-high. Architectural change. Recommend measuring first
(via Tidewave under load) before committing.

---

### P7. Config lookups in dashboard
**Severity**: Minor — repeated reads of rarely-changing config
**File**: `lib/media_centaur_web/live/dashboard_live.ex`

`load_config/0` is called on every mount and handle_params and reads 4+
config keys via `MediaCentaur.Config.get/1`. Config values rarely change
once loaded into `:persistent_term`, so memoizing the whole config map
per request (or caching with a short TTL) would save a handful of
`persistent_term` lookups.

**Fix**: Read once in mount, store in socket assigns, skip re-read in
handle_params unless a `settings:updates` broadcast arrives.

**Effort**: Low. Small caching change.

---

### P8. Logger handler installation timing
**Severity**: Minor — theoretical race window
**File**: `lib/media_centaur/application.ex`

The `:logger` handler is added before the supervision tree starts. During
the window between handler install and `Console.Buffer` boot (~10-20ms),
log events hit the handler but `Process.whereis(Buffer)` returns nil, so
the entries are silently dropped. The handler has a safety guard so
nothing crashes, but startup logs in that window are lost.

**Fix options**:
1. Move handler installation to `handle_continue` after the supervision
   tree is fully started
2. Accept the behavior as-is and document it explicitly in
   `application.ex` + the troubleshoot skill
3. Add a tiny in-process queue that buffers log events until Buffer is up

Option 2 is probably right — it's a 10-20ms window, the missed logs are
boot-time noise, and adding complexity to fix it isn't worth it.

**Effort**: Low for documenting, medium for actually fixing.

---

### P10. Verify library_browser N+1 claim
**Severity**: Unknown — audit's remediation was wrong, underlying claim may or may not be real
**File**: `lib/media_centaur/library_browser.ex`

The audit flagged `Repo.all(query) |> Repo.preload([...])` as N+1 and
suggested replacing with `Repo.all(query, preload: [...])`. Those are
equivalent at the SQL level, so the fix is wrong. But the underlying claim
— that library page loads issue too many preload queries — might still be
real.

**Fix**: Verify with Tidewave + EXPLAIN whether there's an actual N+1.
Count the queries fired during a library page mount with 50 TV series.
If it's 1 query per association level (expected), no action. If it's 1
query per entity per association (actual N+1), consider using SQL joins
via `from t in TVSeries, join: s in assoc(t, :seasons), preload: [seasons: s]`.

**Effort**: Low for verification (just EXPLAIN), medium for any actual
fix.

---

## Documentation

### D2. `PIPELINE.md` staleness verification
**Severity**: Unknown — may or may not be stale
**File**: `PIPELINE.md` (dated 2026-03-26)

Predates the console feature shipped 2026-04-05. May not reflect how logs
flow through `MediaCentaur.Console` now, or how rescan dispatch works
post-refactor. Content may also be accurate — unknown without reading it
end-to-end against current code.

**Fix**: Read PIPELINE.md in full, cross-reference against
`lib/media_centaur/pipeline/` and `lib/media_centaur/broadway/`, and
update any stale claims.

**Effort**: Medium. The document is long.

---

## Priority clusters

If picking a batch, these cluster cleanly by effort/risk:

- **Verification-first items (low effort but need measurement)**: P1, P10 — need Tidewave profiling before committing to a fix. Useful to scope before implementing.

- **Bigger polish items (1 session each)**: D2 (PIPELINE.md staleness verification).

- **Defer**: P7 (config caching — no observable impact), P8 (handler install timing — theoretical only).

---

## How to use this document

1. Pick a cluster or individual items.
2. Start a new session with `/audit-all` available for re-verification if
   the code has drifted since 2026-04-05.
3. Execute per the existing patterns in this repo — the `superpowers:`
   skills cover the planning → implementation → verification flow.
4. Strike completed items from this file as they ship.

When this file is empty, either re-run `/audit-all` or move on to a
different initiative.
