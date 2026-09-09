# Ignore a recommendation

**Date:** 2026-09-09 · **Status:** approved, implementing

## Glossary

| Term | Meaning |
|---|---|
| **Ignored** (rung) | The lowest rung of a title intent: the person has decided the title is not for them. Stored as `:ignored` on `Discovery.TitleIntent`. Keeps the title off the Recommendations tab; nothing else. |
| **Off** | No title intent record at all — no opinion. Unchanged. |
| **Row dismiss** | The pointer-only `×` on a Recommendations row that sets the title's rung to Ignored in one click. |
| **Undo toast** | The transient toast after a row dismiss whose one action restores the rung the title had before the click. |

## Core idea

*One person's standing intent about one title* is `TitleIntent`, and its rung is the whole ladder. "Ignore this recommendation" is that intent at its most negative: not "leave me alone about releases" (Off — no record) but "I have looked, and no." It is a rung below List, not a second table beside the ladder.

The first draft of this design (a separate `ignored_titles` table) was a second representation of the same idea, one campaign after the codebase converged on one ladder (UIDR-036). Rejected.

## Greenfield shape

```
:ignored < :list < :follow < :ask < :grab < :default        (Off = no record)
```

* `TitleIntent.@rungs` gains `:ignored` first. `rung_at_least?/2`, `follows_releases?/1` and `grab_mode/2` fall out by ordering; `grab_mode(:ignored, _)` is `"off"`.
* `ReleaseTracking.set_rung(title, :ignored, attrs)` is the one write path, unchanged: `derive/4` already drops the tracked title for any rung below Follow.
* `Discovery.list_watchlist/0` (renamed from `list_intents/0`, which the moduledoc already called it) returns rungs at List or above. `Discovery.listed?/2` means `rung_at_least?(rung, :list)`. `Discovery.rungs/0` still returns every record, so every row decoration sees the rung.
* No migration: `rung` is an `Ecto.Enum` over a string column.
* Artwork promotion on create (`ensure_artwork_async/1`) runs only for List and above — an ignored title is not kept in the local tier.

## What changes where

| Surface | Change |
|---|---|
| `IntentControl` | Seventh segment, leftmost: **Ignore · Off · List · Follow · Ask · Grab · Default**. Consequence line for Ignored. This is the modal's ignore verb — no separate tertiary control. |
| `TitleDetailHost` | `set_rung` accepts `"ignored"`. Nothing else. |
| `Logic.row_markers/2` | `:ignored` → marker "Ignored" (a search result you dismissed says so). |
| `RecommendationRows.build/2` | Drops rows whose `rung` is `:ignored`. The tab count follows. Friends' shelves, pennants, and the modal's friend activity are untouched — ignoring keeps a title out of the queue, it does not erase what a friend said. |
| `Title.Row` | Opt-in `ignorable?` attr. The row becomes a wrapper `div` holding the existing card `<button>` plus a sibling `×` button (nested buttons are invalid HTML). Pointer-only: revealed on hover, `tabindex="-1"`, no `data-nav-item`; keyboard and gamepad use the ladder in the modal. The row moduledoc records this as the one exception to "every verb lives in the modal". Pushes `ignore_title` with the ref. |
| `DiscoveryLive` | Handles `ignore_title`: reads the row's current rung, calls `ReleaseTracking.set_rung(title, :ignored, provenance)` with the newest recommendation's `activity_id` as `:friend` provenance, and assigns `ignore_undo`. Handles `ignore_undo` (restores the previous rung, or Off) and `ignore_undo_dismiss` (clears the assign). The broadcast `RungChanged` reloads the rows, so the row leaves through the same path every other rung change uses. |
| `ActionToast` | New component `action_toast/1`: the flash skin, one message, one action button, `FlashAutoDismiss` on a 6 s dwell. The hook replays the element's own `phx-click`, so expiry and a manual click clear the assign through one path. `flash/1` stays text-only; it is layout-owned and cannot carry a payload. |

## Interactions decided

* Ignoring a title at Follow or above tears its calendar down, exactly as Off would; the ladder's consequence line says so.
* Raising an ignored title to List or above from the ladder (or from any *Track these* path) simply replaces the rung: wanting it supersedes having dismissed it. Its Recommendations row returns — the row shows who recommended it, which is worth seeing again once you care.
* The modal opened from a dismissed row stays open (the activity list still resolves it); the row underneath is gone when the modal closes.
* Undo exists only for the row `×`, where there is no visible state to reverse. The ladder is its own undo.
* Reviewing the ignored list is deferred: `Discovery.rungs/0` already carries the data; a later `list_ignored/0` is a query, not a migration.

## Tests

* `discovery_test`: `:ignored` is below List; `list_watchlist/0` excludes it; `listed?/2` is false for it; `rungs/0` includes it; artwork is not promoted for it.
* `title_intent` unit: `rung_at_least?`, `follows_releases?`, `grab_mode` for `:ignored`.
* `recommendation_rows_test`: an ignored ref drops out; grouping of the rest unchanged.
* `intent_control_test` / `logic_test`: the Ignore segment, its description, the "Ignored" marker.
* `discovery_live_test`: the row `×` removes the row and the count, the toast appears, Undo restores the row and the prior rung; the ladder's Ignore removes the row; the `×` is absent on the watchlist tab.
* Stories: `intent_control` rungs group gains `:ignored`; `title_row` gains an `ignorable` variation; new `action_toast` story.

## Records

UIDR-036 (one control per title) gains the seventh rung as an amendment; `docs/GLOSSARY.md` **Rung** entry updated; wiki `Watchlist.md` ladder table and `Social.md` Recommendations section updated.
