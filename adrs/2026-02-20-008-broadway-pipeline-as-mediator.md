---
status: accepted
date: 2026-02-20
---
# Broadway pipeline as mediator with pure-function stages

## Context and Problem Statement

Video files need to be processed through multiple steps: parsing filenames, searching TMDB, fetching metadata, downloading images, and ingesting into the library. These steps must run concurrently across many files, handle failures gracefully, and maintain idempotency. The orchestration logic must live somewhere — either distributed across domain resources (reactive/event-driven) or centralized in a coordinator.

## Decision Outcome

Chosen option: "Broadway pipeline as active mediator with pure-function stages", because Broadway provides battle-tested concurrency control (configurable processor count, partitioning, batching) while keeping the processing logic in simple, testable pure functions.

**Architecture:**
- Broadway orchestrates — it calls services, gathers data, and hands results to the library
- Domain resources are passive — they never trigger pipeline behavior through state changes
- Each stage is a pure-function module that takes a `%Payload{}` and returns `{:ok, payload}`, `{:needs_review, payload}`, or `{:error, reason}`
- Stages: Parse → Search → FetchMetadata → DownloadImages → Ingest
- Concurrency: 15 processors partitioned by file path, 1 batcher for serialized PubSub broadcasts

**Idempotency guarantees:**
- Already-linked files are skipped before processing
- Entity deduplication via TMDB `Identifier` unique constraint
- Race-loss recovery: loser destroys its orphan entity and uses the winner's
- All child records use upsert patterns

### Consequences

* Good, because Broadway handles backpressure, batching, and failure isolation out of the box
* Good, because pure-function stages are trivially testable — no Broadway topology needed in tests
* Good, because the mediator pattern keeps domain resources free of orchestration concerns
* Bad, because the pipeline is a single point of coordination — if Broadway is misconfigured, all processing stops
