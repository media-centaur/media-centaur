---
status: complete
started: 2026-08-16
last_updated: 2026-08-17
---
# Settings coherence

## Goal

Finish the settings reorganization started 2026-08-16: every section named
for the user-facing task (not the internal machinery), every setting in the
section a user would look for it in, and no duplicate or one-field sections
padding the nav. The first slice (Maintenance/Danger Zone split, Updates
merged into System, auto-approve threshold → Media Import, poster-titles
toggle → Preferences, Pipeline section renamed Media Import) shipped in
commits `85d13351` + `9a7c1271`; this campaign carries the rest.

## Status

Complete — 2026-08-17. Items 1–4 and 6 shipped in v0.126.5; item 5
(screenshot regen) done after the owner's go-ahead: full tour re-run
against the showcase instance and published to docs-site, README, wiki,
and the assets repo. Item 7 dropped. All completion criteria below hold.

## Decisions made

* `2026-08-16` — Sections are organized by consequence and concern:
  recoverable repair actions live in **Maintenance**, Danger Zone holds only
  the irreversible; update concerns live in one place (System's Updates
  card); settings sit with the behaviour they govern, not the credential
  they mention. (commit `85d13351`)
* `2026-08-16` — Settings sections are named for the user-facing task, not
  the architecture: Pipeline → **Media Import**. Retired section ids get a
  legacy redirect in `handle_params` (`overview`/`updates` → `system`,
  `pipeline` → `import`) — follow that pattern for any future id change.
  (commit `9a7c1271`)
* `2026-08-16` — The Services toggle deliberately kept the name "Pipeline"
  for now: it switches the actual background process, not the Media Import
  settings surface. Whether process names should also be task-facing is
  item 1's design question, not settled.
* `2026-08-16` — Process names are task-facing in all user copy (owner
  pick): Watchers → **File watching**, Pipeline → **Media import**, Image
  Pipeline → **Artwork downloads**. The health board's short labels
  ("File Watcher", "Import") harmonized to the same names; the Status
  activity widget title follows ("Pipeline" → "Media import"). Module and
  process names stay internal per the guide-vocabulary rule.

## Next steps

1. ~~**Process-name pass.**~~ Done 2026-08-16 — owner picked File
   watching / Media import / Artwork downloads; renamed in `services.ex`,
   `overview.ex`, `health_board.ex`, the Status pipeline widget, and wiki
   (Settings-Reference, First-Run, Troubleshooting, Adding-Your-Library,
   TMDB-API-Key, Review-Queue). Also fixed the image-cache flash that
   said "entities"/"pipeline".
2. ~~**Drop "Scan now" from Services.**~~ Done 2026-08-16 — Services is
   pure process toggles; Scan now lives only on Library → Media
   directories. Wiki paths updated (Settings-Reference, Troubleshooting,
   Adding-Your-Library).
3. ~~**Fold Release Tracking into Acquisition.**~~ Done 2026-08-16 —
   refresh-interval card renders last on Acquisition (not gated on
   Prowlarr), `ReleaseTrackingSection` deleted, legacy redirect
   `release_tracking` → `acquisition`, wiki Settings-Reference +
   Release-Tracking updated.
4. ~~**Unify the directory-ignore story.**~~ Done 2026-08-16 — owner
   ruling: Excluded (absolute paths, your library layout) and Skip/Extras
   (folder names found within incoming content) are *distinct concepts*,
   so no merge and no move; the current homes are correct. Instead the
   names carry the distinction: Skip directories → **Ignored folder
   names**, Extras directories → **Extras folder names**; the two ignore
   cards cross-link each other. Wiki Settings-Reference updated.
5. ~~**Regenerate the settings screenshots.**~~ Done 2026-08-17 — full
   tour re-run and published (docs-site + README + wiki thumbnails, 4K
   in the assets repo). Along the way: tour fixed for the buttonless
   omnibox and the identical prowlarr/download-clients frames; showcase
   DB got `services:dev:start_{watchers,pipeline}` enabled so the System
   shot reads all-green.
6. ~~*(droppable)* Move Services out of the General group next to
   System.~~ Done 2026-08-16 with item 2 — dividers now read
   operational ‖ personal ‖ media ‖ infra.
7. ~~*(droppable)* Cross-link Media Import → Artwork resolution to
   Maintenance → Re-fetch backdrops.~~ Dropped 2026-08-16 — the
   Maintenance copy already points back and auto-refetch-on-save covers
   the main path; a second link adds nothing.

## Completion criteria

* No internal architecture name ("Pipeline", "Watchers") appears in
  settings/Status user copy — or the owner has explicitly decided to keep
  a specific one.
* No action appears in two settings sections.
* No settings section contains a single field.
* Wiki Settings-Reference and embedded screenshots match the shipped
  layout.
* Remaining droppable items are either done or struck out here with a
  one-line reason.

## Pointers

* `lib/media_centaur_web/live/settings_live.ex` — `@sections` list, legacy
  redirects in `handle_params`, section router (`section_content/1`).
* Section modules: `lib/media_centaur_web/live/settings_live/*.ex`
  (`*_section.ex` naming for new ones).
* Wiki: `Settings-Reference.md` is the mirror of `@sections`; grep the
  wiki for old section names when renaming (this slice touched
  Review-Queue, TMDB-API-Key, Troubleshooting, Browsing-Your-Library).
* Original review: settings categorization findings 1–10, session
  2026-08-16 (1–4 + rename shipped; 5–10 are this campaign).
