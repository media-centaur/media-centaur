---
status: accepted
date: 2026-02-27
---
# PubSub-driven pipeline input

## Context and Problem Statement

The original pipeline used a database-claiming model: the Producer polled for WatchedFile records in a `:detected` state and atomically claimed them for processing. This coupled the pipeline to the database schema, made the Producer stateful, and introduced polling latency between file detection and processing.

## Considered Options

* PubSub events from Watcher to Producer
* Database polling with atomic claims (previous design)

## Decision Outcome

Chosen option: "PubSub-driven pipeline input", because it decouples file detection from processing, eliminates polling, and makes the pipeline input model event-driven.

**How it works:**
- Each Watcher broadcasts `{:file_detected, %{path, watch_dir}}` to `"pipeline:input"` when a file stabilizes
- The Producer subscribes to `"pipeline:input"` on init and converts events to `%Payload{}` structs
- Review-resolved files re-enter via `{:review_resolved, %{path, watch_dir, tmdb_id, tmdb_type, pending_file_id}}`
- Detection and processing run at independent rates — Broadway controls concurrency

### Consequences

* Good, because file processing starts immediately on detection — no polling interval
* Good, because the Producer is stateless (no database queries, no claim/release logic)
* Good, because multiple Watchers can broadcast independently without coordination
* Good, because the review flow uses the same PubSub input — one entry point for all pipeline work
* Bad, because PubSub messages are not persisted — if the pipeline is down when a file is detected, the event is lost (mitigated by the scan feature, which re-detects all untracked files)
