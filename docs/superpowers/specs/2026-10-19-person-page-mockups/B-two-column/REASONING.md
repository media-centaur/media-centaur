# B — two columns: them on the left, you on the right

**Style.** The Friends tab's full-width opt-out, as the grid has. Same head, strip, rows and card as A, placed side by side: the activity in a fluid left column, the settings card at 440 on the right, sticky, folding under the grid's 1700 breakpoint to one column.

**Decisions.**
- The key and provenance move out of the head into the card's foot, since the card is where the reader's relation to the person is stated.
- Posters at 110 so eight fit the narrower column at 1920.
- The Name row stacks (label over field) to fit the card's width.

**Requirements.** The same as A: one page per person, the override card, the reader's page (acts alone, the right column empty or the pointer line), members without Remove friend.

**Trade-offs.**
- Gains: both halves visible without scrolling on a desk; Hide and Remove are one glance away.
- Sacrifices: the settings share the page's first screen with the activity at equal weight, which cuts against *their activity before your settings*. Two nav zones side by side on a TV. A sticky card beside a long list is a layout the app has nowhere else.

## Round 2 — the activity half is the Feed for one person

The owner liked the two columns and asked where the review text went. The act rows said *reviewed Sintel ♥* and nothing of what Nick wrote, which the Feed already shows in full. So the activity half becomes **the Feed scoped to this person**: the Feed row (poster at 80×120, the verb with its sentiment glyph, the title and year, the review in full, the time at the edge, a hairline between rows) without the identity tile, since the page is one person. Watched rows join it here, which the Feed leaves out.

- `feed.html` (B2): the head, then the feed rows. The strip is dropped: the rows carry the posters, so a strip above them would show every poster twice.
- `strip-and-feed.html` (B3): the strip kept above the feed rows as the glance summary the grid card gives, at the cost of the doubled posters.

## Round 3 — the series they are watching

The owner chose B2 and asked where the series went: the Feed leaves watched rows out (UIDR-038), the grid card's strip shows one poster, and so the app never says *Nick is watching One Step Beyond lately*, which is the most interesting thing a person's page can say. The data already holds it in the right shape: one watched row per person per title, and finishing the next episode replaces that row (`Activities.watched/2`), so a series is one row at its latest episode and never one row per episode.

Including watched rows raises the question the Feed sidesteps by dropping them: a movie watched and then reviewed is two rows in the store (one per person, title and kind). One row per action, the Feed's rule, would show that movie twice on the person's page. So the page folds the way the grid card already does (`SocialLive.People`): **one row per title**, the newest act's verb, every act's glyph after it in the card's order, the review's words when there is a review, the time of the newest act.

- `feed-with-series.html` (B4): B2 refolded per title, with the series rows in. The row is the Feed row's anatomy; the verb is the app's existing words for an episode watch (`watched S01E07 of`, `Format.episode_label/2`), and the episode's name sits in the words slot where a review shows its text. Sintel reads *reviewed ♥ 👁*, watched and loved. Pioneer One is the edge: reviewed earlier and still being watched, so the newest act is the episode (*watched S01E03 of*, the eye then the opinion glyph), with the episode name and the review's words both under the title. A series being watched rises to the top as each episode replaces its row, which is what *lately* means here.

No new words, no new row shape, no per-episode history. The Feed itself stays as it is; the row component takes an act rather than an activity on this page.
