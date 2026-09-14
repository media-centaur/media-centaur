# Tracking controls — design

Date: 2026-09-14. Replaces the seven-way tracking pill (UIDR-036, the
Ignore rung's 2026-09-09 spec, UIDR-039's narrowing) with the bookmark and
two switches. Owner's diagnosis, verbatim: "these controls are all wrong
from a usability perspective" — Off and Ignore make no sense on a strip
that is supposed to say what the app does; List is redundant with being
on the watchlist; Follow means nothing for a title that is already out;
and auto-grab should be one switch whose ask-first-or-not comes from the
Download button's planning mode, not a second global setting.

## Glossary

Working terms, defined before use. Each names the control or module the
app already has where one exists.

- **Watchlist** (existing) — the titles a person has listed: every title intent at List or above. `Discovery.list_watchlist/0`.
- **Title intent** (existing) — one person's standing record about one title, `Discovery.TitleIntent`; carries the **rung**. Off is the absence of a record.
- **Rung** (existing, narrowed) — where the record sits. After this spec four values: `:ignored`, `:list`, `:follow`, `:grab`. `:ask` and `:default` are deleted.
- **Bookmark** (existing, widened) — the one-click beside a title's primary verb that lists it and, from now on, removes it at any rung. `Components.Title.WatchlistToggle`.
- **Tracking controls** (existing term, new shape) — what a listed title shows beneath its details: up to two switch rows. `Components.Title.TrackingControls`, replacing `Components.Title.IntentControl`.
- **Track release dates** — the first switch. On means the rung is at least `:follow`: the app keeps the title's release calendar and its dates show under Coming up on Incoming. Rendered only while a release is ahead (below).
- **Auto-grab** — the second switch. On means the rung is `:grab`: when a release drops the app plans it. Implies Track release dates.
- **Planning mode** (existing, widened) — the person's Download button default, `Settings.Preferences.PlanningMode`: auto-select best release, or manually select release. From now on it also decides a tracking plan's approval policy.
- **Approval policy** (existing) — who commits a ready plan: `automatic` (the gate) or `review` (a person on Incoming). `PlanningMode.approval_policy/1` is the one mapping, moved down from `MediaCentaurWeb.Live.PlanFlow`.
- **Tracked title** (existing) — the calendar machinery derived for a title at `:follow` or above. Unchanged.
- **Release window** (existing) — where a movie stands in its release sequence, `TMDB.ReleaseWindow`, read from the live TMDB payload at a date. Carried on the title detail as `release_window` once the preview lands; nil before, and for a series.
- **Release ahead** — the row rule derived from the window: for a movie, a home release (digital or disc) has not passed — `:unreleased` or `:theatrical`; `:unknown` and a missing window defer to the snapshot's primary release date. For a series: always true. `Title.Logic.release_ahead?/3`, computed where the rows are mounted.
- **Complete** — a film the library owns: nothing left to release. `ReleaseTracking.complete?/2`, the one spelling of the rule `derive/3` and `reconcile/2` already apply. A series or a collection is never complete.
- **Ignored** (existing) — the rung below List that keeps friends' reviews and listings of the title off the Feed. Unchanged in meaning; set only by the Feed card's Ignore from now on.

## Core idea

A person's standing intent about a title answers three yes/no questions,
in the order a person meets them: is it on my list; should the app keep
its release calendar; should the app plan its releases when they drop.
Whether a planned release commits by itself or waits for approval is not
a per-title question — it is the person's one planning mode, the same
preference the Download button already uses.

Everything below follows from that: three questions are three controls,
the ladder has one rung per yes, and the second global grab policy goes.

## Greenfield shape

### The record

```
Off       — no record
:ignored  — a record: keep this title off the Feed
:list     — on the watchlist
:follow   — on the watchlist; keep its calendar
:grab     — on the watchlist; keep its calendar; plan its releases when they drop
```

`TitleIntent.follows_releases?/1` (≥ `:follow`) is unchanged.
`TitleIntent.grabs?/1` (`== :grab`) replaces `grab_mode/2`; acquisition asks
"does this title grab?" and reads the planning mode for the policy.
`Discovery.grabs?/2` replaces `Discovery.grab_mode/3`.

### The controls, for a listed title

