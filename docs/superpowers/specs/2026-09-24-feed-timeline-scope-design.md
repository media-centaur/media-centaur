# Discovery › Feed: own actions in the timeline, an author scope

**Date:** 2026-09-24 · **Status:** implemented 2026-09-24 (UIDR-045); plan in `../plans/2026-09-24-feed-timeline-scope.md`. Mockups in `2026-09-24-feed-timeline-scope-mockups/`
(`1-time-rail`, `2-poster-forward`, `3-editorial-list` **chosen**, with the
scope moved onto the segmented control and the rows into one list surface;
brief `BRIEF.md`). The previous round is
`2026-09-11-discovery-feed-design.md` (UIDR-038); its anatomy is kept.

## Glossary

| Term | Meaning |
|---|---|
| **Feed** | The Discovery tab at `/discovery`: every review and listing the network holds, by every author on the roster and by you, newest first, one row per action. |
| **Author** | Who made an action: a friend, by nickname, or **You**. The word a row leads with. |
| **Own action**, **own row** | An action this identity broadcast, and its row. Only what was broadcast exists: a review is always broadcast; a listing only while *Share your watchlist* is on. |
| **Scope** | The author filter on the Feed: **Everyone** (default), **Friends**, **You**. One value, in the URL as `?scope=`. Not a tab, not a preference. |
| **Segmented control** | The house pick-one pill: a glass rail with the chosen option lifted. The scope's control, and after this design one component shared with Library's type tabs and the strip chart's window. |
| **Row** (feed row) | The Feed's unit after this design: one action rendered as a row in one list surface. Replaces the per-entry glass card. Where it could be confused with a library entry, say *feed row*. |
| **List surface** | One inset glass container holding the rows, separated by hairlines. The Watch History list's idiom. |
| **Subject** | The grammatical subject of a row's sentence, which sets the verb's form: "You want to watch", "Cleo wants to watch". |
| **Withdraw** | Deleting an own action: the modal's Delete review / Delete listing. Publishes a deletion; there is no undo. |

## Problem

Own actions are excluded from the Feed by rule (UIDR-038 rule 1) and
shown only as shelves on the You card, which have no time axis. Reading
what you shared beside what friends shared means leaving the timeline.
The feed's own spec deferred per-author filtering. Visually the feed is
a strip of 48×72 glass cards in a 768px column and reads as unfinished
at 1920px.

## Design objectives

1. **One timeline.** Authorship is a filter on the feed, never a rule of it.
2. **One anatomy for every author.** An own row differs from a friend's
   row by the word You and the verb's form, nothing else.
3. **Time as structure, drawn.** The relative time in its own column so
   the axis reads down the edge.
4. **Composed at 1920px.** One list surface, not floating cards.

## What the user sees

**The Feed tab.** A segmented control at the right of the tab strip's
line: Everyone · Friends · You. Everyone is the default. The tab count is
the number of rows in the window under the current scope. The choice is
in the URL, so a refresh and the sidebar's section memory return to it.
The Feed tab's link carries the scope while the Feed is the active tab;
leaving for Watchlist or Friends and coming back through the tab strip
starts again at Everyone, because the tabs navigate to fresh mounts and
the scope belongs to the Feed's address alone.

**The list.** One inset glass surface. Rows separated by hairlines, a
56×84 poster on the left, three text lines beside it, the relative time
right-aligned in a fixed column. Line 1: the author in medium weight,
"You" in the primary colour, the verb, the sentiment glyph when a review
gives one. Line 2: the title and year. Line 3: the review text when
there is any, four lines at most. A listing's two lines sit at the top
of the row, level with the poster's top edge and the time; the toolbar
seat holds the space beneath. Own rows use the second person: "You
reviewed", "You want to watch".

**The toolbar.** Unchanged in placement and behaviour: a fixed seat,
visible on hover or cursor, the row's height constant.

| Row | Toolbar |
|---|---|
| A friend's | List · Download · Ignore |
| Your own | List · Download |

List on your own listing reads Listed; turning it off drops the title
below List, which withdraws the listing (ADR-067), and the row leaves.
An own row has no Ignore and no Delete: withdrawing is the modal's
Delete, and an own row opens the modal speaking for that action.

**Scopes.**

| Scope | Rows |
|---|---|
| Everyone | Every author's reviews and listings, interleaved by action time |
| Friends | Friends' only: the Feed as UIDR-038 defined it |
| You | Your own only |

Watched actions never appear under any scope. A title at the Ignored
rung makes no row for any author.

**Empty states** (UIDR-034), diagnosed in this order:

