# "Since last visit" semantics for Status Recent Changes, or revise DESIGN.md

**Source:** design-audit 2026-04-06, DS24
**Severity:** Moderate (planned feature, partially shipped)
**Scope:** `lib/media_centaur_web/live/status_live.ex`, `lib/media_centaur/status.ex`, `DESIGN.md` — possibly `MediaCentaur.Settings`

## Context

`DESIGN.md` promises:

> **Recent activity**: last N entities added (what's new since I last looked)

The "last N entities added" half is shipped — `recent_changes_card` in `status_live.ex:285-293` renders the feed from `Status.fetch_stats/0` → `Library.list_recent_changes!/2`. The "since I last looked" half is NOT shipped: every page load shows the same global rolling window (configured via `recent_changes_days`, default 3), with no per-user read watermark.

This is a promise that either needs fulfilling or retracting. It's not a bug — what ships today is fine — but the design document is making a claim the code doesn't back up.

## Option A — ship the "since last visit" semantics

1. Add a `Settings.Entry` key like `status_last_visit` storing an ISO-8601 timestamp. The Settings module already supports this pattern — see how `spoiler_free_mode` and console filter state persist.
2. On `StatusLive.mount/3`, read `status_last_visit`, pass it to the render as `@last_visit_at`, then update the key to `DateTime.utc_now()` (debounced).
3. In `recent_changes_card`, render each entry with a visual "unread" marker (e.g. a small `bg-primary` dot on the left) when `entry.inserted_at > @last_visit_at`.
4. Optionally add a count chip at the top of the card: "3 new since your last visit".
5. Consider the cross-device case — the watermark is per installation, not per user, because the app is single-user (per `CLAUDE.md`). Don't over-engineer it.

## Option B — revise DESIGN.md

If "since last visit" isn't worth the complexity (my read: it probably isn't — the user is the only developer and checks the Status page often), just trim the promise:

```diff
-- **Recent activity**: last N entities added (what's new since I last looked)
++ **Recent activity**: last N entities added over the recent_changes_days window
```

Then move the line from "Planned additions" to the shipped section list.

## What to do

Pick one. **Option B** is probably the right call unless you actively want the unread tracking — in which case Option A is straightforward.

## Acceptance criteria

- If Option A: unread markers visible, watermark persists across restarts, no flashing on page reload.
- If Option B: DESIGN.md no longer promises unread tracking, Recent Changes is listed as a shipped Status feature.
- Either way: `mix precommit` clean, no silent design-doc drift remaining.
