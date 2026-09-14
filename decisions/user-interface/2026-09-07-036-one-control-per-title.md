---
status: accepted
date: 2026-09-07
amended: 2026-09-14
---
# One control per title, because there is one ladder

Supersedes UIDR-035's `Remove from watchlist` clause. The Ignore rung (2026-09-09), UIDR-038 and UIDR-039 (2026-09-11) are folded in.

## Context and Problem Statement

The title detail carried two controls for one idea: watchlist verbs in the action strip and a tracking-mode strip beneath. Removing from the watchlist at Grab tore down the calendar, the wants and the tracking as a side effect, unannounced. The library detail hid the control for an untracked title, leaving an owned series no way to start.

## Decision Outcome

Listing a title and following its releases are one decision at different strengths (ADR-066), so there is one control.

1. **`Components.Title.IntentControl` replaces the tracking-mode control and both watchlist verbs.** Seven buttons in ladder order: Ignore · Off · List · Follow · Ask · Grab · Default. Off is the absence of a record; Ignore (2026-09-09) keeps friends' reviews of the title off the Feed and nothing else. The pressed rung carries `aria-pressed` and its one-line consequence.
2. **Off states that it deletes, before the click.** The consequence line is the disclosure, so no second confirmation.
3. **The control renders for a listed title** (narrowed by UIDR-039). An unlisted title offers only the bookmark of rule 5.
4. **A row wears a marker, never the control.** Rows show where a title sits and open its modal to change it. Exceptions: the bookmark, and the Feed entry's toolbar (bookmark and Ignore shortcut, UIDR-038).
5. **The bookmark toggles the bottom of the ladder only**: adds at List, removes only from List. At Follow and above it is a marker whose label says where the ladder lives. A one-click must not destroy a calendar and its wants.

### Consequences

* `Remove from watchlist` disappears as a named verb; the consequence line carries it. Off on the Watchlist tab or Coming up closes the modal.

## Amendment 2026-09-14

Rules 1, 4's bookmark exception and 5 are superseded by [UIDR-042](2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md): the seven-way strip became the bookmark and two switches, the ladder lost Ask and Default, and the bookmark removes at any rung. The premise stands — one record, one ladder (ADR-066) — and rules 2 and 3 stand as written.
