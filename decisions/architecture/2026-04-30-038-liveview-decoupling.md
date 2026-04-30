---
status: accepted
date: 2026-04-30
---
# LiveViews never couple to each other — extract shared concerns

## Context and Problem Statement

Several pages of the app present the same domain object (an entity, a play
button, a detail modal) but each lives in its own LiveView module — Home,
Library, Review, Watch History, Status, Settings, Console. As features
grow, the temptation is to copy-paste a working chunk of mount logic, an
event handler, or a fragment of a template from one LiveView into another,
or worse, to call across LiveViews via the dictionary-style assigns name
("the LibraryLive way of doing X").

That pattern produces real, recurring bugs:

- The "Watch again" mislabel on the Home page traced back to
  `home_live.ex` initialising `resume_targets: %{}` and never populating
  it, while the LibraryLive computed and updated the same map correctly.
  Both LiveViews then handed that map to the shared `entity_modal/1`
  component, which silently fell through to the wrong branch.
- LibraryLive and HomeLive each had their own ad-hoc playback session
  tracking, until `LiveHelpers.apply_playback_change/5` was extracted and
  unified them.
- Similar drift exists in `handle_info` clauses for `:entities_changed`,
  in tracking-status loading, and in the way entity entries are loaded
  for the modal.

The root pattern: when two LiveViews need the same behaviour, it is
nearly always cheaper *now* to copy code than to extract it. The cost
shows up later as silent divergence — one copy gets a fix the other
doesn't, and the bug is invisible because each LiveView's tests only
cover its own copy.

## Decision Outcome

Chosen option: "LiveViews are leaves of the dependency graph. Any
behaviour or markup that appears in more than one LiveView must be
extracted into a shared component or helper module before the second
copy is committed. LiveViews never depend on each other directly."

### Rules

1. **No LiveView module imports, aliases, or calls another LiveView
   module.** A LiveView is a leaf — it depends on contexts, components,
   and helper modules, but never on another LiveView. If you need
   something a sibling LiveView already has, extract it.

2. **Shared markup → function component.** Anything rendered by two
   LiveViews lives in `lib/media_centarr_web/components/`. The component
   declares its assigns explicitly with `attr/3` (typed where possible
   per the component-contract guidance) and is rendered the same way in
   every caller. Examples in-tree:
   `MediaCentarrWeb.Components.{ModalShell, EntityModal, HeroCard,
   PlayCard, FacetStrip, …}`.

3. **Shared logic → helper module.** Pure functions belong in a helper
   module with `async: true` unit tests per
   [ADR-030](./2026-04-02-030-liveview-logic-extraction.md). Examples
   in-tree: `MediaCentarrWeb.LiveHelpers` (debounce, playback diff),
   `MediaCentarrWeb.LibraryFormatters`, the per-component `Logic`
   modules under `components/detail/`.

4. **Shared mount/event wiring → `__using__` macro or behaviour.** When
   two LiveViews need the same mount setup, PubSub subscriptions, or a
   family of `handle_info` clauses (e.g. the Console drawer), extract
   into a `Shared` module and `use` it from each LiveView. Example
   in-tree: `ConsoleLive.Shared`. Don't grow this option lightly — a
   plain helper module is preferable when the surface is small.

5. **Cross-LiveView state changes flow through PubSub, never direct
   calls.** When one LiveView's action affects another's view (a play
   action started in the modal updating the Home grid), the path is
   *context broadcasts → both LiveViews subscribe → each updates its own
   state*. Direct cross-LiveView messages or assigns are forbidden, in
   line with [ADR-029](./2026-03-26-029-data-decoupling.md).

6. **The second copy is the trigger.** A LiveView is allowed to grow
   private helpers for behaviour that is genuinely page-specific. The
   moment a second LiveView needs the same thing, that helper is
   extracted *before* the second use site is committed — not "we'll
   refactor later". "Later" is how the bugs above were born.

### How this differs from related ADRs

- [ADR-029 (data decoupling)](./2026-03-26-029-data-decoupling.md) governs
  cross-context dependencies (compile-time enforced via Boundary). This
  ADR governs cross-LiveView dependencies inside the web layer.
- [ADR-030 (LiveView logic extraction)](./2026-04-02-030-liveview-logic-extraction.md)
  requires extracting non-trivial logic out of templates so it can be
  unit-tested. This ADR is the next step: extracted helpers must be
  *shared* when two LiveViews need them, never duplicated.

### Consequences

* Good, because divergence bugs (one LiveView fixed, the other not)
  cannot occur — there is one implementation.
* Good, because shared components and helpers acquire tests that exercise
  every caller's case, not just one.
* Good, because the dependency graph stays acyclic and easy to read:
  contexts → helpers → components → LiveViews.
* Good, because adding a new page to the app becomes assembly: pick the
  shared components, add page-specific wiring, ship.
* Bad, because the first extraction has a small upfront cost — naming a
  module, deciding on the assigns shape, moving the tests. This is
  cheaper than the cleanup it prevents.
* Bad, because the boundary between "page-specific helper" and "shared
  helper that just happens to have one caller today" requires judgement.
  Default to leaving page-specific code in the LiveView module until a
  second caller appears, then extract.