| Control | Where | Sets |
|---|---|---|
| Bookmark | action strip, beside the primary verb | List when off the list or ignored; Off at any listed rung |
| Track release dates | tracking block, first row | Follow when off; List when on; no click while auto-grab is on |
| Auto-grab | tracking block, second row | Grab when off; when on, Follow if the Track row renders, else List |

Which rows render:

| Title | Rows |
|---|---|
| Movie in the library | none (the title is complete; the block shows nothing) |
| Movie not in the library, release ahead | Track release dates · Auto-grab |
| Movie not in the library, out | Auto-grab |
| Series, owned or not | Track release dates · Auto-grab |

A title with no record shows nothing in the block (UIDR-039 holds: the
bookmark is the first act). An ignored title shows the one line it shows
today.

### Copy

Rows are the Settings kit's toggle row (`settings_row/1`, extended with
`id` and `disabled?`): label, description, toggle, whole row clickable.

| Row | Label | Description |
|---|---|---|
| Track (movie) | Track release dates | Theatrical, digital and disc dates show under Coming up on Incoming. |
| Track (series) | Track release dates | Upcoming episodes show under Coming up on Incoming. |
| Track while auto-grab is on | Track release dates | Stays on while auto-grab is on. |
| Auto-grab (movie, auto-select) | Auto-grab | Downloads when it drops. |
| Auto-grab (movie, manual) | Auto-grab | Plans when it drops and waits for your approval. |
| Auto-grab (series, auto-select) | Auto-grab | Downloads episodes as they air. |
| Auto-grab (series, manual) | Auto-grab | Plans episodes as they air and waits for your approval. |

