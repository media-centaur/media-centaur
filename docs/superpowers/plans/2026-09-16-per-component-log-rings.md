# Per-Component Log Rings (Store) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Console.Buffer`'s single shared ring with one capped ring per log component, so filtering to a component yields real history instead of whatever survived a shared cap.

**Architecture:** The buffer's state becomes `%{component => ring}`. The four existing read shapes (`snapshot/0`, `snapshot_window/1`, `recent/0,1`) collapse to one `read(%Filter{}, limit)` that uses the filter's component and level dimensions as a **read selector** — only selected rings are pulled — plus a separate `config/0`. `Console.Filter` is already the selection type and is reused as-is rather than a parallel vocabulary being invented. Entries carry a globally monotonic `id` (`System.unique_integer([:monotonic, :positive])`), so merging rings newest-first is a sort by `id` descending.

**Scope:** This plan is the store only. `/console` and the tilde drawer both keep working through every task. The Status subsystem log panel, the journal relocation, and the drawer removal are a second plan (`docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md` covers all of it).

**Tech Stack:** Elixir, GenServer, Phoenix LiveView, ExUnit.

**Sizing (measured, 1,109 live entries):** 200 entries/component × 16 components = 3,200 entries ≈ **2.6 MB**; pathological (every entry at the existing 2,000-char truncation) 8.4 MB. Today: 2.4 MB default, 60 MB at max slider, 131 MB pathological.

**Repo rules that apply throughout:**
- Run `~/scripts/agents/agent-mix`, **never bare `mix`** — a second `mix` against the shared `_build` takes the always-on dev server down.
- Test-first. Red, then green. `mix precommit` before finishing.
- Zero warnings (`--warnings-as-errors`).
- Never `:sys.get_state` or raw `GenServer.call` from outside the owning module (MC0004) — test through the public API.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `lib/media_centaur/console/filter.ex` | The selection value type over log lines | Add `component_visible?/2`, `all/0`; make `level_passes?/2` public |
| `lib/media_centaur/console/buffer.ex` | The store: per-component rings, cap, filter persistence | Rewrite state + reads |
| `lib/media_centaur/console.ex` | Context facade | Swap delegates to `read/2` + `config/0` |
| `lib/media_centaur_web/live/console_live/shared.ex` | Drawer + page shared mount/handlers | Update call sites |
| `lib/media_centaur_web/live/console_live/logic.ex` | Pure console helpers | `visible_entries/2` keeps search only |
| `lib/media_centaur_web/components/console_components.ex` | Console markup | Re-range the cap slider |
| `test/media_centaur/console/filter_test.exs` | Filter unit tests | Add cases |
| `test/media_centaur/console/buffer_test.exs` | Buffer unit tests | Rewrite |

---

### Task 1: `Filter` gains the two predicates the read selector needs

The store must decide *which rings to pull* before it has any entries in hand, so it needs a component check that takes an atom rather than an `%Entry{}`. Today `component_passes?/2` only takes an entry, and both predicates are private.

