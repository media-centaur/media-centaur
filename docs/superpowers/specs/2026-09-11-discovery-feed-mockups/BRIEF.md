# Discovery › Feed — mockup brief (2026-09-11)

Goal: brainstorm how one **feed entry** renders. The Feed replaces the
Recommendations tab. Model for every behavioural decision: **Bluesky**.
Not its rendering — its model.

## Vocabulary (use these words, no others)

| Term | Meaning |
|---|---|
| Feed | The Discovery tab: friends' acts, newest first, flat, one entry per act. |
| Act | One thing one person did to one title at one moment. Two kinds. |
| Entry | The feed's unit: one act, rendered. |
| Recommendation | Act with a sentiment (like / love) and an optional note. Verb: "recommended". |
| Listing | Act: the person put the title on their watchlist. Verb: "wants to watch". No note, no sentiment. |
| Mast / pennant | Flags flying inward from the right edge of a title surface: love (rose), like, watched, bookmark (was bell) — each names the friends. Shows *every* friend's act on that title, so on an entry it is the "Cleo agrees" signal. |
| Markers | Quiet text after the title meta: "In library", "On your list", "Planning", "Downloading". |
| Ignore | The entry's one verb: quiet text revealed on hover/cursor, sets the title to the Ignored rung, hides every entry for that title. |

## Decisions already taken (do not re-open)

* One entry per act, flat reverse-chronological. A title can appear more
  than once (two friends; or one friend recommends then lists it minutes
  later — show both cases).
* Person and time visible on every entry. Sentence voice:
  "Nick recommended · 6d ago", "Cleo wants to watch · 2h ago".
  Relative times as the app formats them: "12m ago", "2h ago", "6d ago",
  "3w ago". No day dividers.
* Watched acts and own acts are NOT in the feed.
* Whole entry is the click target and opens the title modal. Nothing
  else on the entry is a link except Ignore.
* End of the window: a quiet "Show older" control, the app's archive idiom.
* Page: `max-width: 768px`, the Discovery tab strip above
  (Feed · Watchlist · Friends with counts). Sidebar not needed.

## House rules (the app's design values — violations get rejected)

* Dark only, cool slate (hue 264), system fonts. `base.css` carries the
  palette, glass surface, row anatomy, pennant (`.mast`, `.pen`, `.pen.love`),
  thumb (`.thumb`), avatar (`.avatar`), tabs. Reuse them; extend in the
  mockup's own `<style>`.
* Colour is signal only. The rose love pennant is the ONE warm hue. No
  chip palette, no per-person colours beyond the avatar tint already in
  `.avatar`, no coloured edge/accent bars, no badges for state (state is
  quiet text).
* Text read as text never dimmer than 55% white. 40% only for glyphs and
  separators.
* Linear.app calm. No entrance animations. Hover = subtle surface lift only.
* Generic placeholder titles ONLY: Sample Show, Movie A, Movie B, Show B,
  Sample Film, Harbor Lights, The Long Field (invented). Friends: Nick, Cleo,
  Bob, Sam. Notes are short and plausible.
* Overview text (a title's synopsis) is shown only when there is no note
  — the row idiom today. Keep it to one or two lines.

## Content every mockup must show (same data, same order)

1. Cleo · wants to watch · Sample Show (TV · 2024) · 12m ago. Mast: Nick 👍 (Nick recommended it earlier, entry 6).
2. Nick · recommended (love) · Movie A (Movie · 2026) · 2h ago · note: "Saw it twice. The last twenty minutes are the whole film."
3. Nick · wants to watch · Movie A · 2h ago (he listed it right after recommending — the same-person-same-title case, adjacent).
4. Bob · recommended (like) · Show B (TV · 2021) · 1d ago · note: "Slow start, give it three episodes." · marker: In library. Mast: Bob 👍, Cleo 👍.
5. Sam · wants to watch · The Long Field (Movie · 2025) · 3d ago · marker: On your list.
6. Nick · recommended (like) · Sample Show · 6d ago · no note (overview shows). Mast: Nick 👍, Cleo 🔖.
7. Cleo · recommended (like) · Show B · 1w ago · note: "Fine." Mast: Bob 👍, Cleo 👍.
8. Bob · wants to watch · Harbor Lights (TV · 2023) · 2w ago · marker: Downloading.
Then the "Show older" control.

Show one entry in the hovered state with Ignore visible (entry 4), the rest at rest.

## Deliverable

`index.html` (self-contained apart from `../base.css`) and `REASONING.md`
(style, decisions, requirements mapping, trade-offs — and explicitly: how
it holds up at 3 friends and at 30, and what happens when the note is long).
