# Discovery › Feed: friends' actions, one entry each

**Date:** 2026-09-11 · **Status:** design approved (UIDR-038, ADR-067);
not implemented. Mockups in `2026-09-11-discovery-feed-mockups/`
(round 1: `1-person-first-post`, `2-title-row-author-lead`,
`3-two-weights`; round 2: `A-poster-left-row` **chosen**,
`B-sentence-then-card`; briefs `BRIEF.md`, `BRIEF-2.md`). Model for the
behavioural decisions: Bluesky's timeline — not its rendering.

## Glossary

| Term | Meaning |
|---|---|
| **Feed** | The Discovery tab at `/discovery`, the page's default: friends' actions, newest first, flat, one entry per action. Replaces the Recommendations tab. |
| **Action** | One thing one friend did to one title at one moment. Two kinds exist on the feed: a recommendation and a listing. (The stored record is still an **activity**; an action is what the record describes. Not "act".) |
| **Recommendation** | An action with a sentiment, Like or Love, and an optional note. Verb: "recommended". |
| **Listing** | An action: the friend put the title on their watchlist — their rung first reached List or above. Verb: "wants to watch". No note, no sentiment. Replaces the shared *tracking* act (ADR-067). |
| **Entry** | The feed's unit: one action, rendered. Where it could be confused with a library entry (user copy for an entity), say *feed entry*. |
| **Toolbar** | The row of verbs under an entry's text, visible only while the entry is hovered or holds the cursor. |
| **Verb** | A control the reader can use on an entry: List, Download, Ignore. Verbs live in the toolbar and the title modal, never on the entry body. |
| **Window** | The newest N entries the feed shows before *Show older*. |
| **Withdrawal** | A friend deleting their own action; removes the entry. Dropping a title below List withdraws its listing. |

## Problem

The Recommendations tab (UIDR-031) was nearly empty with a small roster,
and the one other forward-looking thing a friend does — listing a title
they want to watch — was a text row on their card. The row was
title-first, with who and when as the smallest text on it, plus pennants,
state markers and a synopsis around the title.

## Design objectives

1. **Signal over volume.** Reads at three friends and at thirty.
2. **Three things per entry.** Name, action, title identification. Nothing
   else on the body.
3. **Time as structure.** Newest first is the whole time axis.
4. **One anatomy.** A listing and a recommendation differ only by the note
   line.

## What the user sees

**The tab.** *Feed* is Discovery's first tab and its default route. Its
count is the number of entries in the window. Watchlist and Friends are
unchanged in position.

