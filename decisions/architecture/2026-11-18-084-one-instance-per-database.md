---
status: accepted
date: 2026-11-18
---
# One instance per database

Supersedes the dev/prod coexistence of commit `0619852b6` (2026-03-05).

## Context and Problem Statement

In March 2026 the installed release and the dev server ran side by side
against one database. To keep them from both watching the same
directories and importing the same files, `config/dev.exs` started the
watchers and the import pipeline off by default, and every service start
flag was stored per environment (`services:dev:start_pipeline`,
`services:prod:start_pipeline`), so each instance could be toggled on its
own.

By November 2026 nothing ran that way. The dev server is the owner's
install; the release service is disabled. Every tool that starts a second
instance gives it its own database through `MEDIA_CENTAUR_CONFIG_OVERRIDE`:
`mc-tv-ab` copies the database and sets `background_services = false`,
`mc-sim-host`, the showcase and the e2e suite each have their own file.

The leftover defaults then caused a fault. ADR-083 gave the artwork
pipeline its own flag, `start_image_pipeline`. No row existed for it on
the dev server, so it took the dev default, off. From 2026-11-10 to
2026-11-17 every title imported on the daily driver got no artwork, and
because the import's artwork hand-off was written to the queue by the
artwork pipeline's own producer, nothing was kept for later either.

## Decision Outcome

**One instance owns a database.** No two running instances share a
database file. An instance that needs the library's data for a
measurement, a simulation or a demo works on its own copy, selected
through `MEDIA_CENTAUR_CONFIG_OVERRIDE`.

Following from it:

1. Every service start flag defaults on, in every environment
   (`Settings.Services.start?/1`). There is no app-env default to override
   it; `config/dev.exs` sets none.
2. A flag is stored once per service, `services:<service>`, with no
   environment segment. The data migration
   `ServiceFlagsLoseEnvironment` keeps the running environment's values
   and drops the rest.
3. An import's artwork is written to the queue whether or not artwork
   downloads are on (`Pipeline.Image.Intake`), so turning a service off
   pauses its work and never discards it.

### Consequences

* Good, because a new service flag starts in the state production uses
  on every instance, so the daily driver and a release cannot differ by a
  default nobody set.
* Good, because the flag key and the settings it lives beside no longer
  carry a distinction no running instance uses.
* Bad, because an ad-hoc dev-environment `mix phx.server` or `mix run`
  without an override still opens the owner's database and runs its
  services. This was already true before this decision (the stored dev
  flags were on); it is a rule to follow, not a guard the code enforces.
