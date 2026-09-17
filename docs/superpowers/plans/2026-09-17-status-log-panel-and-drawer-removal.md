# Status Log Panel, Journal Relocation, Drawer Removal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give every Status subsystem drill-in a real log panel fed by the per-component rings, move the journal tail to the Status System drill-in, and delete the tilde console drawer.

**Prerequisite:** Plan 1 (`docs/superpowers/plans/2026-09-16-per-component-log-rings.md`) is **complete**. `Console.read(%Filter{}, limit)`, `Console.config/0` and `Buffer.whole_store_limit/0` exist; the buffer holds one 200-entry ring per component.

**Spec:** `docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md`

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, ExUnit, bun (JS tests).

**Order matters.** Phase E deletes the drawer; it must come *after* Phase D rehomes the journal, or the journal tail is briefly homeless. Phases A→B→C build the feature the drawer's removal depends on.

**Repo rules throughout:**
- Run `~/scripts/agents/agent-mix`, **never bare `mix`** — a second `mix` against the shared `_build` takes the always-on dev server down.
- Test-first. Red, then green.
- Zero warnings (`--warnings-as-errors`).
- **ADR-030:** any `if`/`case`/`cond`/`Enum` pipeline on domain data goes in a pure public function, unit-tested `async: true` — not inline in a LiveView.
- **MC0024:** never assert on `data-`/`phx-`/`class=`/`id=` literals with `=~`; use `has_element?(view, "[phx-click='x']")`. Asserting user-visible copy with `=~` is fine.
- **MC0009:** a function component under `lib/media_centaur_web/components/**` needs a story unless its module declares `@storybook_status :skip`.
- Commit to `main`. No branches. No `Co-Authored-By: Claude`.
- End each commit message with `Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV`

---

## Phase A — `HealthBoard.components_for/1`

**Files:** `lib/media_centaur_web/live/status_live/health_board.ex`, `test/media_centaur_web/live/status_live/health_board_test.exs`

- [ ] **A1. Write the failing test**

```elixir
describe "components_for/1" do
  test "a subsystem that is its own component returns just itself" do
    assert HealthBoard.components_for(:watcher) == [:watcher]
    assert HealthBoard.components_for(:acquisition) == [:acquisition]
  end

  test "social folds in the nostr wire tag" do
    assert Enum.sort(HealthBoard.components_for(:social)) == [:nostr, :social]
  end

  test "system absorbs the app components with no tile of their own" do
    assert Enum.sort(HealthBoard.components_for(:system)) == [:apps, :review, :settings, :system]
  end

  test "framework components never reach a subsystem" do
    all_mapped = Enum.flat_map(HealthBoard.board_subsystems(), &HealthBoard.components_for/1)

    for framework <- MediaCentaur.Log.Component.framework() do
      refute framework in all_mapped
    end
  end

  test "self_update is a declared hole — it has no component tag" do
    assert HealthBoard.components_for(:self_update) == []
  end
end
```

The `:self_update` case is deliberate, not an oversight: `Log.Component`'s moduledoc records that SelfUpdate's logs were unified onto `:system`. The Updates tile therefore has no log section. The test pins that as a decision.

- [ ] **A2. Run it — expect `function HealthBoard.components_for/1 is undefined`**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live/health_board_test.exs
```

- [ ] **A3. Implement**

`normalize/1` is already private in this module. Derive from it so the two directions cannot drift:

```elixir
@doc """
The log components whose lines belong to `subsystem`.

Derived by folding `Log.Component.app/0` through `normalize/1`, so the
board's fold has exactly one definition and the inverse cannot drift from it.

Framework components (`:phoenix`, `:ecto`, `:live_view`) are excluded — a
subsystem panel never shows framework logs. Those stay on `/console`, behind
the same opt-in that hides them there by default.

`:self_update` returns `[]`. SelfUpdate's logs were deliberately unified onto
`:system` (see `MediaCentaur.Log.Component`'s moduledoc), so the Updates tile
has no log section. That is a declared hole, asserted by test.
"""
@spec components_for(atom()) :: [atom()]
def components_for(subsystem) do
  Enum.filter(Component.app(), &(normalize(&1) == subsystem))
