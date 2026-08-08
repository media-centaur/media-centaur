---
status: accepted
date: 2026-08-07
---
# The detail modal navigates as two regions, and BACK peels containment

## Context and Problem Statement

The detail modal is where a title is actually chosen: it carries Play, More
info and Manage above the body of the title — seasons and episodes for a
series, the film list for a collection, extras for anything.

It navigated as **one flat list of every focusable element in DOM order**. Up
and down walked that list and wrapped at its ends, left was up by another name,
right stepped into whatever controls the focused row carried, and BACK closed
the whole modal from anywhere inside it. Nothing was wrong with any single
transition; the model was simply that the modal had no structure, and every
consequence followed from that:

* Getting from Play to episode 7 of season 3 meant pressing down past two
  buttons and every row above it, because the buttons and the episodes were
  peers.
* Leaving the episode list meant closing the modal and reopening it.
* Left and right, the only two directions with nothing to do in a vertical
  list, were spent on "up" and "step into the row's controls".
* Expanding a season required landing on its header and pressing OK — there was
  no way to say "open this" that was distinct from "toggle whatever this is".

The modal is not a list. It is a small document: a row of commands about the
title, over an index of the things inside it. This record states what follows
from taking that seriously.

## Decision Outcome

### 1. The modal has two regions, and they are separate nav zones.

`detail_actions` is the command row — Play / More info / Manage. `detail_list`
is the body, whichever sub-view is showing. Left and right move between the
three buttons and stop at the ends; up and down do not move between them at all,
because they are a row.

Declared in the markup (`data-nav-zone`) rather than inferred, because which
elements are commands and which are content is a fact about the template, not
something geometry can be asked.

### 2. Down enters the body at its highlighted item.

The body has one **highlighted item**: seeded from the episode Play would play
(`[data-resume-target]`, the same row the panel scrolls to and marks as next
up), and thereafter wherever the cursor was last left. Down goes to it. That is
the whole rule — "the resume target" is the seed, not a separate branch, so
returning to the list after glancing at the buttons puts you back where you
were rather than at the top or at episode one.

The memory is scoped to one opening. Reopening a title re-seeds, because "where
I was" does not survive leaving.

### 3. BACK leaves the region you are in; it does not step out one level.

From anywhere in the body — a season header, an episode, an episode's watched
toggle — one press lands on Play. From Play, the next press closes the modal.

This is deliberately not "peel one layer": stepping back out one level at a time
is what LEFT is for (rule 4), and duplicating it in BACK would make the number
of presses needed to leave depend on how deep you had wandered.

Generalized rather than special-cased. BACK is now answered once, before the
context type, by walking containment: an overlay region leaves via a declared
`back` edge in the nav graph → sub-focus exits (for flat overlays, which have no
region above) → the overlay dismisses → the primary menu exits → content does
nothing. It had been a `case Action.BACK` in eight separate transition
functions, where the ordering between those rules was implicit and unstated.

### 4. In the body, left and right are depth, not lateral movement.

A vertical list has nothing to its left or right, so the pair is free — and the
body is a tree: seasons contain episodes, and an episode contains its own
controls. One idiom covers all of it.

| Cursor on | RIGHT | LEFT |
|---|---|---|
| Collapsed season | expand | — |
| Expanded season | — | collapse |
| Episode | step into its controls | collapse the season it is in, landing on the header |
| An episode's controls | on to the next control | back to the previous, then out to the row |

Collapsing from inside a season lands on that season's header, which is both
where the content went and where you would want to continue from. OK on a season
header toggles it, so a user who never discovers left and right is not stuck.

Right walking *along* an item's controls rather than entering only the first is
what makes the watched toggle reachable at all: it is the second control on
every episode row that has a synopsis, and before this it could not be reached
without a mouse.

### 5. `aria-expanded` is the disclosure signal.

It is already the correct markup for a disclosure, so the input system reads it
rather than a parallel `data-` attribute stating the same fact twice. A
`data-nav-group` ancestor marks the extent of the disclosure, which is how LEFT
from an episode finds the header to collapse.

### 6. An overlay declares its own navigation model, or stays a flat list.

`data-nav-overlay="detail"` names an entry in the input config carrying the
overlay's regions and how they relate. Anything without one keeps the flat
behaviour, which remains right for a confirm dialog or a small form.

The overlay's topology is merged over the page's when it is open, because the
regions inside a modal relate to each other the same way whatever page it was
opened from.

## Consequences

* Good, because the model is stated once and the rest follows. "BACK from an
  episode goes to Play, BACK from Play closes the modal" is one rule about
  containment, not two cases.
* Good, because the eight duplicated BACK branches collapsed into one function
  whose ordering is now explicit and testable.
* Good, because the watched toggle became reachable from the couch — a
  capability that was absent rather than merely awkward.
* Good, because it applies to every detail type. Movies and collections get the
  same action row over their own body, and a movie with no extras simply has no
  second region: down does nothing and BACK closes, with no conditional model.
* Bad, because the list-wide "Show details" toggle lost its place. It sat
  between the action row and the first season, where it interrupted the one
  path users actually walk, and it belongs with the other list-wide controls in
  Manage. It is mouse-only until it moves there — a real, if small, capability
  removed on purpose.
* Bad, because two more `data-nav-*` attributes now have to be right in the
  template for the modal to navigate at all, and no JS test can see the
  template. Covered by assertions in `library_live_test.exs` that name the
  attributes explicitly, which is the seam between the two layers.
* Neutral, because up at the top of the body does not climb to the action row.
  BACK is the documented way out and giving up/down a second, silent one would
  blur what BACK is for. Revisit if it reads as a dead end in use.
  *Amended 2026-08-08:* it did read as a dead end in the Cast sub-view, whose
  body is a `detail_cast` photo grid (SHELF, geometry-resolved) rather than
  the tree. A spatial grid has a geometric "above", so its top row climbs to
  the action row on UP. The tree keeps the original rule.
* Neutral, because "two regions" became "two regions, except Manage has
  three". *Amended 2026-08-08 (Manage sheet overhaul):* the Manage sub-view's
  toolbar card — Delete all, Rematch, Refresh artwork, the ID links on one
  horizontal strip — walked wrong as tree items: DOWN stepped sideways
  through it. It is now its own `manage_tools` TOOLBAR region between the
  action row and the `detail_list` ledger: LEFT/RIGHT move along the card,
  DOWN drops past it, UP climbs to the action row (it is spatial, like the
  cast grid). The region is empty outside Manage, so the `down` candidate
  lists route through it only when it exists — the containment model is
  unchanged, the overlay just has one more rung where Manage is showing.
