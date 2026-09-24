---
status: accepted
date: 2026-09-24
---
# Own actions join the Feed under an author scope

Amends UIDR-038 (rules 1, 3, 4, 6 and 10). Design: `docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md`.

## Context and Problem Statement

UIDR-038 kept own actions off the Feed and on the You card, reasoning that a feed shows what changed and a profile shows what is. The You card's shelves have no time axis, so reading what you shared beside what friends shared meant leaving the timeline. The feed itself was a strip of small glass cards in a 768px column.

## Decision Outcome

A feed is the timeline of every action the network holds; authorship is a filter on it.

1. **Own reviews and listings are rows** in the Feed, interleaved with friends' by action time. Watched stays off the Feed for every author. Only what was broadcast exists.
2. **One scope, three values**: Everyone (default), Friends, You, on the house segmented control at the right of the tab strip's line. The scope is an address (`?scope=`), kept by the section URL memory and carried by the Feed tab's link; never a preference. The tab count follows the scope.
3. **One anatomy for every author.** An own row differs by the word You, in the primary colour, and the second-person verb. No border, tint, marker or badge.
4. **The toolbar on an own row is List and Download.** No Ignore. No Delete: withdrawing is the modal's Delete, which an own row opens by naming its action. UIDR-038 rule 10 becomes: the modal, opened from the You card or an own row, is the only place to withdraw.
5. **One list surface.** Rows in one inset glass container separated by hairlines, the relative time in a right-hand column, the per-entry card gone. The Discovery column is 896px for every tab.
6. **The segmented control is one component** for content surfaces, shared by the Feed's scope, Library's type tabs and the strip chart's window. Settings keeps its kit (UIDR-041).

### Consequences

* Good, because what you shared reads in the timeline your friends read it in, and the You scope is the audit view with a time axis.
* Good, because the entry rule and the scope are separate ideas: what belongs on the Feed never changes with whose it is.
* Bad, because your listings and a prolific friend's now share one stream; the Friends scope is the way out.
* Bad, because the control's extraction touches Library and the strip chart for a change that is about the Feed.

## Anti-patterns

* **Diary** — own watched actions in the timeline.
* **Own-row decoration** — anything but the word marking an own row.
* **One-click withdraw** — Delete on the hover toolbar.
* **Scope as tabs** — Friends as two things on one line.
* **Scope as a preference** — a setting that remembers the filter.