end
```

Add `alias MediaCentaur.Log.Component` if absent.

- [ ] **A4. Green, then delete `log_lines/1`**

`HealthBoard.log_lines/1` (the dead incident-samples flattener this whole campaign replaces) and its `describe "log_lines/1"` test block are deleted in this step. Its only caller is `health_components.ex`, which Phase C rewrites — so expect that file to break until C lands. Do **not** fix it here.

- [ ] **A5. Commit**

```bash
git add lib/media_centaur_web/live/status_live/health_board.ex \
        test/media_centaur_web/live/status_live/health_board_test.exs
git commit -m "feat(status): map each subsystem to its log components

components_for/1 folds Log.Component.app/0 through the existing normalize/1
so the inverse cannot drift. Framework components are excluded — those stay
on /console. :self_update maps to nothing, pinned by test: its logs were
deliberately unified onto :system.

Deletes log_lines/1, which flattened incident samples rather than reading
log history and was blank whenever a subsystem was healthy."
```

---

## Phase B — extract `log_line/1`

**Files:** `lib/media_centaur_web/components/console_components.ex`

`log_list/1` currently fuses a container (`phx-update="stream"`, `phx-hook="LogTail"`) with a row. The Status panel needs the row without the container.

- [ ] **B1. Extract the row, keeping `log_list/1` behaviour identical**

```elixir
attr :entry, MediaCentaur.Console.Entry, required: true
attr :show_component, :boolean,
  default: true,
  doc: "render the component badge; false on single-component surfaces where it is noise"

def log_line(assigns) do
  ~H"""
  <div
    class={["console-entry", View.level_color(@entry.level)]}
    data-level={@entry.level}
    data-component={@entry.component}
    data-message={View.entry_search_text(@entry)}
  >
    <span class="console-timestamp">{View.format_timestamp(@entry.timestamp)}</span>
    <span :if={@show_component} class={["console-component-badge", View.component_badge_class(@entry.component)]}>
      {View.component_label(@entry.component)}
    </span>
    <span class="console-message">{@entry.message}</span>
  </div>
  """
end
```

`log_list/1` then becomes the container plus `<.log_line :for={...} entry={entry} />`. **Careful:** the stream container needs `id={dom_id}` on each child for `phx-update="stream"`. Keep the `id` on the wrapper element inside `log_list/1`'s `:for`, not inside `log_line/1` — a stream child's id is the stream's business, and the Status panel has no stream. Wrap:

```heex
<div :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
  <.log_line entry={entry} />
</div>
```

Verify in the browser that this extra wrapper does not break `console-log` layout (the CSS may target direct children). If it does, instead pass the id through as an attr on `log_line/1` — `attr :id, :string, default: nil` — and keep the flat structure.

- [ ] **B2. Storybook coverage — investigate, don't guess**

`console_components.ex` declares module-level `@storybook_status :skip` with reason *"Log stream is sticky LiveView state — covered by page smoke tests"*. Read `credo_checks/storybook_coverage.ex` and determine whether that module-level attribute exempts **every** function component in the file or only those it can attribute to the stream.

Then run:

```bash
~/scripts/agents/agent-mix credo --strict
```

If MC0009 flags `log_line/1`, add `storybook/console/log_line.story.exs` with variations for: an `:error` line, an `:info` line, and `show_component={false}`. If it does not flag it, add **nothing** — but leave a one-line comment above `log_line/1` noting that its rendered states are covered by `health_drill_in.story.exs` (Phase C), so the exemption is a recorded decision rather than an accident.

- [ ] **B3. Verify and commit**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/console_page_live_test.exs \
                                test/media_centaur_web/page_smoke_test.exs
```

```bash
git add lib/media_centaur_web/components/console_components.ex storybook/
git commit -m "refactor(console): extract log_line/1 from log_list/1

The Status subsystem panel needs the row without the stream container."
```

---

## Phase C — the Status subsystem log panel

**Files:** `lib/media_centaur_web/components/health_components.ex`, `lib/media_centaur_web/live/status_live.ex`, `storybook/health/health_drill_in.story.exs`, `test/media_centaur_web/live/status_live_test.exs`

- [ ] **C1. Replace the dead disclosure in `health_components.ex`**

Delete the current block (the `<details>` calling `HealthBoard.log_lines(@buckets)`) and the `HealthBoard` alias if it becomes unused. Add two attrs to `health_drill_in/1`:

