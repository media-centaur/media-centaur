---
status: accepted
date: 2026-10-21
---
# A person has a page

Amends UIDR-046 (rule 5: the page card no longer opens in place; rule 1: the Feed's glyph takes its grade). Design: `docs/superpowers/specs/2026-10-20-person-page-design.md`; mockups under `docs/superpowers/specs/2026-10-19-person-page-mockups/` (direction B, round 3). Plan: `docs/superpowers/plans/2026-10-21-person-page.md`.

## Context and Problem Statement

A friend's activity and the reader's settings for them lived inside a grid card that opened in place: opening reflowed the grid, the settings sat in a foot under one-line act rows that showed none of a review's words, and nothing had an address — a rail press landed on `?person=<card id>`, a second kind of navigation state beside the route. And the Feed, by design (UIDR-038), leaves watched activity out, so the app never said what a person is watching lately.

## Decision Outcome

The Social page has two projections of one activity list: by action over time (the Feed) and by person folded per title (the person card). **The person page is the second projection in full for one person, at an address.**

1. **The address.** `/social/friends/<npub>` for a friend or a member, `/social/friends/you` for the reader: a third live action on the Social LiveView. The grid card's head and the rail card's head are links to it. A key nobody known holds returns to Friends with a flash; a hex key resolves and patches to the npub, so a page has one address.
2. **The fold.** One row per title, newest act first: the newest act's verb, every act's glyph after it at its grade, the title and year, the episode's name on a series, the review's words in full, the time of the newest act. Watched rows are in: a series is one row at its latest episode (the store holds one watched row per person per title; the next episode replaces it) and rises as each episode lands. Never one row per episode. The fold is one representation: the card's strip item and the page's row are the same `FeedEntry` (`SocialLive.People`); `Act` is gone.
3. **One row.** The Feed row draws both surfaces from one view-model: the author optional (no tile and no name on the page), the glyphs a list at grade, the episode, the toolbar's facts one value per title (`ToolbarSlots`). The Feed's glyph therefore takes its grade, the one glyph in the app that did not.
4. **The reader's view.** A Settings-kit card beside the rows, *Your view of <name>* (`Components.Social.ReaderView`): Name with Rename over the name it masks, Show their picture, Colour, Hide as a switch, the foot with the key, the provenance and Remove friend (a friend only). The card never pushes the rows down: at 440 beside them past the Friends grid's fold, under them below it. The reader's page has no card; a line points to Settings → Social.
5. **Hidden keeps meaning off everything.** A hidden person's rows are not loaded; their page is the head and the card with Hide on over a line that says so.
6. **Two nav zones.** The back row and the rows as a tree (`person_rows`), the card's controls as a vertical walk (`person_view`); DOWN past the last row enters the card, UP from its top returns.

### Consequences

* Good, because a person has one place, reachable by link, refresh and the sidebar's URL memory.
* Good, because the page shows what a person is watching, which no surface did.
* Good, because the row, the fold and the toolbar's slots exist once each; the card lost a third of its markup and one view-model module.
* Bad, because the page is two nav zones side by side on a TV; the card's controls are a vertical walk, the swatches one press each.
* Bad, because the Friends grid's card no longer answers a press in place; the page is one navigation away.

## Anti-patterns

* **Doubled posters** — an acts strip over the rows, or two rows for a watched-and-reviewed title.
* **An episode diary** — one row per episode.
* **Settings over activity** — the card before or above the rows.
* **Two addresses** — a query parameter or an opened set that says which person is open, or the same page under a hex key and an npub.
* **A second row builder** — a copy of the row that pattern-matches a strip item.
