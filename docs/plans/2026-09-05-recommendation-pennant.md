# Recommendation pennant

Design note for the sentiment on a recommendation and the pennant that
shows it. Written 2026-09-05 before implementation; records the decisions,
not the present-tense code.

## Glossary

- **Sentiment** — how strongly a person recommends a title: `like` or
  `love`. One per recommendation. A recommendation that states none is a
  `like`.
- **Recommendation pennant** — the mark that says who recommended a title
  and with what sentiment: a flag flying inward from the right edge of the
  surface the title is on. Love is a heart on the rose fill; like is a
  thumbs up on a neutral tint.
- **Mast** — the right edge a pennant hangs from. Several pennants on one
  title stack on the same mast, love above like.
- **Named pennant** — a pennant carrying the recommender's nickname (or
  "You"). **Icon-only pennant** — the same shape with the name dropped,
  used where the surface already says who (the Feed lead).

## Core idea

A recommendation is a friend's statement about a title with a strength.
The pennant is the one rendering of "who recommended this, and how much",
and appears wherever a recommended title is on screen.

## Greenfield shape

- **Wire.** Kind 32160 content gains `sentiment`: `"like"` or `"love"`.
  Absent means like. Anything else is malformed. No version bump: readers
  ignore unknown fields, and an older reader sees a plain recommendation.
- **Row.** `activities.sentiment`, text, not null, default `like`. Nil on
  every other kind's row is not needed: the column defaults and the
  translation writes it only for a recommendation. The `Activity` schema
  types it as an enum.
- **Context.** `Activities.recommend(title, sentiment, note)`.
  `Activities.recommendations_for(refs)` returns `%{ref => [feed_row]}`,
  the same feed-row shape `list_feed/0` returns (activity, nickname,
  own?), restricted to live recommendations, one query plus one roster
  read. Own rows included, marked `own?`.
- **Web.** One function component,
  `Components.Discovery.RecommendationPennant.recommendation_pennants/1`,
  taking the feed rows for one title and `named?`. A pure
  `pennants/1` groups rows into `[%{sentiment, names, more}]`, love first,
  at most two names then `+N`, "You" for an own row.
- **Surfaces.** Feed row (icon-only), watchlist row, search result row,
  Discovery title detail modal hero, library detail modal hero. The sender
  picks the sentiment in the Recommend modal as two pennants.

## Diff against the code

| Gap | Kind | Disposition |
|---|---|---|
| Watchlist rows show provenance as the quiet `from <nickname>` marker, sourced from the row's `activity_id` alone | second representation of "who recommended" | Replace with the pennant, fed by `recommendations_for/1` for the row's ref. `activity_id` stays as the item's provenance record; it no longer drives display. |
| `Logic.row_markers/1` takes `from_nickname` | now dead | Remove the fact. |
| Search rows carry no recommendation facts | missing seam | Incoming resolves `recommendations_by_ref` per landed result set, the same way it resolves `in_library_refs`. |
| Library detail modal has no recommendation facts | missing seam | EntityModal resolves them per selection beside `tracking_status`, refreshes on activity events. |
| Recommend modal has no sentiment control | missing | Two pennant radios, like preselected. `RecommendFlow.submit/3`. |
| Arrival flash | no page-wide notification seam exists | Out of scope. |
| Home hero | the billboard is full-bleed: its right edge is the window, not a card, so the mast has nothing to hang from | Deferred until the hero has an edge of its own. |

## Scope cost

The coherent path is the query-per-surface seam rather than threading
the watchlist's `activity_id` further. It costs one context function and
one assign per surface, and buys one source of truth for every pennant.