```elixir
attr :log_lines, :list,
  default: [],
  doc: "[Console.Entry.t()] recent lines for this subsystem, newest first"

attr :show_log_components, :boolean,
  default: false,
  doc: "per-line component badges; true only where a subsystem folds more than one tag"
```

Render:

```heex
<details :if={@log_lines != []} class="glass-inset rounded-xl">
  <summary
    data-nav-item
    tabindex="0"
    class="cursor-pointer select-none px-4 py-3 text-sm text-base-content/60"
  >
    Technical logs
  </summary>
  <div class="max-h-96 overflow-y-auto border-t border-base-content/10 px-4 py-3">
    <MediaCentaurWeb.ConsoleComponents.log_line
      :for={entry <- @log_lines}
      entry={entry}
      show_component={@show_log_components}
    />
  </div>
</details>
```

**The `:if={@log_lines != []}` is the point of the whole change** — the old disclosure rendered unconditionally and so was permanently visible and permanently empty on a healthy subsystem. No empty-state copy is added; absence is the empty state.

- [ ] **C2. Wire `StatusLive` — pure logic first (ADR-030)**

Add to `health_board.ex` (pure, unit-tested `async: true`):

```elixir
@doc """
The `%Filter{}` selecting a subsystem's log lines: its components only,
everything else hidden, `:info` and above.

The store is lossless by level so `/console` can show `:debug`; the floor is
applied here, at read time, because a status panel showing SQL debug is noise.
"""
@spec log_filter(atom()) :: Filter.t()
def log_filter(subsystem) do
  Filter.new(
    components: Map.new(components_for(subsystem), &{&1, :show}),
    default_component: :hide,
    level: :info
  )
end

@doc "True when a subsystem folds more than one component, so lines need a badge to disambiguate."
@spec multi_component?(atom()) :: boolean()
def multi_component?(subsystem), do: length(components_for(subsystem)) > 1
```

Test both: `log_filter(:watcher)` admits a `:watcher` info entry and rejects a `:watcher` debug entry and an `:ecto` entry; `multi_component?(:social)` is true, `multi_component?(:watcher)` is false.

In `status_live.ex`, the drill-in is `handle_params`-driven (`parse_subsystem/1` → `:selected_subsystem`). That is the subscribe point:

- When `:selected_subsystem` transitions to non-nil: `Console.subscribe()`, then `assign(:log_lines, Console.read(HealthBoard.log_filter(subsystem), @log_panel_lines))`.
- When it transitions to nil: unsubscribe with `Topics.unsubscribe(Topics.console_logs())` and `assign(:log_lines, [])`.
- `@log_panel_lines 200` as a module attribute, with a comment: *the panel's render cap, deliberately separate from the ring cap — raising the slider deepens the rings but a disclosure holding 1,000 monospace rows is DOM cost with no reader.*

Add the handler:

```elixir
def handle_info({:log_entries, entries}, %{assigns: %{selected_subsystem: nil}} = socket) do
  {:noreply, socket}
end

def handle_info({:log_entries, entries}, socket) do
  filter = HealthBoard.log_filter(socket.assigns.selected_subsystem)
  matching = Enum.filter(entries, &Filter.matches?(&1, filter))

  if matching == [] do
    {:noreply, socket}
  else
    lines = Enum.take(Enum.reverse(matching) ++ socket.assigns.log_lines, @log_panel_lines)
    {:noreply, assign(socket, :log_lines, lines)}
  end
end
```

`Enum.reverse(matching)` because the broadcast batch is oldest-first while `log_lines` is newest-first. **Assert this ordering in a test** — it is the kind of thing that looks right and is backwards.

Pass to the component in render: `log_lines={@log_lines}` and `show_log_components={HealthBoard.multi_component?(@selected_subsystem)}`.

- [ ] **C3. Story variations (MC0009)**

`storybook/health/health_drill_in.story.exs` gains three variations: **lines present** (a few `%Console.Entry{}` fixtures at mixed levels), **no lines** (`log_lines: []` — asserts the section is absent), and **multi-component fold** (`show_log_components: true` with entries from two components). Build entries as `%MediaCentaur.Console.Entry{}` literals with fixed timestamps — storybook renders must be deterministic.

- [ ] **C4. LiveView tests**

In `status_live_test.exs`: opening a drill-in renders its lines; a `{:log_entries, _}` broadcast for a matching component appends; a broadcast for a *non*-matching component does not; closing the drill-in clears. Use `has_element?`, never `=~` on markup.

