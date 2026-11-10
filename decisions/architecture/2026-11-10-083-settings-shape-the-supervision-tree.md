---
status: accepted
date: 2026-11-10
---
# Settings shape the supervision tree at start

Campaign: `supervision-tree.md`. Amends ADR-081 (2026-11-10 amendment) and
ADR-077 (rule 8, where the orphan rescue runs).

## Context and Problem Statement

An audit of the supervision tree (2026-11-10) found four places where the
tree did not say what ran, and the complexity that followed each:

1. The import and artwork pipelines were switched off with
   `Supervisor.terminate_child/2`. Under `:rest_for_one`, a crash of the
   Stats process ahead of them restarted the terminated children — a
   pipeline the user had turned off came back on. "Enabled" lived in three
   places: the persisted flag, the stopped child, and (for the watchers) a
   `:persistent_term` key, each able to disagree with the others.
2. `Features.Runtime` owned a `DynamicSupervisor` it started inside its own
   `init/1` and matched `{:ok, _}` on every feature's start, so one feature
   whose child failed to start took every feature down, and each cycle
   spent the application supervisor's restart budget.
3. Boot sequencing — the config overlay, the media-dir migration, starting
   the watchers, stopping the disabled pipelines — ran as a `:temporary`
   Task beside the tree. Children started before it finished, the Discovery
   producer polled for the watchers twenty times, two processes
   re-subscribed to redo work the overlay had not yet made possible, and a
   crash after the rescued block left the rest silently undone.
4. Playback's supervisor claimed `:one_for_one` independence over a
   Registry and the session supervisor that registers in it; the watcher
   supervisor's `:one_for_all` restarted every watcher, and rescanned every
   directory, for a crash of its config listener.

## Decision Outcome

Three rules, the tree being the one statement of what runs and why.

1. **A setting decides whether a child is started.** Processes that run
   while a flag is on — a feature flag (ADR-081) or a service start flag
   (`Settings.Services.start?/1`) — are a `MediaCentaur.FlagSupervisor`'s
   children: read at start, reconciled on the flag's broadcast, absent from
   the tree while off. Whether they run is read back from the tree
   (`running?/1`), never stored beside the flag. No code stops a started
   child of a static supervisor to express a setting, and
   `Supervisor.restart_child/2` is never a start path (Credo MC0045).
   `DynamicSupervisor.terminate_child/2` remains the normal end of a
   dynamic child.
2. **A strategy states the dependency its children have.** Children that
   read a sibling by name or registry sit after it under `:rest_for_one`;
   independent children under `:one_for_one`; `:one_for_all` only when one
   child's crash makes the others' state wrong. Each subsystem with two or
   more processes has its own supervisor and its own restart budget; the
   application supervisor holds infrastructure, one-shots, subsystem
   supervisors and single-process subsystems.
3. **Bootstrap runs before the tree, in the tree's order.** Work that must
   finish before any subsystem starts is a child whose start applies it and
   returns `:ignore` (`Application.Bootstrap`), placed after the Repo and
   PubSub and before Oban and every subsystem. Nothing runs beside the boot.
   Work that may fail at boot and is not a prerequisite — an enqueue, a
   store hydration — runs in the owning process's `handle_continue/2` and
   logs instead of crashing the supervisor; `init/1` does no database write
   and no network.

### Consequences

* Good, because a Stats crash cannot start a pipeline the user turned off,
  a failing feature leaves the others running, and a watcher backend's exit
  is handled where it is seen.
* Good, because the Discovery producer's retry loop, the start-then-stop of
  a disabled pipeline, the watcher's `:persistent_term` flag and two
  re-subscribe workarounds are gone; "enabled" has one owner per setting.
* Good, because a subsystem that exhausts its restarts is restarted alone;
  the application and the web layer stay up.
* Bad, because the artwork pipeline's toggle gained a persisted flag
  (`start_image_pipeline`) where it was transient before; a user who toggled
  it off now finds it off after a restart — what the Settings page always
  said it did.
* Bad, because a test that needs the watchers or a pipeline running must
  set the real flag through `MediaCentaur.ServiceFlags`; the test
  environment's inert instance stays inert.