**An entry** (mockup A). A glass card, 8px below the previous one. Poster
at 48×72 on the left. To its right, line 1: the friend's name in medium
weight, the verb in the secondary tone, a rose heart after "recommended"
for Love only, then a separator and the relative time ("12m ago", "2h
ago", "6d ago", "3w ago"). Line 2: the title's name, semibold, with the
year beside it. Line 3, recommendations with a note only: the note,
clamped to four lines; the full text is in the modal. A listing's two
lines sit centred against the poster at rest.

Not on the entry: pennants, state markers, synopsis, type badge, avatar,
any colour other than the heart.

**The toolbar.** A fixed 20px seat at the bottom of the text block, empty
at rest, so an entry is the same height hovered or not. On hover, or when
the entry holds the keyboard/gamepad cursor, it shows, left to right:

| Verb | At rest state | What it does |
|---|---|---|
| **List** (bookmark) | Outline "List"; filled "Listed" when the title is on your list; "Following" as a non-toggle at Follow and above (UIDR-036 bookmark rule) | Toggles the bottom rung |
| **Download** (arrow) | "Download"; replaced by plain state text "Downloading" with a 3px hairline while a plan runs, "In library" when owned | Starts the one-click plan |
| **Ignore** | Word only, last | Sets the Ignored rung; every entry for the title leaves; the existing Undo toast |

Clicking anywhere else on the entry opens the title modal, where every
other verb lives. The friend's name is not a link.

**Order and repetition.** One entry per action, newest first. Two friends
recommending one title are two entries. One friend recommending, then
listing, a title minutes later is two adjacent entries. Nothing groups,
nothing re-sorts.

**What is not in the feed.** Watched actions (the Friends card keeps its
Recently watched strip). Your own actions (the You card). Actions by
someone no longer on your roster. Any title at the Ignored rung.

**End of the window.** A quiet *Show older* control, the History archive
idiom.

**Empty states** (UIDR-034). No relay or no friend: the current diagnosis
and its two actions. A connected roster that has done nothing yet: one
sentence saying what will land here — recommendations and titles friends
want to watch.

**Elsewhere, because tracking becomes listing (ADR-067).** The bell
pennant becomes a bookmark on every other title surface. The Friends
card's Tracking shelf becomes *Wants to watch*; its presence line says
"wants to watch Sample Show". Settings → Social's *Share tracking* toggle
becomes *Share your watchlist*, with its description saying a title you
list is shared and one you drop is withdrawn.

## Acceptance criteria

- [ ] `/discovery` opens the Feed tab; the tab count equals the entries in the window.
- [ ] Two friends acting on one title produce two entries; one friend recommending then listing produces two adjacent entries.
- [ ] Entries are ordered by action time, newest first, with no grouping and no day dividers.
- [ ] A listing entry shows exactly: poster, name, "wants to watch", relative time, title, year.
- [ ] A recommendation entry adds the note when present and a rose heart only for Love; Like adds nothing.
- [ ] Watched actions, own actions and former friends' actions never appear.
- [ ] No pennant renders on any feed entry; pennants still render on the Watchlist row and in the title modal.
- [ ] The toolbar is invisible at rest and visible on hover; an entry's height is identical in both states.
- [ ] List toggles List/Off on a title at or below List and reads "Following" without toggling at Follow or above.
- [ ] Download reads "Downloading" while a plan is running and "In library" when the title is owned.
- [ ] Ignore removes every entry for that title, the count follows, and Undo restores them.
- [ ] A friend withdrawing a recommendation or listing removes the entry.
- [ ] A listing is broadcast when a title first reaches List or above and withdrawn when it falls below, only while Share your watchlist is on.
- [ ] The empty state diagnoses no relay or no friends separately from a connected roster that has done nothing yet.
- [ ] The Friends card, the pennant and the Settings toggle say listing / wants to watch / your watchlist, never tracking.

## Anti-patterns

- **Wall of watching** — watched actions never appear as a timeline.
- **Title-first row** — an entry whose first line is the title reads as a list annotated with names.
- **Grouped rows** — one row per title, re-sorted when the next friend acts.
- **State as decoration** — badges, chips, markers or pennants on the entry body. State appears only as the toolbar's own state.
- **Social-network chrome** — avatars, handles, replies, reposts, counts.
- **Hover jump** — a toolbar that changes the entry's height.
- **Day dividers** — the sort order is the time axis.
- **Two features** — a listing rendered as a different component from a recommendation. One anatomy; the note is the only difference.

## Input methods

The design defines the keyboard/gamepad shape (mockup A, the two state
blocks): the ring on the entry, Enter opens the title, RIGHT steps into
the toolbar's first verb, LEFT returns, the rows zone is a TREE as the
Ignore sub-item made it. Per the standing rule for iteration-phase
surfaces the feed **ships mouse-only**; the hardening pass wires the nav
graph once the layout stops moving.

## Deferred

- The friend's name as a link to their card.
- Per-friend filtering of the feed.
- A second clause on an entry when other friends acted on the same title
  ("Cleo agrees"), if the signal turns out to be missed.
- Reviewing the ignored list (already deferred by the ignore design).
- Keyboard and gamepad wiring (hardening pass).
- The Discovery page width at 4K (projections campaign follow-up).

## Records

- [UIDR-038](../../../decisions/user-interface/2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md) — this design. Supersedes the feed half of UIDR-031; amends UIDR-036 and UIDR-037.
- [ADR-067](../../../decisions/architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md) — kind 32163 Listing replaces 32162 Tracking on the wire.
- To follow with implementation: `docs/social-protocol.md` (new kind, retired kind), the wiki *Social* page (Feed, Friends, Sharing sections), `docs/social.md`, `docs/GLOSSARY.md` (Feed, Action, Listing, Entry qualifier, Ignored's effect now "keeps the title off the Feed").
