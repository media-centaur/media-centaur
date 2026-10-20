# Social › Friends: the person page

**Date:** 2026-10-20 · **Status:** design approved, plan to follow.
Mockups: `2026-10-19-person-page-mockups/`, direction B, round 3
(`B-two-column/feed-with-series.html`, B4). Records to write: a UIDR
for the person page; a dated amendment to UIDR-046 rule 5.

## Glossary

Existing terms are in `docs/GLOSSARY.md`: *Feed*, *act*, *social glyph*,
*grade*, *rung*, *friend*, *member*, *hidden*. The *feed row*, the *person
card*, its *acts strip* and the *identity tile* are UIDR-046's. This
design adds:

| Term | Meaning |
|---|---|
| **Person page** | One page per known person, the reader included, at a stable address: the person's activity folded per title on the left, the reader's view of them on the right. "Profile" is not used: within Social it already means the published profile and, at the front door, a viewer profile. |
| **Reader's view** | The settings a reader keeps about one person and that nobody else sees: the name, whether their picture shows, the colour, and whether they are hidden. Drawn as one settings card headed *Your view of \<name\>*. |
| **Fold** | The projection of a person's activity as one row per title, newest act first, every act on the title behind it. The person card's strip already folds this way; the person page shows the fold in full. |
| **Toolbar slots** | The two resolved positions of a row's toolbar, List and Download, and the three facts they come from: the rung, library ownership, the acquisition state. Facts about the reader and a title, never about an action. One value per title, carried by every row for it. |

## Problem

A friend's activity and the reader's settings for them live inside a grid
card that opens in place. Opening reflows the grid, the settings sit in a
foot under the act rows, and nothing has an address: a refresh or a rail
press lands on `?person=<card id>`, a second kind of navigation state
beside the route. The opened card's rows name each act in one line and
show none of a review's words, which the Feed shows in full. And the
Feed, by design (UIDR-038), leaves watched activity out, so the app never
says the one thing a person's page should: what they are watching lately.

Values, agreed at Gate 1: one place per person; their activity before the
reader's settings; nothing drawn that the kit does not already draw.

## The core idea

The Social page has two projections of the same activity rows: by action
over time, the Feed; by person folded per title, the person card. The
person page is the second projection shown in full for one person, at an
address. Every decision below follows from that.

## Decisions

### The address

- `/social/friends/<npub>` for a friend or a member; `/social/friends/you`
  for the reader. A third live action on the Social LiveView, so the tabs,
  the activity list, the subscriptions and the title detail host are the
  page's as they are the Feed's.
- The grid card and the rail card are links to the page. A card is no
  longer a button that opens in place; middle-click and right-click work.
- `?person=`, the opened set and the open-in-place press are removed. The
  route is the one address.
- A key nobody known holds redirects to Friends with a flash.

### The fold

- The per-person, per-title fold that builds the card's strip also builds
  the page's rows. One fold, two projections. The page never re-folds and
  never uses the Feed's per-action builder.
- One row per title: the newest act's verb, every act's glyph after it in
  the card's order (the opinion, the eye, the bookmark), each at its
  grade; the title and year; on a series, the episode's name; the review's
  words in full when there is a review; the time of the newest act.
- Watched rows are in. A series is one row at its latest episode, since the
  store holds one watched row per person per title and the next episode
  replaces it. A series being watched rises to the top as each episode
  lands. There is never one row per episode.
- The edge: a series reviewed earlier and still being watched reads
  *watched S01E03 of*, the eye then the opinion glyph, the episode name and
  the review's words both under the title.
- The verbs are the app's existing words (`ActivityWords`). No "watching"
  verb is added.

### The row

- The Feed row is the app's list row and the page's row is the same
  component. Its view-model widens so one struct serves both: the author
  becomes optional (no identity tile and no name on the page, which is one
  person); the single sentiment becomes a list of glyphs each at its
  grade; the episode joins it; the toolbar slots become one value.
- The Feed builds one row per action with one glyph. The page builds one
  row per title with every glyph.
- The Feed's glyph takes its grade. It was the one glyph in the app drawn
  without one; the row now draws every glyph the same way (Grade's own
  rule: every surface that shows one). A heart three friends share is gold
  on the Feed as it is on a card.
