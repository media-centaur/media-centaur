---
status: accepted
date: 2026-10-31
---
# Features are flagged

Campaign: `campaigns/discovery.md` (M3). Amends UIDR-051 (the Social switch) and the `show_apps` pattern it copied.

## Context and Problem Statement

Two switches gated optional parts of the app, and neither did the whole job. `show_social` hid the Social sidebar entry and the Review control while the Social page, the Social section, the relay connections, relay sync, the activity publisher and an hourly job ran on. `show_apps` hid the Apps entry while `/apps` stayed reachable. Each was a `BooleanSetting` module of its own, an `on_mount` of its own, a layout attribute threaded through fourteen LiveViews, and a row wherever its author put it (Preferences; later Settings → Social). A third feature, Discovery, was about to copy the pattern. There was no word for what these switches were, so there was no rule for what "off" meant.

## Decision Outcome

A **feature** is a named, optional capability of the product with its own surface — a page, a Settings section, affordances on other surfaces, runtime work — that an install can run without. Its **flag** is the one fact about it. Everything that exists for the feature derives from that fact.

1. **One registry declares every feature.** `MediaCentaur.Features` holds the list: id, name, one-line description, default, stage. Nothing else names a feature's existence; a surface that gates on a feature reads the registry's id.
2. **Off means off.** While a feature's flag is off: no sidebar entry; its Settings section is not listed, and its URL draws the off state; its affordances on other surfaces are absent (the Review control for Social); its routes draw the off state in place of their content; its processes do not run (`Features.Runtime` starts a feature's supervision children when the flag is on and stops them when it goes off, live, as the Services toggles already stop the pipeline); its Oban jobs return without work; nothing off the host is admitted while remote players is off.
3. **The flag is a preference**, stored in Settings under `feature:<id>` with the boolean-setting shape, read through the cached Settings layer, not scoped to an environment. Its row is under **Settings → Feature flags**, one per registry entry, and nowhere else.
4. **The stage says why a row exists.** `:development` — unfinished; the row says "In development." — or `:optional` — finished, and a user may still not want it. A feature in development ships default off behind its row. The stage is about the feature; the input system's WIP notice is about a page's navigation, a different fact.
5. **One reader each.** `Live.FeaturesAware` assigns the enabled set to every LiveView, follows the flag's broadcast and owns the turn-on action; the layout takes the set as one attribute; `Components.FeatureOff` is the one drawing of a feature that is off; `Features.Runtime` is the one owner of feature processes, fed each feature's children by `Application`.
6. **Not a feature.** A *capability* (`MediaCentaur.Capabilities`) is an integration configured and tested; a feature can need one, and a feature on with its capability missing shows the capability-gap empty state (UIDR-034). A *service start flag* (`Settings.Services`) pauses core background work and hides nothing. A *preference* changes how a feature behaves, not whether it exists. The library, playback, TMDB, acquisition, watch history and profiles are the product, not features.

First application: Social (optional, default on), remote players (optional, default on), Apps (optional, default off). `show_social` and `show_apps` are not read; no data migration, as UIDR-051 did (Social keeps its default; a user who had turned Apps on turns it on once more).

### Consequences

* Good, because a new feature is one registry entry, a gated route, and its children in the runtime map; the sidebar, Settings and Status follow without a line each.
* Good, because "off" is checkable: a test turns a flag off and asserts nothing of the feature runs or shows.
* Bad, because a test that turns a feature off restarts singletons through the sandbox's reset; the sandbox judges a registered name by presence, not pid, for that reason.
* Bad, because a feature's Oban cron still ticks while off; the job is where the flag is asked.