**Files:**
- Modify: `lib/media_centaur/console/filter.ex:196-204`
- Test: `test/media_centaur/console/filter_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/media_centaur/console/filter_test.exs` inside the outermost `describe`-less scope (match the file's existing style — check whether it wraps tests in `describe` blocks and follow it):

```elixir
describe "component_visible?/2" do
  test "returns true for a component explicitly shown" do
    filter = Filter.new(components: %{watcher: :show}, default_component: :hide)
    assert Filter.component_visible?(filter, :watcher)
  end

  test "returns false for a component explicitly hidden" do
    filter = Filter.new(components: %{ecto: :hide}, default_component: :show)
    refute Filter.component_visible?(filter, :ecto)
  end

  test "falls back to default_component for an unlisted component" do
    filter = Filter.new(components: %{}, default_component: :hide)
    refute Filter.component_visible?(filter, :pipeline)

    permissive = Filter.new(components: %{}, default_component: :show)
    assert Filter.component_visible?(permissive, :pipeline)
  end
end

describe "all/0" do
  test "admits every level and every component" do
    filter = Filter.all()

    assert Filter.component_visible?(filter, :ecto)
    assert Filter.component_visible?(filter, :some_unknown_component)

    for level <- [:debug, :info, :warning, :error] do
      entry = build_entry(level: level, component: :ecto)
      assert Filter.matches?(entry, filter)
    end
  end
end
```

`filter_test.exs` already has `build_entry/1` at line 8 — it merges overrides over defaults through `Entry.new/1`. Use it; do not add a second fixture.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/filter_test.exs
```

Expected: FAIL — `function Filter.component_visible?/2 is undefined or private` and `function Filter.all/0 is undefined`.

- [ ] **Step 3: Implement**

In `lib/media_centaur/console/filter.ex`, add `all/0` next to `new_with_defaults/0`:

```elixir
@doc """
A filter that admits everything — every level, every component, no search.

The "give me the whole store" selection. Named so call sites don't restate
`level: :debug, default_component: :show` and drift apart.
"""
@spec all() :: t()
def all, do: new(level: :debug, components: %{}, default_component: :show)
```

Replace the two private predicates (currently at lines 197-204) with public versions, and route the entry-level check through the atom-level one so there is a single rule:

```elixir
@doc "Whether `entry`'s level clears the filter's level floor."
@spec level_passes?(Entry.t(), t()) :: boolean()
def level_passes?(%Entry{level: entry_level}, %__MODULE__{level: floor_level}) do
  Map.get(@level_ranks, entry_level, 0) >= Map.get(@level_ranks, floor_level, 0)
end

@doc """
Whether a component is visible under this filter.

Takes the component atom rather than an `%Entry{}` so the store can select
which rings to read before it holds any entries.
"""
@spec component_visible?(t(), atom()) :: boolean()
def component_visible?(%__MODULE__{} = filter, component) when is_atom(component) do
  Map.get(filter.components, component, filter.default_component) == :show
end

defp component_passes?(%Entry{component: component}, %__MODULE__{} = filter) do
  component_visible?(filter, component)
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/filter_test.exs
```

Expected: PASS, all tests, zero warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/console/filter.ex test/media_centaur/console/filter_test.exs
git commit -m "refactor(console): expose Filter's level and component predicates

The store needs to select rings by component before it holds entries, so
component_visible?/2 takes the atom and component_passes?/2 routes through
it. Filter.all/0 names the whole-store selection."
```

---

### Task 2: Buffer state becomes per-component rings

**Files:**
- Modify: `lib/media_centaur/console/buffer.ex` (state in `init/1`, `handle_cast({:append, _})`, `trim_if_over/1`)
- Test: `test/media_centaur/console/buffer_test.exs`

The existing buffer trims once per `cap/4` appends rather than on every append — an audit fix (P8) against walking the whole list per log line. **That amortization must survive, per ring.**

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/console/buffer_test.exs`. The file already has the two helpers you need — `build_entry/1` (keyword opts: `:id`, `:level`, `:component`, `:message`) and `start_buffer/1`, which returns `{pid, name}`. Use them; do not add parallel fixtures.

```elixir
describe "per-component rings" do
  test "a chatty component does not evict a quiet component's entries" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    Buffer.append(build_entry(component: :watcher, message: "watcher line"), name)

    for n <- 1..500 do
      Buffer.append(build_entry(component: :ecto, message: "ecto #{n}"), name)
    end

    :ok = Buffer.flush(name)

    messages = Filter.all() |> Buffer.read(1_000, name) |> Enum.map(& &1.message)

    assert "watcher line" in messages
  end

  test "each component's ring is capped independently" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    for n <- 1..50 do
      Buffer.append(build_entry(component: :watcher, message: "w#{n}"), name)
      Buffer.append(build_entry(component: :pipeline, message: "p#{n}"), name)
    end

    :ok = Buffer.flush(name)

    watcher = Filter.new(components: %{watcher: :show}, default_component: :hide, level: :debug)
    pipeline = Filter.new(components: %{pipeline: :show}, default_component: :hide, level: :debug)

    assert length(Buffer.read(watcher, 1_000, name)) == 10
    assert length(Buffer.read(pipeline, 1_000, name)) == 10
  end
end
```

`persist_debounce_ms: 50_000` keeps the settings-persist timer from firing inside a later test's sandbox — the reason `Console.Buffer` carries a `{:reset, …}` disposition in `test/support/global_state_sandbox.ex:87`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: FAIL — `function Buffer.read/3 is undefined`. (Task 3 adds `read`; this task only makes the state per-component. Write both tests now and expect them red until Task 3 lands — that is deliberate, and Step 4 below re-runs them.)

- [ ] **Step 3: Change the state shape**

In `init/1`, replace the `entries: []` / `overflow: 0` fields:

```elixir
state = %{
  rings: %{},
  overflow: %{},
  cap: cap,
  filter: filter,
  persist_ref: nil,
  persist_debounce_ms: Keyword.get(opts, :persist_debounce_ms, @persist_debounce_ms),
  pending: [],
  flush_ref: nil
}
```

Replace `handle_cast({:append, entry}, state)` and `trim_if_over/1`:

```elixir
@impl true
def handle_cast({:append, entry}, state) do
  component = ring_key(entry.component)
  ring = Map.get(state.rings, component, [])

  state = %{
    state
    | rings: Map.put(state.rings, component, [entry | ring]),
      pending: [entry | state.pending]
  }

  {:noreply, state |> trim_if_over(component) |> schedule_flush()}
end

# Rings key on the known component vocabulary. `Entry.classify_component/2`
# lets an explicit `meta[:component]` through as an arbitrary atom, so without
# this fold the ring count would be unbounded. Anything unrecognised joins
# :system, which is already the catch-all everywhere else.
defp ring_key(component) do
  if component in MediaCentaur.Log.Component.all(), do: component, else: :system
end

# Trimming on every append walked `cap` entries per log line (audit P8). Each
# ring may run over by up to a quarter and is trimmed once per that many
# appends; every read takes the cap, so the overflow is never observable.
defp trim_if_over(state, component) do
  seen = Map.get(state.overflow, component, 0) + 1

  if seen >= max(div(state.cap, 4), 1) do
    ring = state.rings |> Map.fetch!(component) |> Enum.take(state.cap)

    %{
      state
      | rings: Map.put(state.rings, component, ring),
        overflow: Map.put(state.overflow, component, 0)
    }
  else
    %{state | overflow: Map.put(state.overflow, component, seen)}
  end
end
```

Update `handle_call(:clear, ...)` and `handle_call({:resize, n}, ...)` to the new shape:

```elixir
def handle_call(:clear, _from, state) do
  # Drop the unflushed batch too — flushing it after the clear would
  # resurrect rows the UI just emptied.
  if state.flush_ref, do: Process.cancel_timer(state.flush_ref)
  broadcast(:buffer_cleared)
  {:reply, :ok, %{state | rings: %{}, overflow: %{}, pending: [], flush_ref: nil}}
end

def handle_call({:resize, n}, _from, state) do
  rings = Map.new(state.rings, fn {component, ring} -> {component, Enum.take(ring, n)} end)
  new_state = %{state | cap: n, rings: rings, overflow: %{}}
  broadcast({:buffer_resized, n})
  {:reply, :ok, schedule_persist(new_state)}
end
```

- [ ] **Step 4: Run the tests — still red, and that is expected**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: the two new tests still FAIL on `Buffer.read/3` being undefined. Every *other* test in the file will also fail, because `snapshot`/`recent` still read `state.entries`, which no longer exists. Task 3 and Task 4 resolve both. **Do not commit at this step** — the tree is intentionally mid-refactor.

---

### Task 3: `Buffer.read/2` — the one read

**Files:**
- Modify: `lib/media_centaur/console/buffer.ex`
- Test: `test/media_centaur/console/buffer_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
describe "read/2" do
  test "returns entries newest-first across rings, ordered by id" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    first = build_entry(component: :watcher, message: "first")
    second = build_entry(component: :pipeline, message: "second")
    third = build_entry(component: :watcher, message: "third")

    for entry <- [first, second, third], do: Buffer.append(entry, name)
    :ok = Buffer.flush(name)

    assert ["third", "second", "first"] =
             Filter.all() |> Buffer.read(10, name) |> Enum.map(& &1.message)
  end

  test "pulls only the rings the filter makes visible" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    Buffer.append(build_entry(component: :watcher, message: "watcher line"), name)
    Buffer.append(build_entry(component: :ecto, message: "ecto line"), name)
    :ok = Buffer.flush(name)

    filter = Filter.new(components: %{watcher: :show}, default_component: :hide, level: :debug)

    assert ["watcher line"] = filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
  end

  test "applies the filter's level floor" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    Buffer.append(build_entry(component: :watcher, level: :debug, message: "noisy"), name)
    Buffer.append(build_entry(component: :watcher, level: :warning, message: "important"), name)
    :ok = Buffer.flush(name)

    filter = Filter.new(level: :info, default_component: :show)

    assert ["important"] = filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
  end

  test "honours the limit" do
    {_pid, name} = start_buffer(cap: 100, persist_debounce_ms: 50_000)

    for n <- 1..20, do: Buffer.append(build_entry(component: :watcher, message: "m#{n}"), name)
    :ok = Buffer.flush(name)

    assert length(Buffer.read(Filter.all(), 5, name)) == 5
  end

  test "folds an unknown component into the :system ring" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    Buffer.append(build_entry(component: :not_a_real_component, message: "stray"), name)
    :ok = Buffer.flush(name)

    system_filter = Filter.new(components: %{system: :show}, default_component: :hide, level: :debug)

    assert ["stray"] = system_filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
  end
end
```

- [ ] **Step 2: Run to verify they fail**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: FAIL — `function Buffer.read/3 is undefined`.

- [ ] **Step 3: Implement**

Add the public API next to `snapshot/0` (which Task 4 deletes):

```elixir
@doc """
Entries matching `filter`, newest-first, capped at `limit`.

The filter's component and level dimensions act as a **read selector** — only
visible rings are pulled, and below-floor entries never leave the store. Search
is not applied here: it is per-keystroke and handled at the call site.
"""
@spec read(Filter.t(), pos_integer()) :: [Entry.t()]
def read(%Filter{} = filter, limit), do: read(filter, limit, __MODULE__)

@doc "Explicit name variant for tests."
@spec read(Filter.t(), pos_integer(), atom()) :: [Entry.t()]
def read(%Filter{} = filter, limit, name) when is_integer(limit) and limit >= 0 do
  GenServer.call(name, {:read, filter, limit})
end
```

And the callback, replacing `handle_call(:snapshot, ...)`, `handle_call({:snapshot_window, n}, ...)`, `handle_call({:recent, nil}, ...)` and `handle_call({:recent, n}, ...)`:

```elixir
@impl true
def handle_call({:read, filter, limit}, _from, state) do
  entries =
    state.rings
    |> Enum.filter(fn {component, _ring} -> Filter.component_visible?(filter, component) end)
    |> Enum.flat_map(fn {_component, ring} -> Enum.take(ring, state.cap) end)
    |> Enum.filter(&Filter.level_passes?(&1, filter))
    # Entry ids come from System.unique_integer([:monotonic, :positive]), so a
    # descending id sort is exact global recency across rings.
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.take(limit)

  {:reply, entries, state}
end
```

- [ ] **Step 4: Run to verify the new tests pass**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: the `read/2` and per-component-ring tests PASS. Tests still calling `snapshot`/`recent` will fail — Task 4 removes them.

---

### Task 4: `config/0`, and delete the old read shapes

**Files:**
- Modify: `lib/media_centaur/console/buffer.ex`, `lib/media_centaur/console.ex`
- Test: `test/media_centaur/console/buffer_test.exs`, `test/media_centaur/console_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
describe "config/0" do
  test "reports the current cap and filter" do
    {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

    filter = Filter.new(level: :warning, default_component: :show)
    :ok = Buffer.put_filter(filter, name)

    config = Buffer.config(name)

    assert config.cap == 10
    assert config.filter.level == :warning
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: FAIL — `function Buffer.config/1 is undefined`.

- [ ] **Step 3: Implement `config`, delete the old reads**

Add to `buffer.ex`:

```elixir
@doc "The buffer's current cap (per component) and filter."
@spec config() :: %{cap: pos_integer(), filter: Filter.t()}
def config, do: config(__MODULE__)

@doc "Explicit name variant for tests."
@spec config(atom()) :: %{cap: pos_integer(), filter: Filter.t()}
def config(name), do: GenServer.call(name, :config)
```

```elixir
def handle_call(:config, _from, state) do
  {:reply, %{cap: state.cap, filter: state.filter}, state}
end
```

**Delete** from `buffer.ex`: `snapshot/0`, `snapshot/1`, `snapshot_window/1`, `snapshot_window/2`, `recent/1` and their `handle_call` clauses.

**Delete** from `lib/media_centaur/console.ex` these delegates:

```elixir
defdelegate snapshot(), to: Buffer
defdelegate snapshot_window(n), to: Buffer
defdelegate recent_entries(), to: Buffer, as: :recent
defdelegate recent_entries(n), to: Buffer, as: :recent
```

**Add** in their place:

```elixir
defdelegate read(filter, limit), to: Buffer
defdelegate config(), to: Buffer
```

- [ ] **Step 4: Update `console_test.exs`**

Replace every `Console.snapshot()` / `Console.recent_entries()` call. The whole-store read is now:

```elixir
Console.read(Filter.all(), 1_000)
```

Add `alias MediaCentaur.Console.Filter` to the test module if it isn't already aliased.

- [ ] **Step 5: Run both test files**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs test/media_centaur/console_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/console/buffer.ex lib/media_centaur/console.ex \
        test/media_centaur/console/buffer_test.exs test/media_centaur/console_test.exs
git commit -m "refactor(console): per-component rings behind one read/2

State becomes %{component => ring}, capped per component, so a chatty
component no longer evicts a quiet one. snapshot/0, snapshot_window/1 and
recent/0,1 collapse into read(%Filter{}, limit), which uses the filter's
component and level dimensions as a read selector. The amortized trim
survives, per ring."
```

---

### Task 5: Cap semantics — new settings key and range

The persisted key `console_buffer_size` means "total lines". It now means "lines per component". `load_settings` does **not** clamp an out-of-range value — it resets it to the default (`buffer.ex:323-330`) — so a stale 5,000 would silently become the new default rather than anything proportional. A new key makes that change explicit. No compatibility shim (repo policy: remove obsolete paths).

**Files:**
- Modify: `lib/media_centaur/console/buffer.ex` (module attributes, `load_settings/0`, `persist_to_settings/1`)
- Test: `test/media_centaur/console/buffer_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
describe "cap range" do
  test "the per-component defaults are in force" do
    assert Buffer.default_cap() == 200
    assert Buffer.min_cap() == 100
    assert Buffer.max_cap() == 1_000
  end
end
```

If `min_cap/0` and `max_cap/0` are not already public, check `buffer.ex` — add them alongside `default_cap/0` if missing:

```elixir
@doc "Smallest settable per-component cap."
@spec min_cap() :: pos_integer()
def min_cap, do: @min_cap

@doc "Largest settable per-component cap."
@spec max_cap() :: pos_integer()
def max_cap, do: @max_cap
```

- [ ] **Step 2: Run to verify it fails**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: FAIL — assertion error, `2000 != 200`.

- [ ] **Step 3: Implement**

```elixir
@default_cap 200
@min_cap 100
@max_cap 1_000
```

In `load_settings/0`, change the key:

```elixir
case Settings.get_by_key("console_lines_per_component") do
```

In `persist_to_settings/1`, change the key:

```elixir
Settings.find_or_create_entry!(%{
  key: "console_lines_per_component",
  value: %{"value" => state.cap}
})
```

- [ ] **Step 4: Run to verify it passes**

```bash
~/scripts/agents/agent-mix test test/media_centaur/console/buffer_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/console/buffer.ex test/media_centaur/console/buffer_test.exs
git commit -m "feat(console): cap is per component, 200 default

New settings key console_lines_per_component; console_buffer_size is
deleted rather than reinterpreted, since load_settings resets an
out-of-range value to the default instead of clamping it."
```

---

### Task 6: Update the console LiveView call sites

**Files:**
- Modify: `lib/media_centaur_web/live/console_live/shared.ex:43,105,144,216,224`
- Modify: `lib/media_centaur_web/live/console_live/logic.ex:19-25,44-47`
- Test: `test/media_centaur_web/live/console_live_test.exs`, `test/media_centaur_web/live/console_page_live_test.exs`

- [ ] **Step 1: Read the current call sites**

```bash
grep -n "Console.snapshot\|Console.recent_entries\|visible_entries\|initial_snapshot" \
  lib/media_centaur_web/live/console_live/shared.ex \
  lib/media_centaur_web/live/console_live/logic.ex
```

- [ ] **Step 2: Delete `Logic.initial_snapshot/0`**

It mirrored `Console.snapshot/0`'s bundle shape, which no longer exists — and it has **no caller in `lib/`**. Its only reference is its own test. Verify, then delete both:

```bash
grep -rn "initial_snapshot" lib/ test/
```

Expected: the definition at `lib/media_centaur_web/live/console_live/logic.ex:22-25` and the `describe "initial_snapshot/0"` block in `test/media_centaur_web/live/console_live/logic_test.exs:25`. Nothing else. Delete both. Do not write a replacement — `shared.ex` reads `Console.config/0` directly in Step 3.

`visible_entries/2` now only applies search — the store already applied component and level:

```elixir
@doc """
Returns the subset of `entries` matching the filter's search term, preserving
order. Component and level are applied by `Console.read/2` as a read selector,
so this is the one dimension left at the call site.
"""
@spec visible_entries([Entry.t()], Filter.t()) :: [Entry.t()]
def visible_entries(entries, %Filter{} = filter) when is_list(entries) do
  Enum.filter(entries, &Filter.search_passes?(&1, filter))
end
```

This needs `Filter.search_passes?/2` public. In `filter.ex`, change `defp search_passes?` to `def search_passes?` with a doc:

```elixir
@doc "Whether `entry`'s message contains the filter's search term (case-insensitive)."
@spec search_passes?(Entry.t(), t()) :: boolean()
def search_passes?(%Entry{}, %__MODULE__{search: ""}), do: true

def search_passes?(%Entry{message: message}, %__MODULE__{search_lower: search_lower}) do
  String.contains?(String.downcase(message), search_lower)
end
```

- [ ] **Step 3: Update `shared.ex`**

At mount (line ~43), replace the snapshot read:

```elixir
config = Console.config()
visible_entries = Console.read(config.filter, Buffer.default_cap())
```

Then `assign(:filter, config.filter)` and `assign(:buffer_size, config.cap)` in place of the `snapshot.filter` / `snapshot.cap` reads.

Note the filtering comment above this block in the current code — it explains the "flash of unfiltered text" fix. Keep it, updated: the filter is now applied *in the store*, which is strictly stronger than applying it before streaming.

At the resize handler (line ~105) and filter-change handler (line ~144), replace:

```elixir
visible = Logic.visible_entries(Console.read(filter, Buffer.default_cap()), filter)
```

At the download/copy payload sites (lines ~216, ~224), replace `Console.snapshot()` with:

```elixir
Console.read(socket.assigns.filter, Buffer.max_cap() * 16)
```

`Buffer.max_cap() * 16` is the whole store at its ceiling — 16 rings at the maximum per-component cap. Add a brief comment saying exactly that, so the constant is not mysterious.

- [ ] **Step 4: Run the console LiveView tests**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/live/console_live_test.exs test/media_centaur_web/live/console_page_live_test.exs
```

Expected: PASS. Both files reference `Console.recent_entries()` — update those assertions to `Console.read(Filter.all(), 1_000)`.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/console_live/ lib/media_centaur/console/filter.ex \
        test/media_centaur_web/live/console_live_test.exs \
        test/media_centaur_web/live/console_page_live_test.exs
git commit -m "refactor(console): LiveViews read through Console.read/2

Component and level become a read selector in the store; visible_entries/2
keeps only the search dimension."
```

---

### Task 7: Re-range the cap slider

**Files:**
- Modify: `lib/media_centaur_web/components/console_components.ex:272-285`
- Modify: the `action_footer` story under `storybook/` (find it with `find storybook -iname "*console*"`)

- [ ] **Step 1: Update the markup**

```heex
<div class="console-buffer-size">
  <form id="console-buffer-size-form" phx-change="resize_buffer">
    <input
      type="range"
      name="size"
      min="100"
      max="1000"
      step="100"
      value={@buffer_size}
      class="range range-xs"
    />
  </form>
  <span class="console-buffer-size-label text-xs">{@buffer_size} / subsystem</span>
</div>
```

The unit words matter: the number alone reads as a total, which is what it used to mean.

- [ ] **Step 2: Update the `@doc` attribute description**

Change the `:buffer_size` line in the component's `## Attributes` docblock (line ~238) from "current buffer capacity" to "current per-component buffer capacity".

- [ ] **Step 3: Confirm there is no story to update**

`console_components.ex` declares `@storybook_status :skip` with the reason *"Log stream is sticky LiveView state — covered by page smoke tests"* (lines 8-11), so MC0009 does not require a story for it. **Do not add one.** Verify nothing references the component in `storybook/`:

```bash
grep -rn "action_footer" storybook/
```

Expected: no hits.

- [ ] **Step 4: Verify**

```bash
~/scripts/agents/agent-mix test test/media_centaur_web/page_smoke_test.exs
```

Expected: PASS — the smoke test is what covers this component's render path.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/console_components.ex
git commit -m "feat(console): slider sets lines per subsystem, 100-1000"
```

---

### Task 8: Full verification

- [ ] **Step 1: Check the global-state sandbox still holds**

`test/support/global_state_sandbox.ex:87` resets `Console.Buffer` via `{MediaCentaur.Console.Buffer, :reset, []}`. `reset/1` delegates to the `:clear` callback, which Task 2 updated — confirm the disposition still describes reality and that `global_state_sandbox_test.exs:57` ("the Console ring buffer is emptied") passes.

```bash
~/scripts/agents/agent-mix test test/media_centaur/global_state_sandbox_test.exs
```

Expected: PASS.

- [ ] **Step 2: Grep for any surviving references to the deleted API**

```bash
grep -rn "snapshot_window\|Console.snapshot\|recent_entries\|console_buffer_size" lib test storybook
```

Expected: no hits outside this plan's own documentation. Fix any that remain.

- [ ] **Step 3: Run precommit**

```bash
~/scripts/agents/agent-mix precommit
```

Expected: PASS — compile with zero warnings, format clean, credo `--strict` clean, boundaries clean, deps.audit and sobelow clean, full suite green.

- [ ] **Step 4: Confirm the behaviour against the running dev server**

The dev server is the always-on daily driver. After `agent-mix precommit` has compiled into the isolated build root, confirm the real instance still serves logs:

```bash
~/scripts/agents/mc-eval 'alias MediaCentaur.Console; alias MediaCentaur.Console.Filter; Console.read(Filter.all(), 5) |> Enum.map(& {&1.component, &1.level}) |> IO.inspect()'
```

Expected: five recent `{component, level}` pairs. Note this reads the *running* server, which is on the pre-change code until it is restarted — so treat a shape mismatch here as "not yet reloaded", not a failure.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix(console): precommit fallout from the ring rewrite"
```

---

## Plan 2 (not in this document)

The spec's remaining work, in dependency order. Each depends on this plan's `read/2` landing first:

1. **Status subsystem log panel** — `HealthBoard.components_for/1` derived from `Log.Component.app()` through `normalize/1`; `log_line/1` extracted from `log_list/1`; the panel renders only when there are lines; live updates via `console:logs` while a drill-in is open.
2. **Journal relocation** — the journal tail moves from a `/console` tab to the Status System drill-in, subscribing on *expand* rather than on drill-in open.
3. **Drawer removal** — `console_live.ex`, the sticky mount in `layouts.ex:286`, the `` ` `` binding, and `console_live/shared.ex` (whose `__using__` macro wraps duplication that stops existing once there is one consumer).
4. **Docs** — `CLAUDE.md`, `docs/architecture.md`, `docs/GLOSSARY.md`, the `troubleshoot` skill, and the wiki's `Keyboard-Shortcuts.md` / `Keyboard-and-Gamepad.md` / `Troubleshooting.md`.
