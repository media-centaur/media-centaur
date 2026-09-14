---
status: accepted
date: 2026-09-05
---
# Follow-up pill and condition dot — the sidebar's two badge idioms

## Context and Problem Statement

The sidebar rendered one idea three ways: the Status count cleared on visit, the Review count persisted until the files were handled, and Incoming showed nothing even with a draft plan waiting for approval.

## Decision Outcome

1. **Follow-up pill** — a count of items on that page waiting on a decision from the user. It persists until the items are handled, and each source defines handling: approve or discard a plan, review a file, look at an incident. One component (`Components.FollowUpPill`), one variant (error), one size, one placement: the row's end in the expanded rail, the icon's top-right corner in the collapsed rail. Sources: Incoming (plans in `ready`), Review (pending files and mappings), Status (unseen incidents).
2. **Condition dot** — something is wrong right now; persists until resolved. Status only (error buckets), at the icon's bottom-right so it never overlaps the pill.
3. The pill is domain state, not attention tracking: it counts what is waiting regardless of which page or modal is open. A new page with pending decisions adds a source to `MediaCentaurWeb.ShellBadges` and one `relevant?/1` clause, never new chrome.

### Consequences

* The Review count changed from blue to red. If it proves too loud, the remedy is one non-error variant for all three sources, never a second colour.
