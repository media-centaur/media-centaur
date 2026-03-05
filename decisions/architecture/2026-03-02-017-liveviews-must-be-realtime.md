---
status: accepted
date: 2026-03-02
---
# All LiveViews must update in real time via PubSub

## Context and Problem Statement

The Review LiveView (`/review`) did not update in real time when new files arrived for review. The pipeline's Search stage creates PendingFile records via `Intake.create_from_payload/1`, but no PubSub event was broadcast afterward, so the ReviewLive only learned about *removals* (`{:file_reviewed, file_id}`). New files were invisible until the user manually reloaded the page.

Every other LiveView in the application (Library, Dashboard, Operations) subscribes to PubSub and updates in real time. This inconsistency made Review the only page that could show stale data.

## Decision Outcome

Chosen option: "Every LiveView must subscribe to PubSub and handle updates in real time", because a media center dashboard that requires manual refreshes defeats the purpose of a live interface.

The pattern, already established in LibraryLive and DashboardLive, is:

1. **Subscribe in mount** — inside `connected?(socket)`, subscribe to the relevant PubSub topic(s).
2. **Debounce rapid updates** — when a batch of events arrives in quick succession (common during pipeline processing), cancel-and-reschedule a reload timer (typically 500ms) so only one data fetch occurs.
3. **Handle the reload message** — fetch fresh data from the domain and reassign.

Any code path that mutates data visible in a LiveView must broadcast to the appropriate PubSub topic. The broadcaster does not need to know which LiveViews are listening — it only ensures the event is published.

### Consequences

* Good, because users see new review files appear immediately without page reload
* Good, because the pattern is consistent across all LiveViews — no special cases to remember
* Good, because debouncing prevents unnecessary database queries during batch processing
* Neutral, because each new data-producing code path must remember to broadcast — but this is already the established convention and is documented in CLAUDE.md
