# Social projections: friends carry the shelves, the feed is recommendations

**Status:** approved 2026-09-06 (UIDR-031). Mockups in
`2026-09-06-social-projections-mockups/` (Friends: `1-friend-cards-poster-strip`
chosen; feed: `feed-3-grouped-by-title` chosen; the others record the
directions rejected and why).

## Glossary

| Term | Meaning |
|---|---|
| **Activity** | One signed statement by one signer about one title (kind recommendation / watched / tracking). Unchanged from the 2026-09-05 design. |
| **Shelf** | A person's current set of activities of one kind, one entry per title: their *watched* shelf, *tracking* shelf, *recommended* shelf. Derived from the addressable records; nothing stored. |
| **Presence line** | A person's latest activity of any kind, as a sentence: "watched S02E05 of Sample Show", "recommended Movie B", "started tracking Movie A", plus relative time. |
| **Person card** | The Friends tab's unit: one friend, or You, with their presence line and three shelves. |
| **You card** | The person card for this install's identity: what has been broadcast, i.e. what friends see. |
| **Recommendation row** | One title on the Recommendations tab with every friend who recommended it. |

## What changes for the user

* The first Discovery tab is **Recommendations** again: friends'
  recommendations, one row per title, newest recommendation first. No
  Incoming/Yours switch.
* The **Friends** tab is person cards: You first, then friends by latest
  activity, friends with nothing shared last. The add-friend form and the
  Settings → Social pointer remain below the cards.
* A person card: header (initial avatar, name as the title, presence line
  right); *Recently watched* strip of five posters newest first with an
  "all N" tile that grows the strip in place; Tracking and Recommended
  text rows, up to three names then "N more", Recommended with the
  sentiment pill; footer with the elided key, added date and Remove
  friend. The You card has a primary-tinted border, the subtitle "How
  friends see you", and no footer.
* Every poster and title name opens the title modal with that activity's
  facts (kind, episode, sender, time, own?), so Delete on an own activity
  works from the You card as it did from Yours.

## Diff against the code

* `DiscoveryLive`: `live_action :feed` → `:recommendations`; `feed_scope`,
  `scoped_feed/2`, `scope_count/2`, the `feed_scope` event and the `:own`
  empty state go. `@feed` stays the full enriched activity list (every
  kind, every actor); `Logic.recommendation_rows/1` groups friends'
  recommendations by title and `Logic.person_cards/2` folds the list into
  cards. `?title=` gains an optional `activity=` so a card's poster opens
  *that* activity, not the title's newest recommendation.
* `TitleRow`: `notes` (attributed) beside `secondary`; the Feed passes
  `named?: true`.
* New `Components.Discovery.PersonCard` with a story; `RosterBlock`
  shrinks to the add-friend form and guidance.
* `ActivityWords.presence/3` gives the presence sentence.
* Wiki: Friends / Recommendations pages; `docs/social.md` Feed paragraph.

## Deferred

Per-friend page behind "all N"; per-friend filtering of recommendations;
posters for tracking; any feed filter row.
