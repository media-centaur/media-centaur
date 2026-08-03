---
status: accepted
date: 2026-08-03
---
# Coming Up depth is the house modal, and unscheduled titles are rows

## Context and Problem Statement

On Incoming > Coming up, clicking an agenda row opened a per-title slide-over — the
only drawer in the app. Every other "click a thing → see its depth" surface is a
centered modal through the `<.modal>` seam (UIDR-013), including the pursuit modal on
the same page, so the page carried two zoom-in physics for two rows sitting inches
apart. The slide-over also hand-rolled its overlay, dodging MC0020.

Meanwhile, tracked titles with nothing scheduled ("stragglers") rendered as plain text
inside a one-line disclosure — visible but inert. No detail, no auto-grab toggle, no
stop-tracking. The titles most likely to prompt "why am I still tracking this?" were
the only ones with no verbs at all.

Three directions were mocked (`mockups/coming-up-depth/`): stragglers-as-rows with a
lean house modal, an art-forward straggler card band with a rich modal, and inline
accordion expansion with no overlay.

## Decision Outcome

Chosen option: "stragglers as rows + one centered title modal", combining direction 1's
structure with direction 2's modal interior, because it is the only direction that
serves all three governing values — one idiom for depth, everything tracked is
actionable, and the agenda's calm stays intact:

* **Stragglers become first-class agenda rows** behind a quiet "Not scheduled yet · N"
  hairline toggle, **collapsed by default** (owner review pass: dormant titles are
  bookkeeping and shouldn't occupy the resting view — the ledger's grow-in-place
  idiom, applied here; collapsed-by-default means no persistence machinery). Expanded:
  same row anatomy, empty date slot (muted em-dash preserves column alignment), media
  type in the subtitle position, neutral Tracked pill. The text-only disclosure is
  gone — the collapsed toggle differs from it in that expansion yields fully
  interactive rows, not inert names. Presence scales linearly as rows — never a card
  wall that outshouts the schedule.
* **One centered title modal for every row**, dated or not, through the `<.modal>`
  seam (ephemeral): backdrop-art identity header, a featured next-release line (or an
  explicit "Nothing scheduled" statement) above the timeline, the auto-grab toggle,
  the releases timeline (landed entries muted), recent activity, and the sole
  error-tinted "Stop tracking" in the footer. The slide-over is deleted; the app has
  zero drawers again.
* **Status vocabulary states what happens**: the invented term "Armed" is retired on
  every user-facing surface. The pill and event-card label read **"Will grab"** —
  plain future promise in the app's established grab vocabulary, reading as a timeline
  with its siblings (Will grab → In pursuit → Landed). The fallback status keeps
  "Grabs if still missing". This also collapses the accidental double vocabulary
  (pill "Armed" vs event-card "Auto-grabbing") to one label.

The inline-accordion direction was rejected because it re-creates the split this
decision removes (torrent row → modal, shelf row → accordion) and runs out of room if
per-title depth grows; the card-band direction was rejected because it adds a second
visual register and degrades into a wall of cards as idle titles accumulate.

### Consequences

* Good, because both zoom-in gestures on Incoming now share one physics, and the
  modal-seam rule (UIDR-013 / MC0020) holds everywhere again.
* Good, because every tracked title carries the same verbs regardless of schedule
  state — the "visible but inert" class of entries no longer exists.
* Good, because "Will grab" needs no glossary entry; the wiki row defining "Armed"
  becomes self-evident copy.
* Bad, because the agenda list grows by the straggler rows; accepted — the divider
  keeps them cheap, and a "Show all" idiom for stragglers is available later if real
  libraries prove long.
* Bad, because a straggler's modal is information-sparse (absence statement + last
  landed entry); uniformity of the surface was chosen over a bespoke dormant-title
  layout.
* Extends UIDR-015 (Incoming page); conforms to UIDR-013 (modal seam).
