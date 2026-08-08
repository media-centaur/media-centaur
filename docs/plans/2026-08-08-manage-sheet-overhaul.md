# Manage Sheet Overhaul — Toolbar Card + Collapsed Folder Ledger

## Problem Statement

The detail modal's Manage view (the cog / `:info` sub-view) renders every known
file as an always-expanded row. For a large TV series (150+ files) the sheet is a
wall of thousands of pixels: per-folder cleanup means hunting for a delete button
scattered between file rows, and the non-file tools (Rematch, Refresh artwork,
External IDs, UUID) sit below the entire inventory. The layout spends the most
pixels on the rarest action (single-file delete) and buries the rest.

The primary usage pattern is whole-title cleanup ("this show is done — reclaim
the disk"), followed by per-folder/season pruning, followed distantly by
single-file surgery.

## Design Objectives

- **Calm at rest** — summaries, not walls. Opening Manage shows numbers and
  one-line rows, not 161 file rows and 161 trash icons.
- **Scope-first cleanup** — prominence follows frequency: delete-everything is
  one click, delete-folder one click without expanding, delete-file behind one
  expansion.
- **Tools without scrolling** — everything you can do to the *title* (Delete
  all, Rematch, Refresh artwork, external IDs, UUID) is visible on open.
- **Uniform with the modal** — folder expansion uses the same disclosure idiom
  (chevron head, `aria-expanded`, TREE LEFT/RIGHT depth) as the episodes view's
  season accordion; buttons/badges through the house components.

## User-Facing Behavior

The sheet is exactly two things plus existing bookkeeping:

1. **Toolbar card** — one bordered card at the top: summary figure
   (n files · total size · folder count), the Delete-all button (danger, with
   size), Rematch and Refresh artwork, and — as the card's quiet lower edge —
   external ID links and the UUID. TMDB-not-ready swaps Rematch for the
   existing Settings hint.
2. **Folder ledger** — one collapsed row per folder: name, file count, size,
   quiet Delete. Expanding (click / RIGHT) reveals file rows sorted by
   filename, each keeping size, absent flag, quality badges, probe lines, and
   a per-file delete. Small inventories (≤ 6 files total — typical movies)
   auto-expand so a single file is never hidden behind a chevron.

Subtitles row and track-override badge stay below the ledger, unchanged.
Inline two-click confirm (with Cancel and re-targeting) is preserved at all
three delete tiers. Folder order is filesystem order. The media-dir root never
offers folder delete.

## Acceptance Criteria

- [ ] Opening Manage shows summary, Delete all, Rematch, Refresh artwork,
      external ID links, and UUID without scrolling
- [ ] Folder groups render collapsed — zero file rows at rest
- [ ] Total files ≤ 6 → groups auto-expand
- [ ] Expanded file rows sorted by filename; keep size / absent / badges /
      probe / delete
- [ ] Media-dir root group never offers folder delete
- [ ] Inline confirm works at all tiers, including deleting-in-flight
- [ ] TMDB-not-ready hint renders inside the toolbar card
- [ ] No files: ledger and Delete all absent; card still carries tools + IDs
- [ ] Full couch operability: every affordance `data-nav-item`; RIGHT/LEFT
      expand/collapse groups exactly like seasons in the episodes view
- [ ] Stories updated in the same change (MC0009)

## Anti-patterns

- **Wall of rows** — never render all files at rest
- **Hover-gated deletes** — quiet ≠ hidden; couch nav can't hover
- **Modal-on-modal confirm** — stays banned
- **Dashboard-ification** — no stat tiles, size bars, or chip palette; color
  only on the destructive action
- **Size-sorted folders** — filesystem order only

## Deferred

- "Delete watched only" scope
- Any redesign of per-file badge/probe presentation beyond carrying it over

## Decisions

Rationale lives in the component moduledoc/comments (repo convention —
moduledocs over ADRs for module-scoped decisions). Related: UIDR-019 (Manage
stays a `detail_list` TREE in the modal's second region), UIDR-013 (dismissal),
UIDR-003 (button variants).
