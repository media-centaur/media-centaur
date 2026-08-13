---
status: accepted
date: 2026-08-13
---
# Subject progress lives in the hero hairline, from one shared component

## Context and Problem Statement

The detail modal's pinned block crammed three unrelated jobs into a ~260px
left column: the metadata row, a thin progress bar with "29m remaining"
beside it, and the action row. The progress strip was the worst-placed
element — wedged between facts and buttons, it read as a divider rather than
information — and the column as a whole was bunched while the synopsis column
sat beside dead space.

Meanwhile the modal already had a better progress idiom: TV series carry
their watched fraction as the orientation hairline flush on the hero window's
bottom edge (`ViewModel.Orientation`), and leaves (movies, collection
members) were the documented exception keeping a card-row bar. Collections
had even grown an unused `Orientation.for_collection/1`. Two idioms for one
concept, and the weaker one was causing the clutter.

Four directions were mocked and compared (`mockups/pinned-block-declutter/`):
hero hairline, progress-fill inside the Play button, metadata absorbed into
the hero lockup, and a full-width command bar at the block's base.

## Decision Outcome

Chosen option: "every subject carries progress in the hero hairline", because
it deletes the clutter into an idiom the modal already owns rather than
inventing a new control state or new chrome.

* **The hairline always shows the *subject's* watched fraction.** TV: the
  series (subject = series). Movie and collection member: that movie. One
  meaning, no per-type branching. The rail tile underline continues to carry
  per-member state for the *set*; hero = selected subject is UIDR-023's
  premise, so the two agreeing on the selected member is coherence, not
  duplication.
* **The PlayCard's percent/remaining row is retired from its contract** —
  attrs removed, story updated — not zeroed or conditionally hidden. No
  progress gauge or copy renders anywhere in the pinned block's card area.
* **Remaining time becomes the metadata line's final item** ("29m left"),
  lightly tinted toward primary so it reads as the hairline's caption. It
  displaces "Released" whenever present — a title mid-watch is self-evidently
  released. Unstarted and fully-watched titles render the metadata line
  exactly as before.
* **One component, everywhere.** The hairline (track + fill + progressbar
  semantics) becomes a single function component with typed attrs and a
  storybook story, rendered by every CinematicShell tenant that shows subject
  progress — never re-implemented as tenant-local markup. Likewise the
  metadata items (including the remaining item and the Released suppression)
  are composed in one builder shared by every subject shape. Drift between
  the movie, member, and TV renderings of the same concept is the failure
  mode this decision exists to prevent.
* The `aria` progressbar label names the subject ("Movie progress" /
  "Series progress"); fraction source is the same view-model value the rail
  tile underline reads, so the two can never disagree.

UIDR-005 (playback card three-row hierarchy) is unaffected — it governs the
Continue Watching playback card, whose progress bar stays. UIDR-004 duration
formatting applies to the remaining figure.

### Consequences

* Good, because the modal has one progress voice: the hairline is the only
  gauge, "Xm left" the only words, for every entity type.
* Good, because the left column drops to two rows (metadata, actions) with
  real spacing — the clutter is resolved by deletion, and unstarted /
  finished states produce zero layout shift.
* Good, because the extraction ends the inline-markup hairline in the
  orientation slot; the component contract is pinned by a story (MC0009).
* Bad, because the hairline's unit is per-subject: a member's hairline shows
  that movie's fraction where a series shows the whole series — correct under
  "subject's fraction", but a viewer comparing a collection modal to a TV
  modal sees different scopes filled by the same pixel.
* Bad, because the metadata line grows one item mid-watch; metadata-rich
  titles wrap a word earlier at narrow widths.