| Scope | Condition | Copy |
|---|---|---|
| Everyone, Friends | No relay or no friend | The existing diagnosis with its two actions |
| Everyone | Ready, nothing yet | Headline: "What you and your friends review and want to watch lands here". Body: "Each action is one row, newest first." |
| Friends | Ready, nothing yet | Headline: "What your friends review and want to watch lands here". Same body. |
| You | Nothing shared | Headline: "What you review and list lands here". Body: "A review is always shared. A title you list is shared while Share your watchlist is on." Action: Settings → Social |

The You scope needs no relay and no friend: a review creates its row
locally and publishes when a relay connects.

**Width.** The Discovery column widens from 768px to 896px for all three
tabs. Watchlist rows and Friends cards reflow; nothing else on them
changes.

**The Friends tab.** Unchanged. The You card keeps its shelves and its
subtitle; the modal opened from it keeps Delete.

## The model

Core idea: the Feed is the timeline of every action the network holds;
who authored an action is a filter, not a rule.

- **The entry rule** admits a review or a listing by an author on the
  roster or by you, on a title not ignored. The scope filters after it.
- **The scope is navigation state**: one value in the URL, read on
  `handle_params`, patched by the control, carried by the Feed tab's
  link. The section URL memory keeps it across the sidebar. Watch
  History's filters stay in assigns: a compound search with free text
  and a heatmap date is not an address. Recorded here so the two are not
  mistaken for one idiom.
- **The row's view-model** carries the author, the display name with You
  resolved, and whether the row is own; the projection resolves both and
  the row decides nothing. The verb takes a subject.
- **Delete stays in the modal.** One click on a hover toolbar, in the
  seat where Ignore sits on the neighbouring rows, would withdraw a
  broadcast irreversibly. Ignore has an undo; a deletion has none.
- **The segmented control becomes one component** for content surfaces.
  Library's type tabs and the strip chart's window picker move onto it in
  the same change; Settings keeps its kit (UIDR-041).
- **The component is renamed** from card to row, with its story.

## Acceptance criteria

- [ ] `/discovery` opens on Everyone; own reviews and listings interleave with friends' by action time.
- [ ] The control offers Everyone, Friends, You; the tab count equals the rows in the window for the current scope.
- [ ] Friends shows no own row; You shows own rows only.
- [ ] `?scope=you` survives a refresh and the sidebar's section memory; the Feed tab's link carries it while the Feed is active; a value the URL does not offer falls back to Everyone.
- [ ] An own row reads "You reviewed" / "You want to watch", You in the primary colour, with no border, tint, marker or badge.
- [ ] The relative time sits in the right column; line 1 carries no time.
- [ ] A friend's row toolbar is List · Download · Ignore; an own row's is List · Download.
- [ ] Turning List off on your own listing withdraws it and the row leaves.
- [ ] Clicking an own row opens the modal for that action, with Delete.
- [ ] Row height is identical at rest and hovered.
- [ ] Watched actions never appear under any scope; a title at Ignored makes no row for any author.
- [ ] Empty states follow the table; the You scope's empty state renders with no relay and no friend.
- [ ] Library's type tabs and the strip chart's window render from the shared segmented control with their behaviour unchanged.
- [ ] Watchlist and Friends render at the wider column, otherwise unchanged.

## Anti-patterns

- **Diary** — own watched actions in the timeline.
- **Own-row decoration** — a border, tint, marker or badge on an own row. The word is the mark.
- **Two components** — an own row rendered by a different component from a friend's row.
- **Scope as tabs** — text tabs beside the page tabs, which makes Friends two things on one line.
- **One-click withdraw** — Delete on the hover toolbar.
- **Scope as a preference** — a setting that remembers the filter. It is an address.
- Everything UIDR-038 bans: wall of watching, title-first row, grouped rows, state as decoration, social-network chrome, hover jump, day dividers.

## Input methods

As before: the Feed ships mouse-only and the hardening pass wires the
nav graph once the layout stops moving. The control's options become
nav items in that pass.

## Deferred

- Per-friend scope.
- The author's name as a link to the Friends card.
- Keyboard and gamepad wiring (hardening pass).
- The Friends card's Recently watched tiles grow at the wider column;
  check the 240px derivative at 2× scale during implementation and
  raise it if it softens.

## Records

- [UIDR-045](../../../decisions/user-interface/2026-09-24-045-own-actions-join-the-feed-under-an-author-scope.md) — this design. Amends UIDR-038 rules 1, 3, 4, 6 and 10.
- To follow with implementation: `docs/social.md` (Web layer), `docs/GLOSSARY.md` (Feed (tab), Action, Ignored; new Scope, Author, feed row), the wiki *Social* page (Feed: the scope and your own rows; Friends: Delete from an own row's modal), the `user-interface` skill's UIDR table and component inventory, the storybook.
