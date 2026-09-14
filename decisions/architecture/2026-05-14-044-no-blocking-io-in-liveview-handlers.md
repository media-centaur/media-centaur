---
status: accepted
date: 2026-05-14
amended: 2026-05-22
---
# No blocking external I/O in LiveView mount, handle_event, or handle_info

## Context and Problem Statement

A LiveView process serialises its own messages. While one handler blocks on a network round-trip (a Prowlarr search, a TMDB fetch, a download-client call) the process renders nothing and answers nothing, and a long enough block downgrades the transport. A modal open that fanned out a search from inside `handle_event/3` took half a second; the database part was under five milliseconds.

## Decision Outcome

Synchronous external I/O is forbidden in `mount/3`, `handle_params/3`, `handle_event/3`, `handle_info/2` and the helpers they call. The boundary is latency not bounded by the local process or a local file.

1. **Always async:** Prowlarr, TMDB, download-client RPC, any HTTP call, any read from a configured media directory, and anything that awaits one of these.
2. **Synchronous is fine:** `Repo` queries on local SQLite, ETS and `:persistent_term` reads, pure functions, view-model assembly, PubSub broadcasts.
3. **Synchronous only when proved:** `GenServer.call` to an in-process singleton. Document the call and the invariant that keeps the singleton non-blocking, or use a cast.
4. **The fix shape is owned async** (amended 2026-05-22 by [ADR-049](2026-05-22-049-testing-principles.md)): `start_async/3` or `assign_async/3`, a loading placeholder on the first render, and an identity check that drops a stale result. The earlier manual `Task.Supervisor.start_child` plus `send` loop orphans work under the global supervisor and is banned in the web layer by MC0019.
5. **Review trigger:** any call into `Search`, `TMDB`, `HttpClient`, `Req`, a download-client driver, or `File`/`Path` against a media path inside one of the handlers above is a violation, not a judgment call.

### Consequences

* Every async path carries a loading branch and a completion handler, and one more place state can drift.
* "Repo is fast" holds only while the database is local SQLite; a networked database would move every query into the async bucket.
