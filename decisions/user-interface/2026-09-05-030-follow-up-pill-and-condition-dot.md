---
status: accepted
date: 2026-09-05
---
# Follow-up pill and condition dot — the sidebar's two badge idioms

## Context and Problem Statement

The sidebar rendered one idea three ways: the Status count cleared when
the page was visited, the Review count persisted until the files were
handled, and Incoming had nothing even when a draft plan sat waiting for
approval. Each new page with pending decisions was about to invent its
own chrome.

## Decision Outcome

Chosen option: two named idioms and no others.

* **Follow-up pill** — a count of items on that page waiting on a
  decision from the user. Persists until the items are handled, and each
  source defines handling: approve or discard a plan, review a file,
  look at an incident. One component
  (`MediaCentaurWeb.Components.FollowUpPill`), one variant (error), one
  size, one placement rule: the row's end in the expanded rail, the
  icon's top-right corner in the 52px rail. Sources today: Incoming
  (plans in `ready`), Review (pending files + mappings), Status (unseen
  incidents).
* **Condition dot** — something is wrong right now; persists until
  resolved. Status only (error buckets), at the icon's bottom-right so
  it never overlaps the pill.

The pill is domain state, not attention tracking: it counts what is
waiting regardless of which page or modal is open. A new page with
pending decisions adds a source to `MediaCentaurWeb.ShellBadges.Counts`
and one `relevant?/1` clause — never new chrome.

### Consequences

* Good, because every "waiting on you" reads the same and a future page
  has one thing to add.
* Good, because the pill survives the collapsed rail, which used to clip
  the Review count.
* Bad, because the Review count changed from blue to red; if it proves
  too loud in daily use the remedy is one non-error variant for all
  three, never a second colour.