(Shortened 2026-09-14 on the owner's review: one line, no pointer to where the ask-first policy lives — Settings is where a person would look for it anyway.)

Beneath the rows, only while acquisition is not ready: *Auto-grab
downloads nothing until an indexer and a download client are set up under
Settings → Acquisition.* The ignored line is unchanged: *Hidden from the
Feed. Add it to your watchlist to bring it back.*

The label is "Track release dates", not "Notify me on release": nothing
notifies today, and the description says exactly what happens. See
*Scheduled convergence*.

Row markers (`Title.Logic.row_markers/2`): `:follow` → "Tracking",
`:grab` → "Auto-grab"; List and Ignored as today.

### The global setting

Settings → Acquisition → Auto-acquisition loses its "When a release
appears" choice (Grab it / Ask first / Notify only). The card's other rows
(Highest resolution, Within a resolution, Season packs, Search attempts)
stay; its description becomes *Applied to every release auto-grab takes.*
`AutoGrabSettings.default_mode` and the `auto_grab.default_mode` entry
are deleted.

The Download button card's choice now governs tracking plans too; its
description becomes *Also decides whether auto-grab asks first.*

### What each piece of acquisition reads

| Site | Before | After |
|---|---|---|
| `DropPlanner.plan_item/4` guard | `grab_mode != "off"` | `Discovery.grabs?/2` |
| `DropPlanner.approval_policy/2` | ask → review, else automatic | `PlanningMode.approval_policy(PlanningMode.value())` |
| `ModeReconciler.off?/3` | `grab_mode == "off"` | `not Discovery.grabs?/2` |
| `Reactor.Handlers.tracking_item_off?/1` | same | same |
| `Targeting.tracked_want_units/1` | same | same |
| `UpcomingFeed` context | `auto_grab_default_mode` | `approval_policy`; armed ⇔ ready ∧ grabs? ∧ `"automatic"` — the feed predicts what the planner stamps, in the planner's word |
| `TrackingDetail` context and struct | `auto_grab_default_mode` / `default_grab_mode` | `approval_policy` / dropped |
| `Title.Detail` | `default_grab_mode` | `release_window`, `complete?`; `planning_mode` stays for the Download menu |
| `ReleaseTracking.derive/3`, `reconcile/2` | two private owned-film predicates | one public `complete?/2` |
| Feed card list slot | "Following" | "Tracking" — the UI word the switch and the row marker use; code keeps `follow` |

## Diff against the code — every incoherence and its disposition

1. **Two global answers to "does a plan commit alone?"** — planning mode for the Download button, auto-grab default mode for tracking drops. *Fix now:* one, the planning mode. `PlanFlow.approval_policy/1` moves to `PlanningMode.approval_policy/1` so the context layer can read it; the web helper is deleted.
2. **Ignore on the tracking strip.** A Feed-suppression opinion offered as a tracking level, reachable in the modal only for a title already listed. *Fix now:* removed from the modal; the Feed card's Ignore stays the one way onto the rung. The rung itself stays — it is still one representation of "a person's standing intent".
3. **The bookmark as a marker at Follow and above** (UIDR-036 rule 5) contradicts "remove from the watchlist is one act". *Fix now:* the bookmark removes at any rung. What Off destroys is re-derivable: re-listing refetches the calendar; the per-title quality acceptance is keyed by TMDB identity and survives. Dismissed wants are the one thing lost (they reopen on re-follow). Accepted; no undo toast in this pass.
4. **A released movie at `:follow`** can exist after the migration and shows no Track row. The record is the truth and the row marker still says "Tracking"; turning Auto-grab on and off from there lands on List. Accepted — a state the UI can no longer create, and one it clears on the next touch.
5. **An ended series** still shows Track release dates, because the snapshot carries no TMDB status. Accepted; the description is harmless. Not scheduled.
6. **Global flip no longer moves every title at once.** With `:default` deleted, the global setting can no longer turn auto-grab on for all titles. Accepted by the owner (2026-09-14).

Found on the second unify pass (2026-09-14, against the first draft of this spec):

7. **"An owned film is complete" had two private spellings** (`ReleaseTracking.movie_in_library?/1`, `owned_film?/1`) and the first draft added a third at the modal mount. *Fix now:* one public `ReleaseTracking.complete?/2`; the host puts it on the detail.
8. **The first draft stored a derived boolean** (`Detail.release_ahead?`) that the host recomputed when the preview landed. *Fix now:* the detail carries the fact, `release_window`; the mount derives the row rule.
9. **The forecast and tracking contexts carried the Settings atom** (`planning_mode`). What the feed predicts is what the planner stamps. *Fix now:* those contexts and the controls carry `approval_policy` — the glossary's existing word — and the host maps the setting once with `PlanningMode.approval_policy/1`.
10. **Two UI words for one state.** The Feed card says "Following"; the row marker and the switch say "Tracking". *Fix now:* "Tracking" is the UI word; `follow` stays the code word (the guide's entry/entity split).
11. **Two answers to "is this movie out?"** The Download button reads the snapshot's primary date (`MediaResults.release_status/2`); the Track row reads the window. *Scheduled:* the button reads the window too, which changes when Download shows for a film in theaters — a decision under UIDR-022, taken when that verdict and the button are next touched together.
12. **A collection is a `:movie` title carrying the collection's TMDB id** (`EntityModal.find_tmdb_id/1`). Pre-existing; `complete?/2` is false for it because no movie owns that id. Recorded, not scheduled.
13. **The plan board's footer bookmark lists only** (spec 2026-09-14 plan-board-empty-outcome). It is a verb slot on a diagnosis surface, not the bookmark; unchanged.

## Migration

One data migration, raw SQL, idempotent, tested through its `sweep/1`
like every other file under `priv/repo/data_migrations/`
(`20260914120000_tracking_is_two_switches.exs`, module
`Repo.DataMigrations.TrackingIsTwoSwitches`):

1. Read `json_extract(value, '$.value')` from `settings_entries` for key `auto_grab.default_mode`; `"off"` means Notify only.
2. `UPDATE title_intents SET rung = 'grab' WHERE rung = 'ask'`.
3. `UPDATE title_intents SET rung = <'follow' if the setting was "off", else 'grab'> WHERE rung = 'default'`.
4. `DELETE FROM settings_entries WHERE key = 'auto_grab.default_mode'`.

Down is `:ok`: `grab` and `follow` are legal old values, and the deleted
entry's absence reads as the old built-in default (Grab it). Runs with
`mix ecto.migrate_data` on the dev database and on Update now for users;
the CHANGELOG entry names the fold.

## Scheduled convergence

- **A real notice for a tracked release.** A followed title whose release drops produces nothing but a Coming up row. The idiom that fits is the sidebar follow-up pill on Incoming (UIDR-030) counting dropped releases nobody has planned or dismissed — which needs a per-row dismiss on Coming up first, or the pill nags forever. Separate spec; the row's label may then become "Notify me on release".
- **Ended series** hide the Track row once the preview carries TMDB's status. Not scheduled.

## What goes

`Title.IntentControl` (component, story, test, index entry), the `:ask`
and `:default` rungs, `TitleIntent.grab_mode/2`, `Discovery.grab_mode/3`,
`AutoGrabSettings.default_mode` and its Settings row, `PlanFlow.approval_policy/1`,
every `default_grab_mode` / `auto_grab_default_mode` attr, assign and
context key, the bookmark's marker state, `Logic`'s Default-resolving
marker, the `"Tracking: …"` marker words, `ReleaseTracking`'s two private
owned-film predicates, the Feed card's "Following".

## Records

- New **UIDR-042 — Tracking is the bookmark and two switches over one record**, superseding UIDR-036 rules 1, 4 (its bookmark exception) and 5; UIDR-036 gets a dated amendment pointing at it. UIDR-039 stands (bookmark first, then the controls). ADR-066 (one ladder per title) stands; the ladder is shorter.
- `docs/GLOSSARY.md`: Rung, Ignored, Tracking controls, Bookmark, Following, Approval policy, Planning mode.
- Wiki: `Watchlist.md` (bookmark paragraph, Tracking section), `Release-Tracking.md` (Automatic downloads, the Follow/Off references), `Settings-Reference.md` (Auto-acquisition and Download button rows).
- CHANGELOG entry (drafted in the plan's last task).

## Tests

Unit: `title_intent_test` (four rungs, `grabs?/1`), `tracking_controls_test`
(rows, choices, descriptions, form), `watchlist_toggle_test` (Off at any
listed rung), `logic_test` (markers, `release_ahead?/3`), `auto_grab_settings_test`
(no mode), `planning_mode_test` (approval policy), `drop_planner_test`
(grab + manual planning mode parks; follow plans nothing; turning
auto-grab off reconciles), `upcoming_feed_test` and `view_test`
(`planning_mode` context), migration test (ask → grab; default → follow or
grab by the old setting; entry deleted). LiveView: `discovery_live_test`
and `entity_modal_tracking_test` rewritten for the rows and the one-click
bookmark. Stories: `tracking_controls` (every rung × movie/series ×
planning mode, acquisition missing), fixtures updated where they carried a
deleted rung or attr.

The discovery test "the tracking controls' Ignore removes the entry" tests
a control that no longer exists and is deleted; it is a behaviour test,
not a regression test under ADR-027.

## Scope cost

The coherent path touches the schema, one migration, four acquisition
sites, two view-model contexts, one component rewrite with its story and
test, the bookmark, seven mount sites, twelve test files, five story
fixtures, one settings section, three wiki pages, the glossary and a new
UIDR. One session of implementation, one of review. The cheap path — hide
two segments and rename three — would leave the second global policy, the
marker bookmark and the Default rung in place, and was not considered.

## Iteration 2 — 2026-09-14, on the owner's live review

Working terms: **switch** — a toggle glyph and its label as one click, `role="switch"`, the compact form the tracking controls now take (no longer the Settings kit's full-width row, whose `id`/`disabled?` extension was reverted); **release dates readout** — `Components.ReleaseTracking.ReleaseDates`, what the app knows of a title's upcoming dates: a movie's theaters/digital/disc rows from the live release window or the calendar, a series' next dated episodes; **tooltip** — the one glass label (`#app-tooltip`, `hooks/tooltip.js`) for any `data-tip` anchor, the former sidebar-only element generalized.

1. The Notify switch is labelled **Notify you via Coming up** (owner's words); its line names the dates Coming up will carry. Auto-grab's line is one short sentence.
2. The block is one `glass-inset` card: the release dates readout on the left, the switches in a 16rem column on the right. The readout renders as soon as there is a calendar or a movie's release window — an unlisted movie already shows its dates; the switches once the title is listed.
3. The release timeline (featured next release, dated list with status pills) is deleted from both title surfaces; the readout replaces it. The one word beside a row is the forecast status that matters: Will download, Downloading (a link to the pursuit), In your library.
4. Native `title` tooltips on icon buttons are replaced by `data-tip` on the app tooltip, which now positions beneath any anchor and to the right of the sidebar's.
5. A multi-value facet's separator travels with its chip, so a wrap never strands a dot.
