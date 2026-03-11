# 010 — Engineering Hardening

Findings from a brutally honest engineering audit. Grouped by effort and risk.

## Tier 1 — Quick wins (< 30 min each)

### A. ~~Fix `String.to_existing_atom` in pipeline producer~~ DONE

- **File:** `lib/media_centaur/pipeline/producer.ex:118`
- **Fix:** Replaced with `validated_tmdb_type/1` — a case that maps `"movie"` and `"tv"` to known atoms, raises on anything else.

### B. ~~Delete dead domain functions~~ DONE

- **File:** `lib/media_centaur/library.ex`
- **Fix:** Removed 4 dead `define` statements: `list_identifiers`, `list_extras`, `find_or_create_image`, `find_or_create_movie_image`, `find_or_create_episode_image`. Also removed `list_entities_all_files_absent` (only caller was dead helper code).

## Tier 2 — Important, bounded scope

### C. ~~Library browser: push absent-entity filter into DB~~ DONE

- **File:** `lib/media_centaur/library_browser.ex`
- **Problem:** Two-query pattern — load all absent IDs, then load all entities, then `Enum.reject` in Elixir.
- **Fix:** Pushed exclusion filter directly into the Ash query via `not (exists(watched_files, true) and not exists(watched_files, state == :complete))`. Eliminated `Helpers.entity_ids_all_absent` and `entity_ids_all_absent_for` (now dead). Note: full pagination deferred — the library still loads all entities on mount, but the absent-entity filtering is now a single DB query instead of two queries + Elixir filter.

### D. ~~File tracker TOCTOU race~~ DONE

- **File:** `lib/media_centaur/library/file_tracker.ex`
- **Fix:** Added a re-check inside `delete_entity_cascade` — if new files appeared between the caller's check and the cascade, it aborts with a log message instead of destroying the entity.

## Tier 3 — Structural improvements

### E. ~~Extract LiveView helpers into focused modules~~ DONE

- **File:** `library_live.ex` (1006 → 835 lines)
- **Fix:** Extracted 12 pure functions (filtering, sorting, tab counts, progress computation, resume formatting, display helpers) into `MediaCentaurWeb.LibraryHelpers` (191 lines). `review_live.ex` helpers are tightly coupled to review-specific display — no clean extraction target.

### F. ~~Add playback public API tests~~ SKIPPED

- **Reason:** PlaybackManager is a thin orchestrator — its logic delegates to SessionSupervisor and MpvSession (real mpv socket). Testing the public API requires mocking both for low signal. Updated the GenServer testing policy in CLAUDE.md to clarify: test GenServers with meaningful public logic (Stats, RetryScheduler), skip thin wrappers around external systems.

## Not worth doing

- **Ash overhead** — cost already paid, ripping out is destructive for no gain
- **Catch-all `handle_info`** — standard OTP practice, not bugs
- **Admin unbounded loads** — developer-only danger zone, used rarely
- **Dashboard `rescue _ -> nil`** — defensive for a status display, acceptable
