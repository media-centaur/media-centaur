# Play in Place — hover play button on cards, direct play everywhere

## Problem Statement

Mouse users need two aimed steps to start playback (card → modal →
Play), while their stated intent when clicking a title is usually "just
play it." The pointer's free hover channel is unused, and the only
one-click play path (`autoplay=1`) opens the detail modal as a
waystation before playing.

## Design Objectives

- One click from any browse surface to playback.
- Calm: the resting UI is pixel-identical to today; hover feedback is
  opacity-only, immediate, and motionless.
- Purely additive for every user: card click keeps opening details. A
  default-on preference (Settings → Preferences → "Play button on
  cards") turns the overlay off for users who don't want it.
- Invisible to keyboard/gamepad: no new focus stops, no layout or
  scroll perturbation, no reveal on programmatic focus.
- One play path in the system: playing happens in place; the modal is
  for details, never a step toward playback.

## User-Facing Behavior

- Hovering a playable card — library grid (with or without card info),
  Recently Added, Continue Watching — fades in a centered circular play
  button after a short hover-intent delay (opacity only, tunable in
  CSS). Moving the pointer away fades it out with no delay.
- Clicking the button starts playback immediately. No modal opens; on
  leaving playback the page is exactly as the user left it.
- Clicking anywhere else on the card opens the detail modal, unchanged.
- The button fills with the primary color when the pointer is over the
  button itself.
- Poster-shaped cards show a ~52px button, the large continue-watching
  backdrop a ~64px one; both sit on a soft radial halo behind the
  button (never a card-wide scrim, which fought the card's hover
  brighten).
- The hero's Play button now also plays directly — no modal. "More
  info" still opens the modal.
- Cards whose entity has nothing playable show no play button.
  Collection shelf cards and "See all" cards never show one.
- A failed play (e.g. missing file) reports through the same error
  surface as the modal's Play button.
- Keyboard and gamepad experiences are completely unchanged.

## Acceptance Criteria

- [ ] At rest, every card renders identical to today — zero new chrome
      without hover.
- [ ] Hover reveals the button via opacity fade only — no scale or
      translation — after a hover-intent delay that never applies to
      the fade-out.
- [ ] One click on the button starts playback from all three surfaces,
      including wall-of-posters mode.
- [ ] No detail modal opens before, during, or after button-initiated
      playback; the browse surface is unchanged on return.
- [ ] Clicking any non-button part of a card opens details as before.
- [ ] Hero Play starts playback without opening the modal; More info
      still opens it.
- [ ] The `autoplay` modal-then-play path no longer exists anywhere —
      no surface and no URL triggers it.
- [ ] The button never appears from keyboard/gamepad focus (including
      `:focus-visible`), is not a nav item, and adds no focus stop or
      scroll/layout change.
- [ ] Non-playable entities, collection shelf cards, and "See all"
      cards show no play button.
- [ ] Progress hairline, now-playing pulse, and selected/focus ring
      render unchanged and don't collide with the button.
- [ ] The overlay is one shared component with one state matrix across
      all three surfaces (size tier only).

## Anti-patterns

- **Dwell pop-out**: no delay-then-expand panel; the expansion
  duplicates the modal. (The hover-intent *delay* itself was adopted
  for the button reveal — the expansion stays rejected.)
- **Default inversion**: a bare card click must never start playback —
  accidental fullscreen mpv (+ HDR flip) is the app's most expensive
  misclick, and inversion is what would force a settings toggle.
- **Hover motion**: no zoom, lift, or scale on card or button.
- **Action creep**: one button, one action; no add-to-list/ratings/
  metadata furniture on the hover layer.
- **Parallel play paths**: modal-then-play must be deleted, not left
  beside the new path.
- **UI-side playability guessing**: button visibility comes from the
  library views' presence vocabulary, not heuristics in templates.

## Deferred

- Episode/season rows inside the detail modal adopting the same hover
  affordance.
- Any touch-input consideration.
- Revisiting whole-card-resumes for Continue Watching.

## Decisions

See `decisions/user-interface/2026-08-17-027-play-in-place.md`
(UIDR-027). Related: UIDR-012 (rendering calm), UIDR-018 (input system
owns focus/scroll), UIDR-020 (cursor regularity), UIDR-025 (collections
are filing).
