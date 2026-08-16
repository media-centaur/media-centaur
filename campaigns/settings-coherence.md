---
status: in-progress
started: 2026-08-16
last_updated: 2026-08-16
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

In progress — resumed 2026-08-16. Reconciled against `git log`: the first
slice (`85d13351`, `9a7c1271`, `445443ef`) is the only settings work on
main; code matches the plan below. Items 2 and 3 are settled and being
implemented; item 1 awaits the owner's name pick; item 4's design question
is open; item 5 waits for the layout to settle.

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

## Next steps

1. **Process-name pass (design conversation first).** "Watchers",
   "Pipeline", "Image Pipeline" appear as Services toggles, Status-page
   health items, and in guide/wiki copy — internal architecture names in
   user copy. Decide task-facing names with the owner (e.g. "File
   watching" / "Import" / "Artwork downloads"), then rename every surface
   in one change: `services.ex`, `overview.ex` health items, Status
   widgets, guide, wiki (Settings-Reference "Services", Troubleshooting).
   Per the guide-vocabulary rule this is user copy only — module and
   process names stay.
2. ~~**Drop "Scan now" from Services.**~~ Done 2026-08-16 — Services is
   pure process toggles; Scan now lives only on Library → Media
   directories. Wiki paths updated (Settings-Reference, Troubleshooting,
   Adding-Your-Library).
3. ~~**Fold Release Tracking into Acquisition.**~~ Done 2026-08-16 —
   refresh-interval card renders last on Acquisition (not gated on
   Prowlarr), `ReleaseTrackingSection` deleted, legacy redirect
   `release_tracking` → `acquisition`, wiki Settings-Reference +
   Release-Tracking updated.
4. **Unify the directory-ignore story.** Three "ignore this directory"
   settings across two sections: Library → Excluded directories (absolute
   paths), Media Import → Skip directories (names, silent) and Extras
   directories (names, bonus content). Decide whether they co-locate
   (likely Library, next to the media dirs they modify) or stay split with
   point-of-use copy explaining the paths-vs-names distinction. Design
   question: are Skip and Excluded even distinct concepts to a user?
5. **Regenerate the settings screenshots.** Wiki/docs-site embed
   `settings-overview.png`, `settings-library.png`, `settings-tmdb.png` —
   all show the old nav (Updates section, no Maintenance) and the TMDB
   threshold field. Do once, after items 1–4 settle the layout
   (screenshot-showcase skill).
6. ~~*(droppable)* Move Services out of the General group next to
   System.~~ Done 2026-08-16 with item 2 — dividers now read
   operational ‖ personal ‖ media ‖ infra.
7. *(droppable)* Cross-link Media Import → Artwork resolution to
   Maintenance → Re-fetch backdrops. The Maintenance copy already points
   back; the auto-refetch-on-save covers the main path.

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