- [ ] **C5. Verify and commit**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live_test.exs \
    test/media_centaur_web/live/status_live/ test/storybook_render_test.exs \
    test/media_centaur_web/page_smoke_test.exs
```

```bash
git commit -m "feat(status): real log history on each subsystem drill-in

The panel reads the subsystem's per-component rings at :info and above, and
renders only when there are lines — the old disclosure flattened incident
samples and so was permanently visible and permanently empty on a healthy
subsystem."
```

---

## Phase D — relocate the journal to Status → System

**Files:** `lib/media_centaur_web/components/health_components.ex`, `lib/media_centaur_web/live/status_live.ex`, `test/media_centaur_web/live/status_live_test.exs`

The journal is **not** a second copy of the ring panel. The ring holds structured, subsystem-scoped entries that start empty at boot; the journal holds raw whole-process text that **survives restarts and contains what killed the VM**. Label it as the service's systemd journal, not as more subsystem logs.

`MediaCentaur.Console` already exposes: `journal_subscribe/0` → `{:ok, [Entry.t()]} | {:error, :no_unit_detected}`, `journal_unsubscribe/0`, `journal_available?/0`, `journal_snapshot/0`, `journal_reconnect/0`. Messages arrive as `{:journal_line, entry}` and `{:journal_reset}`.

- [ ] **D1. Server-controlled disclosure, because subscribe must be server-side**

`JournalSource` refcounts subscribers and only spawns `journalctl -f` while someone is watching. Subscribing merely because the System tile was opened would spawn a process for a passer-by. So this is **not** a `<details>` — it is a button toggling an assign:

- `:journal_open` assign, default `false`.
- `handle_event("toggle_journal", ...)`: on open, `Console.journal_subscribe()` and seed from the returned snapshot; on close, `Console.journal_unsubscribe()` and clear.
- Closing the drill-in (`selected_subsystem` → nil) must **also** unsubscribe. Leaking a subscriber keeps `journalctl` alive indefinitely — assert this in a test.
- Render the control only when `Console.journal_available?/0` and `@selected_subsystem == :system`.

- [ ] **D2. Component**

Add `journal_panel/1` to `health_components.ex` taking `lines`, `open`, `on_toggle`. Reuse `ConsoleComponents.log_line/1` with `show_component={false}` — every journal entry is `component: :systemd`, so the badge is noise. Story variations: closed, open-with-lines, open-empty.

- [ ] **D3. Tests**

**Read this before writing tests — the obvious approach does not work.** `console_page_live_test.exs` does not exercise the journal at all today, so there is no existing pattern to copy. `Console.journal_subscribe/0` delegates to `JournalSource` under its default `__MODULE__` name, and the app supervisor already runs that singleton, so a LiveView test cannot inject a stub instance. `journal_source_test.exs` gets around this by starting its own **named** instance (`JournalSource.start_link(name: ...)`) — an option the facade does not expose.

Split the coverage accordingly rather than hacking a seam in a test:

1. **LiveView level:** in the test environment no systemd unit is detected, so `journal_available?/0` is false. Assert the control is **absent** on the System drill-in. This is the real default path and it is worth pinning.
2. **Pure logic:** extract the toggle decision (open/closed → subscribe/unsubscribe/clear) into a pure function and unit-test it `async: true`, per ADR-030.
3. **Subscribe/unsubscribe lifecycle:** already covered by `journal_source_test.exs` against a named instance. Do not duplicate it.

**Do not** add an injectable-name parameter to the `Console` facade just to make a test pass — that is a production seam, and if it is genuinely wanted it is its own decision. Report it as a concern instead.

The leak case still needs asserting: **closing the drill-in while the journal is open must unsubscribe.** Cover that in the pure toggle logic (closing yields an unsubscribe action), since the LiveView path is unreachable without availability.

- [ ] **D4. Commit**

```bash
git commit -m "feat(status): systemd journal moves to the System subsystem

