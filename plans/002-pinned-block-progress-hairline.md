# Pinned-Block Declutter — Subject Progress in the Hero Hairline

## Problem Statement

The detail modal's pinned block stacks metadata, a progress bar with
remaining-time caption, and the action row into one narrow left column. The
three strips are visually bunched, the progress bar reads as a divider
between facts and buttons, and the synopsis column floats beside dead space.
TV series already solved this — their progress lives in the hero orientation
hairline — leaving leaves (movies, collection members) as the odd entity type
carrying a card-row bar.

## Design Objectives

- **One progress idiom.** Every subject — series, movie, collection member —
  carries its watched fraction the same way, in the same place, meaning the
  same thing: the subject's own fraction.
- **Declutter by deletion.** The left column loses a whole strip; nothing new
  is added anywhere. No new control states, no chrome near the hero-to-list
  seam.
- **No drift.** The hairline and the metadata line are each rendered from a
  single shared contract used by every modal surface that shows them. The
  movie, member, and TV renderings can never diverge because there is only
  one rendering.

## User-Facing Behavior

- A mid-watch movie or collection member shows a glowing progress hairline
  flush on the hero artwork's bottom edge — exactly where a TV series shows
  its series progress.
- "29m left" appears as the last item of the metadata line, faintly tinted
  toward the accent color, replacing "Released" while a remaining figure
  exists. Unstarted and fully-watched titles show the metadata line exactly
  as today.
- The card area below holds only two rows — metadata and actions — with
  breathing room between them. No bar, percent, or remaining text renders
  there for any entity type.
- Selecting a different collection member re-anchors the hairline to that
  member's fraction; the rail tile underline and the hero hairline always
  agree for the selected member.
- Play/Resume labels, the action row's contents, and d-pad navigation are
  unchanged.

## Acceptance Criteria

- [ ] Mid-watch movie/member: hairline shows its fraction at the hero's
      bottom edge; no progress gauge or copy anywhere in the card area
- [ ] "Xm left" is the metadata line's final item; "Released" is suppressed
      while it is present; unstarted titles render today's metadata line
      unchanged
- [ ] Rail tile underline and hero hairline agree for the selected member
      (same fraction, same source value)
- [ ] Unstarted and fully-watched states produce zero layout shift in the
      column (metadata + actions occupy identical geometry)
- [ ] TV series render identically to today
- [ ] The hairline in TV, movie, and member modals renders from one shared
      component whose contract is pinned by a storybook story; no surface
      carries its own copy of the track/fill markup
- [ ] The remaining-time item and Released-suppression rule are composed in
      one place shared by all subject shapes
- [ ] d-pad walk across the action row is unchanged (mc-nav-trace clean)
- [ ] The hairline carries progressbar semantics with a subject-appropriate
      label ("Movie progress" / "Series progress")

## Anti-patterns

- **Second progress voice**: no percent text, ring, or bar anywhere else in
  the panel — the hairline is the only gauge, "Xm left" the only words.
- **Conditional row kept "just in case"**: the play card's progress
  attributes are removed from its contract and story, not zeroed —
  backward-compat paths are how the old bar creeps back.
- **Unit branching**: the hairline never means different things per entity
  type; it is always the subject's fraction.
- **Tenant-local copies**: pasting the hairline or metadata markup into a
  second modal surface instead of rendering the shared component — the exact
  drift this design forbids.

## Deferred

- Play-button labeling changes ("Resume · 29m" hybrid) — revisit only if the
  metadata-line placement reads poorly in real use.
- Any change to where TV renders its metadata row.
- Rail-tile watched toggle (already deferred in UIDR-023).

## Decisions

See [UIDR-024](../decisions/user-interface/2026-08-13-024-subject-progress-hero-hairline.md).
Builds on [UIDR-023](../decisions/user-interface/2026-08-13-023-movie-first-collection-modal.md)
(one component family) and [UIDR-021](../decisions/user-interface/2026-08-11-021-cinematic-frame-artwork-ladder.md)
(cinematic frame). UIDR-005's playback card is out of scope. Mockups:
`mockups/pinned-block-declutter/` (direction 1 chosen).