- The row keeps its toolbar (List, Download; Ignore on a friend's row),
  its press (the title modal speaking for the newest act), and its nav
  contract (UP and DOWN walk rows, RIGHT steps along the verbs).

### The reader's view

- One settings card composed from the Settings kit, at 440 wide, sticky
  beside the rows, folding under them below the grid's 1700 breakpoint.
  Headed *Your view of \<name\>* with the line *Only you see these. They
  change nothing for \<name\> or anyone else.*
- Rows, in order: **Name**, a field with Rename, the published name (else
  Unnamed) as its placeholder; **Show their picture**, a switch; **Colour**,
  the hue swatches with Theirs first; **Hide**, a switch (the same event
  the hidden group's Show sends).
- The foot: the short npub and the provenance (*added Sep 3*, or *on
  \<relay\>*) at the left; **Remove friend** at the right, on a friend's
  page only. A member's page has the card without it.
- The card's foot on the person card is removed with the opened state. The
  card is the head and the strip, nothing else.
- The reader's page has no card. One line under the rows: *Your name,
  picture and colour are under Settings → Social.*

### Hidden people

- A hidden person has a page, reached from the hidden group. Hidden keeps
  meaning off everything: their rows are not loaded, so the page shows the
  head and the card with Hide on over an empty list that says *Hidden.
  Their activity is kept off the Feed, titles and Friends. Switch Hide off
  to see it here.*

### Empty states

- A known person with no acts: the head and the card over one line,
  *Nothing yet.*
- The reader with no acts: the head over *Nothing yet* and the pointer
  line.

### Keyboard and gamepad

- The page is two zones: the rows as a tree, as the Feed's, then the card's
  controls as on Settings. Left at the rows' edge returns to the sidebar.
  Back from the page's back row returns to Friends.

## What changes on existing surfaces

- **Friends grid**: the card no longer opens in place; it links. The
  hidden group and the add-friend form are unchanged.
- **Feed rail**: the card links to the page instead of patching
  `?person=`.
- **Feed**: the glyph after the verb is drawn at its grade. Nothing else.
- **Person card**: loses `opened?`, the act rows and the foot.
- **UIDR-046 rule 5**: amended. The press on a page card navigates to the
  person page; the opened state and the foot are retired.

## Acceptance criteria

- [ ] Every known person, the reader included, has a page at a stable
      address that survives reload and the sidebar's URL memory.
- [ ] A grid card, a rail card and the You card are links to the page.
- [ ] A title with several acts by one person is one row on their page,
      carrying every act's glyph at its grade and the review's words.
- [ ] A series is one row at its latest episode with the episode's name,
      and moves to the top when the next episode is finished.
- [ ] A reviewed series still being watched shows both the episode name
      and the review's words under the title.
- [ ] Rename, Show their picture, Colour and Hide take effect on the page
      and everywhere the person is drawn, without leaving the page.
- [ ] Remove friend returns to Friends and the person is gone from the
      grid; a member's page has no Remove friend.
- [ ] The reader's page shows the reader's acts in the second person and
      no card.
- [ ] A hidden person's page shows the card with Hide on and the hidden
      empty state; switching Hide off fills the rows.
- [ ] A key nobody known holds redirects to Friends.
- [ ] The Friends grid card no longer opens in place; `?person=` is gone.
- [ ] The Feed's glyph is drawn at its grade.
- [ ] Rows, their verbs and the card's controls are reachable by keyboard
      and gamepad; the row's toolbar shows on focus as on hover.
- [ ] Every component touched has its story updated in the same change.

## Anti-patterns

- **Doubled posters**: no acts strip above the rows, no second row for a
  watched-and-reviewed title. One picture per title (UIDR-046).
- **Episode diary**: never one row per episode. The page says what they
  are watching, not every sitting.
- **Settings over activity**: the card never pushes the rows down. Their
  activity is the page; the reader's view sits beside it.
- **Redrawn kit**: the row is the Feed row, the card is the Settings card,
  the switch is the switch, the swatches are the swatches.
- **Two addresses**: no query parameter, opened set or client state that
  says which person is open. The route says it.
- **A second row builder**: the page never pattern-matches the strip's
  item into a copy of the row. One struct, one component, two builders.

## Deferred

- A larger head tile (stays at 48, the grid card's).
- A "watching" verb.
- Loading hidden people's rows for their page.
- Per-episode history.
- A link from Settings → Social to the reader's page.

## Records

- UIDR-038 (watched off the Feed): unchanged.
- UIDR-041 (settings kit): the card composes from it.
- UIDR-046 (Feed, rail, person card): rule 5 amended as above; rule 5's
  "a press opens it in place" retired.
- UIDR-047 (name, picture), UIDR-048 (hue): their controls move to the
  page's card; the rules stand.
- UIDR-051 (Social page): the tab strip gains no tab; the page is under
  Friends.
- New UIDR: the person page.

## Testing

- The Social page's LiveView tests gain the person action: the address
  for a friend, a member, the reader and an unknown key; the fold (one
  row per title, the series edge, the reviewed-and-watching edge); every
  card control; Remove friend; the hidden empty state.
- The opened-card tests retire with the behaviour they guarded; what
  they asserted about the controls (rename, picture, colour, hide, remove)
  is asserted again on the page. ADR-027 covers parser and pipeline
  regression tests and does not apply here.
- Component tests: the row with and without an author, with several
  glyphs at grades, with an episode; the card for a friend, a member, a
  hidden person.
- Stories: the row's new variations; the person card without its opened
  variations; the new card component; the page's empty states.
- Page smoke test: the three addresses.
- The input system's bun tests: the page's zone layout.