Subscribe on expand, not on drill-in open — JournalSource refcounts and
spawns journalctl -f, so opening the System tile must not spawn a process
for a passer-by. Closing the drill-in unsubscribes."
```

---

## Phase E — delete the drawer

**Only after D.** The journal must have its new home first.

- [ ] **E1. Delete the drawer LiveView and its mount**

- Delete `lib/media_centaur_web/live/console_live.ex`.
- Delete `Layouts.console_mount/1` (`lib/media_centaur_web/components/layouts.ex:277-289`) and its call in **12 page LiveViews** — find them with `grep -rln "console_mount" lib/media_centaur_web/`. Note the name collision: `ConsoleLive.Shared` has its *own* private `console_mount/1` (the mount helper inside the macro). Do not delete that one in Phase E2's inlining; rename it to something unambiguous such as `mount_console_state/1`.
- Delete `test/media_centaur_web/live/console_live_test.exs`.

- [ ] **E2. Inline `shared.ex` into `ConsolePageLive`**

`console_live/shared.ex` is a `__using__` macro that exists solely to share mount/handlers between the drawer and the page. With one consumer it is indirection wrapping no duplication. Move its contents into `console_page_live.ex` as ordinary functions and delete `shared.ex`. Keep `logic.ex` — it is pure functions, tested independently, and stays a module.

Drop from the page while inlining: `source_tabs/1`, `journal_list/1`, the `:active_source` assign, `:journal` stream, and the `{:journal_line, _}` / `{:journal_reset}` handlers. The journal now lives on Status. `/console` becomes one source with no tabs. Delete `source_tabs/1` and `journal_list/1` from `console_components.ex`.

- [ ] **E3. JavaScript**

- Delete `assets/js/hooks/console.js` and `assets/js/hooks/console.test.js`; remove the hook's registration from wherever hooks are collected.
- Remove the `toggle_console` global binding in `assets/js/app.js:228-245`, including the `data-global-bindings` key if nothing else reads it.
- Check `assets/js/input/` for any reference to the console overlay (`data-captures-keys`) and remove what is now dead.
- Run `bun test assets/js/` and `~/scripts/agents/agent-mix assets.build`. **Dev asset watchers are off in this repo** — an `assets/` edit needs a manual build or the dev server serves stale JS.

- [ ] **E4. CSS**

`console-overlay`, `console-panel` and any drawer-only rules in `assets/css/` are now dead. Remove them. Keep `console-entry`, `console-timestamp`, `console-component-badge`, `console-message`, `console-log` — `log_line/1` and `/console` still use them.

- [ ] **E5. Verify**

```bash
~/scripts/agents/agent-mix precommit
bun test assets/js/
```

Then confirm in a browser via `~/scripts/agents/page-shot --url http://127.0.0.1:2160/console --wait-ms 3000` that `/console` still renders, and that a normal page no longer carries `console-sticky-root`.

- [ ] **E6. Commit**

```bash
git commit -m "feat: retire the tilde console drawer

/console keeps the full filtering UI; the Status subsystem panels cover the
common case and the journal now lives on Status -> System. Deletes
console_live/shared.ex with it: its __using__ macro wrapped duplication that
stops existing once there is one consumer."
```

---

## Phase F — documentation

- [ ] **F1. In-repo**

| File | Change |
|---|---|
| `CLAUDE.md` | "Observability for Debugging" — the drawer is gone; runtime diagnostics are the Status subsystem panels, `/console`, and `mc-eval` |
| `docs/architecture.md` | Console context description |
| `docs/GLOSSARY.md` | drop/replace drawer terms |
| `.claude/skills/troubleshoot/SKILL.md` | production log access path |

- [ ] **F2. Wiki** (separate repo, `~/src/media-centaur/media-centaur.wiki`, git)

`Keyboard-Shortcuts.md` and `Keyboard-and-Gamepad.md` (the `` ` `` binding is gone), `Troubleshooting.md` (how to read logs now).

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A && git commit -m "wiki: console drawer retired; logs live on Status" && git push
```

- [ ] **F3. CHANGELOG**

Under Unreleased, user-facing: the drawer is gone, each Status subsystem now shows its own recent logs, the journal moved to System, and — **carried from Plan 1** — *a previously customised console buffer size resets to the new per-subsystem default.*

---

## Out of scope

- Giving `:self_update` a component tag (reverses a decision in `Log.Component`; own change).
- Input-system / nav coverage for `/console` (surface in flux; mouse-only stands).
- The two scheduled convergences recorded in the spec (pending-review count rendered in two widgets; `:http` being a lens rather than a subsystem).
