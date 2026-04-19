# Watch-dir runtime configuration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move watch-directory configuration from TOML into the Settings-backed UI, make the file watcher dynamic (off when no dirs, live-start/stop on change), and ship a dialog with rich live validation.

**Architecture:** Settings entry `config:watch_dirs` holds a list of `%{id, dir, images_dir, name}` maps. `Config.watch_dirs/0` contract is preserved (still returns `[String.t()]`) — callers don't change. A one-shot TOML→Settings migration runs on boot. `Config.put_watch_dirs/1` writes + broadcasts; `Watcher.Supervisor` subscribes and reconciles children (start/stop/replace). Validation lives in a pure `DirValidator` module with injected filesystem primitives.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto/SQLite, daisyUI, Bun/Playwright (no JS changes expected for this feature).

**Spec:** `docs/superpowers/specs/2026-04-19-watch-dirs-runtime-config-design.md`

**Deviation from spec (minor):** the spec says "registry key becomes the UUID." On reflection the runtime `Watcher.Registry` already keys by `dir` string, and `dir` must be unique (enforced by validation). UUIDs stay in the Settings entry + UI for stable identity across edits; the Registry key stays `dir`. This keeps the delta to watcher code minimal.

---

## File structure

### New files

- `lib/media_centarr/watcher/dir_validator.ex` — pure validator, all 11 rules, injected FS adapter
- `lib/media_centarr/watcher/reconciler.ex` — pure diff function `(old_entries, new_entries) -> %{start, stop, replace}`
- `lib/media_centarr_web/live/settings_live/watch_dirs_logic.ex` — pure helpers for the card & dialog (ADR-030)
- `test/media_centarr/watcher/dir_validator_test.exs`
- `test/media_centarr/watcher/reconciler_test.exs`
- `test/media_centarr_web/live/settings_live/watch_dirs_logic_test.exs`
- `test/media_centarr/config_watch_dirs_test.exs` (migration + put/get round-trip)

### Modified files

- `lib/media_centarr/config.ex` — add `watch_dirs_entries/0`, `put_watch_dirs/1`, `migrate_watch_dirs_from_toml/0`; rebuild `:watch_dirs` + `:watch_dir_images` from Settings on load
- `lib/media_centarr/watcher/supervisor.ex` — subscribe to config updates; add `reconcile/1`, `handle_info/2`
- `lib/media_centarr/application.ex` — call `Config.migrate_watch_dirs_from_toml/0` after Repo starts, before starting watchers
- `lib/media_centarr/topics.ex` — add `config_updates/0` topic (if absent)
- `lib/media_centarr_web/live/settings_live.ex` — render the card + dialog in the `library` section; wire events
- `defaults/media-centarr.toml` — remove `watch_dirs`, add pointer comment
- `test/media_centarr_web/live/settings_live_test.exs` (or a sibling file) — integration tests for the new UI

---

## Phase 1 — Settings storage, Config contract, migration

### Task 1: Add `Topics.config_updates/0`

**Files:**
- Modify: `lib/media_centarr/topics.ex`

- [ ] **Step 1.1:** Open `lib/media_centarr/topics.ex`. If a `config_updates` topic does not exist, add:

```elixir
@doc "Topic for broadcasting config changes (e.g. watch_dirs)."
def config_updates, do: "config:updates"
```

- [ ] **Step 1.2:** Run `mix compile --warnings-as-errors`. Expect clean compile.

- [ ] **Step 1.3:** Commit.

```bash
jj desc -m "feat(topics): add config_updates pubsub topic"
```
(Changes auto-snapshot in jj; no explicit commit step beyond `jj desc`.)

---

### Task 2: `Config.watch_dirs_entries/0` read path + `put_watch_dirs/1` write path

**Files:**
- Modify: `lib/media_centarr/config.ex`
- Create: `test/media_centarr/config_watch_dirs_test.exs`

- [ ] **Step 2.1: Write failing tests.**

```elixir
# test/media_centarr/config_watch_dirs_test.exs
defmodule MediaCentarr.ConfigWatchDirsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Settings

  describe "watch_dirs_entries/0" do
    test "returns [] when the settings entry is absent" do
      assert Config.watch_dirs_entries() == []
    end

    test "returns the entries from the settings row" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:watch_dirs",
          value: %{
            "entries" => [
              %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => nil, "name" => nil}
            ]
          }
        })

      assert [%{"id" => "aaa", "dir" => "/mnt/a"}] = Config.watch_dirs_entries()
    end
  end

  describe "put_watch_dirs/1" do
    test "persists, updates :persistent_term, and broadcasts" do
      :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.config_updates())

      entries = [
        %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => nil, "name" => nil}
      ]

      assert :ok = Config.put_watch_dirs(entries)

      # persistent_term contract preserved
      assert Config.get(:watch_dirs) == ["/mnt/a"]
      assert Config.get(:watch_dir_images) == %{"/mnt/a" => Path.join("/mnt/a", ".media-centarr/images")}

      assert_receive {:config_updated, :watch_dirs, ^entries}
    end

    test "honours explicit images_dir override" do
      entries = [
        %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => "/mnt/ssd/images", "name" => "Movies"}
      ]

      :ok = Config.put_watch_dirs(entries)

      assert Config.get(:watch_dir_images) == %{"/mnt/a" => "/mnt/ssd/images"}
    end
  end
end
```

- [ ] **Step 2.2:** Run `mix test test/media_centarr/config_watch_dirs_test.exs`. Expect all four tests to fail (functions undefined).

- [ ] **Step 2.3: Implement.** In `lib/media_centarr/config.ex`:

```elixir
@watch_dirs_settings_key "config:watch_dirs"

@doc "Returns the raw list of watch-dir entry maps from Settings."
@spec watch_dirs_entries() :: [map()]
def watch_dirs_entries do
  case MediaCentarr.Settings.get_by_key(@watch_dirs_settings_key) do
    {:ok, %{value: %{"entries" => entries}}} when is_list(entries) -> entries
    _ -> []
  end
end

@doc """
Replaces the entire watch-dir list: persists to Settings, rebuilds the
derived `:watch_dirs` and `:watch_dir_images` values in `:persistent_term`,
and broadcasts `{:config_updated, :watch_dirs, entries}` on the config topic.
"""
@spec put_watch_dirs([map()]) :: :ok
def put_watch_dirs(entries) when is_list(entries) do
  {:ok, _} =
    MediaCentarr.Settings.find_or_create_entry(%{
      key: @watch_dirs_settings_key,
      value: %{"entries" => entries}
    })

  refresh_watch_dirs_persistent_term(entries)

  Phoenix.PubSub.broadcast(
    MediaCentarr.PubSub,
    MediaCentarr.Topics.config_updates(),
    {:config_updated, :watch_dirs, entries}
  )

  :ok
end

defp refresh_watch_dirs_persistent_term(entries) do
  dirs = Enum.map(entries, & &1["dir"])

  images_map =
    Map.new(entries, fn entry ->
      dir = entry["dir"]
      images_dir = entry["images_dir"] || default_images_dir(dir)
      {dir, images_dir}
    end)

  config =
    :persistent_term.get({__MODULE__, :config})
    |> Map.put(:watch_dirs, dirs)
    |> Map.put(:watch_dir_images, images_map)

  :persistent_term.put({__MODULE__, :config}, config)
end
```

- [ ] **Step 2.4:** Run `mix test test/media_centarr/config_watch_dirs_test.exs`. Expect 4 passes.

- [ ] **Step 2.5:** `jj desc -m "feat(config): add watch_dirs_entries/0 and put_watch_dirs/1"`

---

### Task 3: TOML→Settings migration, one-shot on boot

**Files:**
- Modify: `lib/media_centarr/config.ex`
- Modify: `test/media_centarr/config_watch_dirs_test.exs`

- [ ] **Step 3.1: Write failing tests.** Append to `config_watch_dirs_test.exs`:

```elixir
describe "migrate_watch_dirs_from_toml/0" do
  test "imports TOML dirs into a Settings entry with UUIDs" do
    toml_entries = [
      %{"dir" => "/mnt/a", "images_dir" => nil},
      %{"dir" => "/mnt/b", "images_dir" => "/mnt/ssd/images"}
    ]

    :ok = Config.migrate_watch_dirs_from_toml(toml_entries)

    entries = Config.watch_dirs_entries()
    assert length(entries) == 2
    assert Enum.map(entries, & &1["dir"]) |> Enum.sort() == ["/mnt/a", "/mnt/b"]
    assert Enum.all?(entries, fn e -> is_binary(e["id"]) and byte_size(e["id"]) > 0 end)
  end

  test "is a no-op when the settings entry already exists" do
    :ok = Config.put_watch_dirs([%{"id" => "seed", "dir" => "/mnt/existing", "images_dir" => nil, "name" => nil}])
    :ok = Config.migrate_watch_dirs_from_toml([%{"dir" => "/mnt/other", "images_dir" => nil}])

    assert [%{"id" => "seed", "dir" => "/mnt/existing"}] = Config.watch_dirs_entries()
  end

  test "returns :ok with empty input and creates no entry" do
    :ok = Config.migrate_watch_dirs_from_toml([])
    assert Config.watch_dirs_entries() == []
  end
end
```

- [ ] **Step 3.2:** Run the tests. Expect 3 failures.

- [ ] **Step 3.3: Implement.** In `lib/media_centarr/config.ex`:

```elixir
@doc """
One-shot import of TOML `watch_dirs` into the Settings entry. No-op if the
entry already exists. Called once per boot from `MediaCentarr.Application`.
"""
@spec migrate_watch_dirs_from_toml([map() | String.t()]) :: :ok
def migrate_watch_dirs_from_toml(toml_entries) when is_list(toml_entries) do
  case MediaCentarr.Settings.get_by_key(@watch_dirs_settings_key) do
    {:ok, _} ->
      :ok

    _ ->
      entries =
        toml_entries
        |> Enum.map(&normalize_toml_entry/1)
        |> Enum.reject(&is_nil/1)

      case entries do
        [] -> :ok
        list -> put_watch_dirs(list)
      end
  end
end

defp normalize_toml_entry(dir) when is_binary(dir) do
  %{"id" => new_uuid(), "dir" => Path.expand(dir), "images_dir" => nil, "name" => nil}
end

defp normalize_toml_entry(%{"dir" => dir} = table) do
  %{
    "id" => new_uuid(),
    "dir" => Path.expand(dir),
    "images_dir" => table["images_dir"] && Path.expand(table["images_dir"]),
    "name" => nil
  }
end

defp normalize_toml_entry(_), do: nil

defp new_uuid do
  Ecto.UUID.generate()
end
```

- [ ] **Step 3.4:** `mix test test/media_centarr/config_watch_dirs_test.exs` — all 7 pass.

- [ ] **Step 3.5:** `jj desc -m "feat(config): add one-shot TOML→Settings watch_dirs migration"`

---

### Task 4: Wire migration into application boot

**Files:**
- Modify: `lib/media_centarr/application.ex`

- [ ] **Step 4.1:** Locate the init_services task (around line 87-93 per prior exploration). Before the call to `WatcherSupervisor.start_watchers/0`, call the migration. The migration needs the raw TOML entries — use the current TOML loading code as the source. If the TOML was already parsed at load time, the parsed structures are available; otherwise re-read:

```elixir
# In the init_services function, before start_watchers:
toml_entries = Application.get_env(:media_centarr, :__raw_toml_watch_dirs, [])
:ok = MediaCentarr.Config.migrate_watch_dirs_from_toml(toml_entries)

# Refresh :persistent_term from Settings (covers the case where entries
# already exist in the DB from a prior boot).
:ok = MediaCentarr.Config.refresh_watch_dirs_from_settings()
```

- [ ] **Step 4.2:** Add `refresh_watch_dirs_from_settings/0` to `config.ex`:

```elixir
@doc "Rebuilds :watch_dirs and :watch_dir_images from the current Settings entry."
@spec refresh_watch_dirs_from_settings() :: :ok
def refresh_watch_dirs_from_settings do
  refresh_watch_dirs_persistent_term(watch_dirs_entries())
end
```

- [ ] **Step 4.3:** Update `load_config/0` in `config.ex` to stash the raw TOML watch_dirs into Application env so the migration can read them later:

```elixir
# After the merge_toml call that populates defaults.watch_dirs, also:
raw_watch_dirs =
  case get_in(toml, ["watch_dirs"]) do
    list when is_list(list) -> list
    _ -> []
  end

Application.put_env(:media_centarr, :__raw_toml_watch_dirs, raw_watch_dirs)
```

- [ ] **Step 4.4:** Manually smoke-test: start the app, confirm `Config.watch_dirs_entries/0` returns the migrated entries. If you have an existing TOML with `watch_dirs`, confirm the first boot after this change migrates them into the DB.

- [ ] **Step 4.5:** `mix test` — full suite clean.

- [ ] **Step 4.6:** `jj desc -m "feat(config): run watch_dirs migration on boot"`

---

## Phase 2 — Watcher reconciliation

### Task 5: Pure `Reconciler.diff/2`

**Files:**
- Create: `lib/media_centarr/watcher/reconciler.ex`
- Create: `test/media_centarr/watcher/reconciler_test.exs`

- [ ] **Step 5.1: Write failing tests.**

```elixir
# test/media_centarr/watcher/reconciler_test.exs
defmodule MediaCentarr.Watcher.ReconcilerTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.Reconciler

  defp entry(id, dir, opts \\ []) do
    %{"id" => id, "dir" => dir, "images_dir" => opts[:images_dir], "name" => opts[:name]}
  end

  test "no change returns no actions" do
    list = [entry("a", "/mnt/a")]
    assert %{to_start: [], to_stop: [], to_replace: []} = Reconciler.diff(list, list)
  end

  test "new entry → to_start" do
    assert %{to_start: [%{"dir" => "/mnt/b"}], to_stop: [], to_replace: []} =
             Reconciler.diff([], [entry("b", "/mnt/b")])
  end

  test "removed entry → to_stop" do
    assert %{to_start: [], to_stop: ["/mnt/a"], to_replace: []} =
             Reconciler.diff([entry("a", "/mnt/a")], [])
  end

  test "dir changed → to_replace" do
    old = [entry("a", "/mnt/a")]
    new = [entry("a", "/mnt/a2")]

    assert %{
             to_start: [],
             to_stop: [],
             to_replace: [%{old_dir: "/mnt/a", new: %{"dir" => "/mnt/a2"}}]
           } = Reconciler.diff(old, new)
  end

  test "images_dir changed → to_replace" do
    old = [entry("a", "/mnt/a", images_dir: nil)]
    new = [entry("a", "/mnt/a", images_dir: "/mnt/ssd")]

    assert %{to_replace: [%{old_dir: "/mnt/a", new: %{"images_dir" => "/mnt/ssd"}}]} =
             Reconciler.diff(old, new)
  end

  test "name-only change is a no-op" do
    old = [entry("a", "/mnt/a", name: nil)]
    new = [entry("a", "/mnt/a", name: "Movies")]
    assert %{to_start: [], to_stop: [], to_replace: []} = Reconciler.diff(old, new)
  end

  test "mixed: add + remove + replace + no-op in one diff" do
    old = [entry("a", "/mnt/a"), entry("b", "/mnt/b"), entry("c", "/mnt/c")]
    new = [entry("a", "/mnt/a"), entry("b", "/mnt/b2"), entry("d", "/mnt/d")]

    result = Reconciler.diff(old, new)
    assert Enum.map(result.to_start, & &1["dir"]) == ["/mnt/d"]
    assert result.to_stop == ["/mnt/c"]
    assert [%{old_dir: "/mnt/b", new: %{"dir" => "/mnt/b2"}}] = result.to_replace
  end
end
```

- [ ] **Step 5.2:** Run `mix test test/media_centarr/watcher/reconciler_test.exs`. Expect 7 failures.

- [ ] **Step 5.3: Implement.**

```elixir
# lib/media_centarr/watcher/reconciler.ex
defmodule MediaCentarr.Watcher.Reconciler do
  @moduledoc """
  Pure diff calculator for watcher reconcile actions.

  Given the previous and current watch-dir entry lists, computes which
  watcher children need to start, stop, or be replaced (stop + start).
  A replace is emitted when `dir` or `images_dir` changes for an id
  present in both lists. A name-only change is a no-op.
  """

  @type entry :: %{required(String.t()) => String.t() | nil}
  @type diff :: %{
          to_start: [entry()],
          to_stop: [String.t()],
          to_replace: [%{old_dir: String.t(), new: entry()}]
        }

  @spec diff([entry()], [entry()]) :: diff()
  def diff(old_entries, new_entries) do
    old_by_id = Map.new(old_entries, &{&1["id"], &1})
    new_by_id = Map.new(new_entries, &{&1["id"], &1})

    old_ids = MapSet.new(Map.keys(old_by_id))
    new_ids = MapSet.new(Map.keys(new_by_id))

    added = MapSet.difference(new_ids, old_ids)
    removed = MapSet.difference(old_ids, new_ids)
    kept = MapSet.intersection(old_ids, new_ids)

    %{
      to_start: Enum.map(added, &Map.fetch!(new_by_id, &1)),
      to_stop: Enum.map(removed, fn id -> old_by_id[id]["dir"] end),
      to_replace:
        kept
        |> Enum.flat_map(fn id ->
          old = old_by_id[id]
          new = new_by_id[id]

          if old["dir"] != new["dir"] or old["images_dir"] != new["images_dir"] do
            [%{old_dir: old["dir"], new: new}]
          else
            []
          end
        end)
    }
  end
end
```

- [ ] **Step 5.4:** `mix test test/media_centarr/watcher/reconciler_test.exs` — 7 pass.

- [ ] **Step 5.5:** `jj desc -m "feat(watcher): add Reconciler.diff/2 pure function"`

---

### Task 6: `Watcher.Supervisor.reconcile/1` + live subscribe

**Files:**
- Modify: `lib/media_centarr/watcher/supervisor.ex`

- [ ] **Step 6.1:** Add reconcile as a public function. This is a stateful wrapper that takes the current entry list and applies the diff to running children. Uses `Reconciler` + existing `start_watchers`-style helpers.

```elixir
@doc """
Reconciles the set of running watcher children with `new_entries`:
starts new ones, terminates removed ones, and replaces entries whose
`dir` or `images_dir` changed. Name-only changes are no-ops.

Called whenever `Config` broadcasts `{:config_updated, :watch_dirs, …}`.
"""
@spec reconcile([map()]) :: :ok
def reconcile(new_entries) when is_list(new_entries) do
  old_entries = currently_running_entries()
  actions = MediaCentarr.Watcher.Reconciler.diff(old_entries, new_entries)

  Enum.each(actions.to_stop, &stop_dir/1)
  Enum.each(actions.to_replace, fn %{old_dir: old, new: new} ->
    stop_dir(old)
    start_dir(new["dir"])
  end)
  Enum.each(actions.to_start, fn new -> start_dir(new["dir"]) end)

  :ok
end

defp currently_running_entries do
  # Reconstruct an "entries"-shaped list from the Registry so the pure
  # diff can compare id-for-id. We use dir as both id and dir here,
  # because the Registry only knows paths.
  MediaCentarr.Watcher.Registry
  |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  |> Enum.map(fn dir ->
    %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}
  end)
end

defp start_dir(dir) do
  case DynamicSupervisor.start_child(
         MediaCentarr.Watcher.DynamicSupervisor,
         {MediaCentarr.Watcher, dir}
       ) do
    {:ok, _} -> :ok
    {:error, {:already_started, _}} -> :ok
    {:error, reason} ->
      Log.warning(:watcher, "reconcile: failed to start #{dir}: #{inspect(reason)}")
  end
end

defp stop_dir(dir) do
  case Registry.lookup(MediaCentarr.Watcher.Registry, dir) do
    [{pid, _}] -> DynamicSupervisor.terminate_child(MediaCentarr.Watcher.DynamicSupervisor, pid)
    [] -> :ok
  end
end
```

- [ ] **Step 6.2:** Switch subscription: convert `Watcher.Supervisor` into a `GenServer` sibling that subscribes + delegates reconciles, OR — simpler — add a thin `Watcher.ConfigListener` GenServer that subscribes to `Topics.config_updates()` and calls `Watcher.Supervisor.reconcile/1`. Recommendation: the latter. Create `lib/media_centarr/watcher/config_listener.ex`:

```elixir
defmodule MediaCentarr.Watcher.ConfigListener do
  @moduledoc """
  Subscribes to `Topics.config_updates()` and calls
  `Watcher.Supervisor.reconcile/1` on every watch-dir change.
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.config_updates())
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, :watch_dirs, entries}, state) do
    MediaCentarr.Watcher.Supervisor.reconcile(entries)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
```

- [ ] **Step 6.3:** Add `ConfigListener` as a child in `Watcher.Supervisor.init/1` after the DynamicSupervisors:

```elixir
children = [
  {Registry, keys: :unique, name: MediaCentarr.Watcher.Registry},
  {Registry, keys: :unique, name: MediaCentarr.Watcher.DirMonitor.Registry},
  {DynamicSupervisor, name: MediaCentarr.Watcher.DynamicSupervisor, strategy: :one_for_one},
  {DynamicSupervisor,
   name: MediaCentarr.Watcher.DirMonitor.DynamicSupervisor, strategy: :one_for_one},
  MediaCentarr.Watcher.ConfigListener
]
```

- [ ] **Step 6.4: Integration test.** Create `test/media_centarr/watcher/supervisor_reconcile_test.exs`:

```elixir
defmodule MediaCentarr.Watcher.SupervisorReconcileTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Watcher.Supervisor, as: WatcherSup

  @tag :integration
  test "put_watch_dirs triggers reconcile that starts a watcher" do
    on_exit(fn -> :ok = Config.put_watch_dirs([]) end)

    tmp = System.tmp_dir!() |> Path.join("watcher-reconcile-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    :ok = Config.put_watch_dirs([
      %{"id" => "t1", "dir" => tmp, "images_dir" => nil, "name" => nil}
    ])

    # Give the ConfigListener a moment to process the broadcast
    Process.sleep(50)
    dirs = WatcherSup.statuses() |> Enum.map(& &1.dir)
    assert tmp in dirs

    :ok = Config.put_watch_dirs([])
    Process.sleep(50)
    assert WatcherSup.statuses() == []
  end
end
```

- [ ] **Step 6.5:** `mix test test/media_centarr/watcher/` — expect passes.

- [ ] **Step 6.6:** `jj desc -m "feat(watcher): live reconcile on config changes"`

---

## Phase 3 — DirValidator

### Task 7: Pure validator with injected FS adapter

**Files:**
- Create: `lib/media_centarr/watcher/dir_validator.ex`
- Create: `test/media_centarr/watcher/dir_validator_test.exs`

- [ ] **Step 7.1: Write failing tests (all 11 rules).** Tests use a stub FS adapter and async mode.

```elixir
# test/media_centarr/watcher/dir_validator_test.exs
defmodule MediaCentarr.Watcher.DirValidatorTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.DirValidator

  defp stub_fs(overrides \\ %{}) do
    defaults = %{
      exists?: fn _ -> true end,
      dir?: fn _ -> true end,
      readable?: fn _ -> true end,
      ls: fn _ -> {:ok, []} end,
      touch: fn _ -> :ok end,
      expand: &Path.expand/1,
      mount_for: fn _ -> {:ok, "/"} end,
      mounted?: fn _ -> true end
    }

    Map.merge(defaults, overrides)
  end

  defp candidate(dir, opts \\ []) do
    %{
      "id" => opts[:id],
      "dir" => dir,
      "images_dir" => opts[:images_dir],
      "name" => opts[:name]
    }
  end

  describe "dir field — existence/type/readability" do
    test "passes when path exists, is a dir, and is readable" do
      assert %{errors: [], warnings: _} =
               DirValidator.validate(candidate("/mnt/a"), [], stub_fs())
    end

    test "errors when path does not exist" do
      fs = stub_fs(%{exists?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_found}, &1))
    end

    test "errors when path is not a directory" do
      fs = stub_fs(%{dir?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_a_directory}, &1))
    end

    test "errors when path is not readable" do
      fs = stub_fs(%{readable?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_readable}, &1))
    end
  end

  describe "dir field — duplicate/nested" do
    test "errors when dir duplicates an existing entry" do
      existing = [candidate("/mnt/a", id: "existing")]
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), existing, stub_fs())
      assert Enum.any?(errors, &match?({:dir, :duplicate}, &1))
    end

    test "edit of self is not a duplicate" do
      existing = [candidate("/mnt/a", id: "me")]
      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/a", id: "me"), existing, stub_fs())

      refute Enum.any?(errors, &match?({:dir, :duplicate}, &1))
    end

    test "errors when dir is nested inside an existing entry" do
      existing = [candidate("/mnt/videos", id: "root")]
      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/videos/movies"), existing, stub_fs())
      assert Enum.any?(errors, &match?({:dir, :nested}, &1))
    end

    test "errors when dir contains an existing entry" do
      existing = [candidate("/mnt/videos/movies", id: "child")]
      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/videos"), existing, stub_fs())
      assert Enum.any?(errors, &match?({:dir, :contains_existing}, &1))
    end
  end

  describe "dir field — mount awareness" do
    test "warns when path is under an unmounted mount point" do
      fs = stub_fs(%{mounted?: fn _ -> false end, mount_for: fn _ -> {:ok, "/mnt/nas"} end})
      assert %{warnings: warnings} = DirValidator.validate(candidate("/mnt/nas/media"), [], fs)
      assert Enum.any?(warnings, &match?({:dir, :unmounted, _}, &1))
    end
  end

  describe "images_dir" do
    test "errors when images_dir is inside any watch dir" do
      existing = [candidate("/mnt/a", id: "existing")]
      fs = stub_fs()
      entry = candidate("/mnt/b", images_dir: "/mnt/a/cache")
      assert %{errors: errors} = DirValidator.validate(entry, existing, fs)
      assert Enum.any?(errors, &match?({:images_dir, :inside_watch_dir}, &1))
    end

    test "errors when images_dir cannot be created and does not exist" do
      fs =
        stub_fs(%{
          exists?: fn
            "/mnt/a" -> true
            "/mnt/unwritable/images" -> false
            "/mnt/unwritable" -> true
            _ -> true
          end,
          touch: fn _ -> {:error, :eacces} end
        })

      entry = candidate("/mnt/a", images_dir: "/mnt/unwritable/images")
      assert %{errors: errors} = DirValidator.validate(entry, [], fs)
      assert Enum.any?(errors, &match?({:images_dir, :unwritable}, &1))
    end
  end

  describe "name" do
    test "errors when name duplicates another entry's name" do
      existing = [candidate("/mnt/a", id: "existing", name: "Movies")]
      entry = candidate("/mnt/b", name: "Movies")
      assert %{errors: errors} = DirValidator.validate(entry, existing, stub_fs())
      assert Enum.any?(errors, &match?({:name, :duplicate}, &1))
    end

    test "errors when name exceeds 60 characters" do
      long = String.duplicate("x", 61)
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a", name: long), [], stub_fs())
      assert Enum.any?(errors, &match?({:name, :too_long}, &1))
    end

    test "empty name is allowed" do
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a", name: nil), [], stub_fs())
      refute Enum.any?(errors, &match?({:name, _}, &1))
    end
  end

  describe "preview" do
    test "returns preview counts based on ls" do
      fs =
        stub_fs(%{
          ls: fn _ ->
            {:ok, ["movie.mkv", "show.mp4", "notes.txt", "subdir"]}
          end,
          dir?: fn
            "/mnt/a" -> true
            "/mnt/a/subdir" -> true
            _ -> false
          end
        })

      assert %{preview: %{video_count: 2, subdir_count: 1}} =
               DirValidator.validate(candidate("/mnt/a"), [], fs)
    end
  end
end
```

- [ ] **Step 7.2:** Run tests. Expect 14 failures.

- [ ] **Step 7.3: Implement.** Create `lib/media_centarr/watcher/dir_validator.ex`:

```elixir
defmodule MediaCentarr.Watcher.DirValidator do
  @moduledoc """
  Pure validator for watch-directory form entries.

  Returns `%{errors: [...], warnings: [...], preview: %{...}}`. Filesystem
  primitives are passed through an adapter map so the module is `async: true`
  test-safe and never touches the real disk during tests.
  """

  @video_exts ~w(.mkv .mp4 .avi .mov .m4v .webm .ts .wmv)

  @type rule :: atom()
  @type error :: {atom(), rule()} | {atom(), rule(), any()}

  def validate(%{} = entry, existing, fs) do
    dir = entry["dir"] |> normalize(fs)
    errors = []
    warnings = []

    {errors, dir_ok?} = validate_dir_existence(errors, dir, fs)
    {errors, _} = maybe_validate_dir_shape(errors, dir, fs, dir_ok?)
    {errors, _} = maybe_validate_dir_readable(errors, dir, fs, dir_ok?)
    errors = validate_duplicate(errors, entry, existing, fs)
    errors = validate_nesting(errors, entry, existing, fs)
    warnings = validate_mount(warnings, dir, fs)
    errors = validate_images_dir(errors, entry, existing, fs)
    errors = validate_name(errors, entry, existing)

    preview = if dir_ok?, do: build_preview(dir, fs), else: nil

    %{errors: errors, warnings: warnings, preview: preview}
  end

  # --- rules ---

  defp validate_dir_existence(errors, nil, _fs), do: {[{:dir, :not_found} | errors], false}

  defp validate_dir_existence(errors, dir, fs) do
    if fs.exists?.(dir), do: {errors, true}, else: {[{:dir, :not_found} | errors], false}
  end

  defp maybe_validate_dir_shape(errors, _dir, _fs, false), do: {errors, false}

  defp maybe_validate_dir_shape(errors, dir, fs, true) do
    if fs.dir?.(dir), do: {errors, true}, else: {[{:dir, :not_a_directory} | errors], false}
  end

  defp maybe_validate_dir_readable(errors, _dir, _fs, false), do: {errors, false}

  defp maybe_validate_dir_readable(errors, dir, fs, true) do
    if fs.readable?.(dir), do: {errors, true}, else: {[{:dir, :not_readable} | errors], false}
  end

  defp validate_duplicate(errors, entry, existing, fs) do
    dir = normalize(entry["dir"], fs)
    id = entry["id"]

    duplicate? =
      Enum.any?(existing, fn e ->
        e["id"] != id and normalize(e["dir"], fs) == dir
      end)

    if duplicate?, do: [{:dir, :duplicate} | errors], else: errors
  end

  defp validate_nesting(errors, entry, existing, fs) do
    dir = normalize(entry["dir"], fs)
    id = entry["id"]

    others = Enum.reject(existing, &(&1["id"] == id))

    errors
    |> maybe_add(Enum.any?(others, fn e -> nested_under?(dir, normalize(e["dir"], fs)) end),
      {:dir, :nested})
    |> maybe_add(Enum.any?(others, fn e -> nested_under?(normalize(e["dir"], fs), dir) end),
      {:dir, :contains_existing})
  end

  defp nested_under?(a, b) when is_binary(a) and is_binary(b) do
    a != b and String.starts_with?(a, b <> "/")
  end

  defp nested_under?(_, _), do: false

  defp validate_mount(warnings, nil, _fs), do: warnings

  defp validate_mount(warnings, dir, fs) do
    with {:ok, mount} <- fs.mount_for.(dir),
         false <- fs.mounted?.(mount) do
      [{:dir, :unmounted, mount} | warnings]
    else
      _ -> warnings
    end
  end

  defp validate_images_dir(errors, %{"images_dir" => nil}, _existing, _fs), do: errors

  defp validate_images_dir(errors, %{"images_dir" => images_dir} = entry, existing, fs) do
    images_dir = normalize(images_dir, fs)

    errors
    |> maybe_add(inside_any_watch_dir?(images_dir, entry, existing, fs),
      {:images_dir, :inside_watch_dir})
    |> maybe_add(not writable?(images_dir, fs), {:images_dir, :unwritable})
  end

  defp inside_any_watch_dir?(images_dir, entry, existing, fs) do
    watch_dirs =
      [entry | existing]
      |> Enum.uniq_by(& &1["id"])
      |> Enum.map(&normalize(&1["dir"], fs))

    Enum.any?(watch_dirs, fn dir -> nested_under?(images_dir, dir) end)
  end

  defp writable?(path, fs) do
    cond do
      fs.exists?.(path) ->
        fs.touch.(Path.join(path, ".media-centarr-write-test")) == :ok

      true ->
        parent = Path.dirname(path)

        fs.exists?.(parent) and
          fs.touch.(Path.join(parent, ".media-centarr-write-test")) == :ok
    end
  end

  defp validate_name(errors, %{"name" => nil}, _), do: errors
  defp validate_name(errors, %{"name" => ""}, _), do: errors

  defp validate_name(errors, %{"name" => name, "id" => id}, existing) do
    trimmed = String.trim(name)

    errors
    |> maybe_add(String.length(trimmed) > 60, {:name, :too_long})
    |> maybe_add(
      Enum.any?(existing, fn e -> e["id"] != id and e["name"] == trimmed end),
      {:name, :duplicate}
    )
  end

  defp build_preview(dir, fs) do
    case fs.ls.(dir) do
      {:ok, entries} ->
        video_count =
          Enum.count(entries, fn name ->
            ext = name |> Path.extname() |> String.downcase()
            ext in @video_exts
          end)

        subdir_count =
          Enum.count(entries, fn name -> fs.dir?.(Path.join(dir, name)) end)

        %{video_count: video_count, subdir_count: subdir_count}

      _ ->
        nil
    end
  end

  defp maybe_add(errors, true, item), do: [item | errors]
  defp maybe_add(errors, false, _), do: errors

  defp normalize(nil, _fs), do: nil
  defp normalize(path, fs), do: fs.expand.(path)
end
```

- [ ] **Step 7.4:** Add a real FS adapter constructor at the bottom of the module:

```elixir
@doc "Returns the production filesystem adapter."
def real_fs do
  %{
    exists?: &File.exists?/1,
    dir?: &File.dir?/1,
    readable?: fn path ->
      case File.stat(path) do
        {:ok, %File.Stat{access: a}} when a in [:read, :read_write] -> true
        _ -> false
      end
    end,
    ls: &File.ls/1,
    touch: fn path ->
      case File.touch(path) do
        :ok -> _ = File.rm(path); :ok
        err -> err
      end
    end,
    expand: &Path.expand/1,
    mount_for: &mount_for/1,
    mounted?: &mounted?/1
  }
end

defp mount_for(path) do
  case File.read("/proc/mounts") do
    {:ok, contents} ->
      mount =
        contents
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          [_dev, mp | _] = String.split(line, " ", parts: 3)
          mp
        end)
        |> Enum.filter(fn mp -> path == mp or String.starts_with?(path, mp <> "/") end)
        |> Enum.max_by(&String.length/1, fn -> "/" end)

      {:ok, mount}

    _ ->
      {:ok, "/"}
  end
end

defp mounted?(mount) do
  case File.read("/proc/mounts") do
    {:ok, contents} ->
      String.split(contents, "\n", trim: true)
      |> Enum.any?(fn line -> String.contains?(line, " " <> mount <> " ") end)

    _ ->
      true
  end
end
```

- [ ] **Step 7.5:** `mix test test/media_centarr/watcher/dir_validator_test.exs`. Expect 14 pass.

- [ ] **Step 7.6:** `jj desc -m "feat(watcher): pure DirValidator with 11 live validation rules"`

---

## Phase 4 — Settings UI

### Task 8: `WatchDirsLogic` pure helpers + tests

**Files:**
- Create: `lib/media_centarr_web/live/settings_live/watch_dirs_logic.ex`
- Create: `test/media_centarr_web/live/settings_live/watch_dirs_logic_test.exs`

- [ ] **Step 8.1: Write failing tests.**

```elixir
defmodule MediaCentarrWeb.SettingsLive.WatchDirsLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.SettingsLive.WatchDirsLogic

  defp entry(dir, opts \\ []), do: %{"id" => opts[:id] || dir, "dir" => dir, "images_dir" => opts[:images_dir], "name" => opts[:name]}

  test "display_label/1 falls back from name to dir" do
    assert WatchDirsLogic.display_label(entry("/mnt/a", name: "Movies")) == "Movies"
    assert WatchDirsLogic.display_label(entry("/mnt/a")) == "/mnt/a"
    assert WatchDirsLogic.display_label(entry("/mnt/a", name: "")) == "/mnt/a"
  end

  test "new_entry/0 returns a blank entry with a UUID id" do
    e = WatchDirsLogic.new_entry()
    assert is_binary(e["id"])
    assert e["dir"] == ""
    assert is_nil(e["images_dir"])
    assert is_nil(e["name"])
  end

  test "upsert/2 replaces an existing entry by id" do
    list = [entry("/mnt/a", id: "a"), entry("/mnt/b", id: "b")]
    updated = %{"id" => "a", "dir" => "/mnt/a2", "images_dir" => nil, "name" => nil}

    assert [
             %{"id" => "a", "dir" => "/mnt/a2"},
             %{"id" => "b"}
           ] = WatchDirsLogic.upsert(list, updated)
  end

  test "upsert/2 appends when id is not in the list" do
    list = [entry("/mnt/a", id: "a")]
    new = %{"id" => "c", "dir" => "/mnt/c", "images_dir" => nil, "name" => nil}

    assert [_, %{"id" => "c"}] = WatchDirsLogic.upsert(list, new)
  end

  test "remove/2 drops the entry with the given id" do
    list = [entry("/mnt/a", id: "a"), entry("/mnt/b", id: "b")]
    assert [%{"id" => "b"}] = WatchDirsLogic.remove(list, "a")
  end

  test "saveable?/1 is true only when no errors" do
    refute WatchDirsLogic.saveable?(%{errors: [{:dir, :not_found}], warnings: [], preview: nil})
    assert WatchDirsLogic.saveable?(%{errors: [], warnings: [], preview: nil})
    assert WatchDirsLogic.saveable?(%{errors: [], warnings: [{:dir, :unmounted, "/mnt/nas"}], preview: nil})
  end

  test "error_message/1 produces human-readable strings" do
    assert WatchDirsLogic.error_message({:dir, :not_found}) =~ "not found"
    assert WatchDirsLogic.error_message({:dir, :duplicate}) =~ "already configured"
    assert WatchDirsLogic.error_message({:dir, :nested}) =~ "nested"
    assert WatchDirsLogic.error_message({:name, :too_long}) =~ "60"
  end
end
```

- [ ] **Step 8.2:** Run the tests. Expect failures.

- [ ] **Step 8.3: Implement.**

```elixir
defmodule MediaCentarrWeb.SettingsLive.WatchDirsLogic do
  @moduledoc """
  Pure helpers for the Settings watch-dirs card and dialog.

  ADR-030: keep LiveView logic small by extracting reusable transformations
  and text formatting into this pure module. Tested with `async: true`.
  """

  @spec new_entry() :: map()
  def new_entry do
    %{"id" => Ecto.UUID.generate(), "dir" => "", "images_dir" => nil, "name" => nil}
  end

  @spec display_label(map()) :: String.t()
  def display_label(%{"name" => name, "dir" => dir}) do
    case name do
      n when is_binary(n) and n != "" -> n
      _ -> dir
    end
  end

  @spec upsert([map()], map()) :: [map()]
  def upsert(list, %{"id" => id} = entry) do
    if Enum.any?(list, &(&1["id"] == id)) do
      Enum.map(list, fn e -> if e["id"] == id, do: entry, else: e end)
    else
      list ++ [entry]
    end
  end

  @spec remove([map()], String.t()) :: [map()]
  def remove(list, id), do: Enum.reject(list, &(&1["id"] == id))

  @spec saveable?(map()) :: boolean()
  def saveable?(%{errors: errors}), do: errors == []

  @spec error_message({atom(), atom()} | {atom(), atom(), any()}) :: String.t()
  def error_message({:dir, :not_found}), do: "Path not found on this host."
  def error_message({:dir, :not_a_directory}), do: "Path is not a directory."
  def error_message({:dir, :not_readable}), do: "Path is not readable by the app."
  def error_message({:dir, :duplicate}), do: "This directory is already configured."
  def error_message({:dir, :nested}), do: "This directory is nested inside another configured directory."
  def error_message({:dir, :contains_existing}), do: "This directory contains another configured directory."
  def error_message({:dir, :unmounted, mount}), do: "Warning: #{mount} is not currently mounted."
  def error_message({:images_dir, :inside_watch_dir}), do: "Images directory cannot live inside a watch directory."
  def error_message({:images_dir, :unwritable}), do: "Images directory is not writable and cannot be created."
  def error_message({:name, :too_long}), do: "Name must be 60 characters or fewer."
  def error_message({:name, :duplicate}), do: "Another directory already uses this name."
end
```

- [ ] **Step 8.4:** Tests green.

- [ ] **Step 8.5:** `jj desc -m "feat(settings): WatchDirsLogic pure helpers for the UI"`

---

### Task 9: Settings LiveView card + dialog + events

**Files:**
- Modify: `lib/media_centarr_web/live/settings_live.ex`
- (optional, if it makes the LiveView cleaner) Create: `lib/media_centarr_web/live/settings_live/watch_dirs_component.ex` as a `Phoenix.Component`

Because settings_live.ex is already large, this task adds the new state + event handlers + template block inline, keeping the card markup in a function component for readability.

- [ ] **Step 9.1: Extend mount assigns.** In `settings_live.ex`, extend `mount/3` to load watch dirs from `Config.watch_dirs_entries()`, initialize dialog state:

```elixir
|> assign(:watch_dirs, MediaCentarr.Config.watch_dirs_entries())
|> assign(:watch_dir_dialog, nil)              # nil | %{entry, validation, debounce_timer}
|> assign(:watch_dir_delete_confirm, nil)      # nil | id
```

Also subscribe in `mount/3` (connected? branch) to the config topic:

```elixir
Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.config_updates())
```

- [ ] **Step 9.2: Handle params** — `handle_params/3` reads `?add_watch_dir=1` and opens the dialog with a fresh entry.

```elixir
@impl true
def handle_params(%{"add_watch_dir" => "1"} = _params, _uri, socket) do
  {:noreply, open_watch_dir_dialog(socket, WatchDirsLogic.new_entry())}
end

def handle_params(_params, _uri, socket), do: {:noreply, socket}
```

- [ ] **Step 9.3: Event handlers.** Add these `handle_event/3` clauses:

```elixir
def handle_event("watch_dir:open_add", _, socket) do
  {:noreply, open_watch_dir_dialog(socket, WatchDirsLogic.new_entry())}
end

def handle_event("watch_dir:open_edit", %{"id" => id}, socket) do
  entry = Enum.find(socket.assigns.watch_dirs, &(&1["id"] == id)) || WatchDirsLogic.new_entry()
  {:noreply, open_watch_dir_dialog(socket, entry)}
end

def handle_event("watch_dir:close", _, socket) do
  {:noreply, close_watch_dir_dialog(socket)}
end

def handle_event("watch_dir:validate", %{"entry" => params}, socket) do
  {:noreply, schedule_watch_dir_validation(socket, params)}
end

def handle_event("watch_dir:save", _, socket) do
  %{entry: entry, validation: validation} = socket.assigns.watch_dir_dialog

  if WatchDirsLogic.saveable?(validation) do
    entries = WatchDirsLogic.upsert(socket.assigns.watch_dirs, entry)
    :ok = MediaCentarr.Config.put_watch_dirs(entries)
    {:noreply, close_watch_dir_dialog(socket)}
  else
    {:noreply, socket}
  end
end

def handle_event("watch_dir:delete_confirm", %{"id" => id}, socket) do
  {:noreply, assign(socket, :watch_dir_delete_confirm, id)}
end

def handle_event("watch_dir:delete_cancel", _, socket) do
  {:noreply, assign(socket, :watch_dir_delete_confirm, nil)}
end

def handle_event("watch_dir:delete", %{"id" => id}, socket) do
  entries = WatchDirsLogic.remove(socket.assigns.watch_dirs, id)
  :ok = MediaCentarr.Config.put_watch_dirs(entries)
  {:noreply, assign(socket, :watch_dir_delete_confirm, nil)}
end
```

- [ ] **Step 9.4: handle_info clauses:**

```elixir
def handle_info({:config_updated, :watch_dirs, entries}, socket) do
  {:noreply, assign(socket, :watch_dirs, entries)}
end

def handle_info({:watch_dir_validate, params}, socket) do
  case socket.assigns.watch_dir_dialog do
    %{} = dialog ->
      entry = merge_entry(dialog.entry, params)

      validation =
        MediaCentarr.Watcher.DirValidator.validate(
          entry,
          other_entries(socket.assigns.watch_dirs, entry),
          MediaCentarr.Watcher.DirValidator.real_fs()
        )

      new_dialog = %{dialog | entry: entry, validation: validation, debounce_timer: nil}
      {:noreply, assign(socket, :watch_dir_dialog, new_dialog)}

    _ ->
      {:noreply, socket}
  end
end
```

- [ ] **Step 9.5: Private helpers in the LiveView:**

```elixir
defp open_watch_dir_dialog(socket, entry) do
  assign(socket, :watch_dir_dialog, %{
    entry: entry,
    validation: %{errors: [], warnings: [], preview: nil},
    debounce_timer: nil
  })
end

defp close_watch_dir_dialog(socket) do
  assign(socket, :watch_dir_dialog, nil)
end

defp schedule_watch_dir_validation(socket, params) do
  case socket.assigns.watch_dir_dialog do
    %{debounce_timer: timer} = dialog ->
      if timer, do: Process.cancel_timer(timer)
      t = Process.send_after(self(), {:watch_dir_validate, params}, 500)
      assign(socket, :watch_dir_dialog, %{dialog | debounce_timer: t})

    _ ->
      socket
  end
end

defp merge_entry(old, params) do
  %{
    "id" => old["id"],
    "dir" => params["dir"] || old["dir"],
    "images_dir" => nilify(params["images_dir"]) || old["images_dir"],
    "name" => nilify(params["name"]) || old["name"]
  }
end

defp nilify(""), do: nil
defp nilify(v), do: v

defp other_entries(list, entry) do
  Enum.reject(list, &(&1["id"] == entry["id"]))
end
```

- [ ] **Step 9.6: Template.** In the library section of the settings template, render:

```heex
<div class="glass-surface rounded-xl p-4 space-y-3">
  <div class="flex items-baseline justify-between">
    <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Watch Directories</h3>
    <button class="btn btn-soft btn-success btn-sm" phx-click="watch_dir:open_add">
      <.icon name="hero-plus" class="size-4" /> Add
    </button>
  </div>

  <div :if={@watch_dirs == []} class="text-base-content/60 py-4">
    No watch directories configured — your library is empty. Add one to get started.
  </div>

  <ul :if={@watch_dirs != []} class="space-y-2">
    <li :for={entry <- @watch_dirs} class="glass-inset rounded-lg p-3 flex items-baseline justify-between gap-3">
      <div class="min-w-0 flex-1 space-y-1">
        <div class="font-medium">{WatchDirsLogic.display_label(entry)}</div>
        <div class="truncate-left text-sm text-base-content/60" title={entry["dir"]}>
          <bdo dir="ltr">{entry["dir"]}</bdo>
        </div>
        <div :if={entry["images_dir"]} class="truncate-left text-xs text-base-content/50" title={entry["images_dir"]}>
          <bdo dir="ltr">images: {entry["images_dir"]}</bdo>
        </div>
      </div>

      <div class="flex gap-1">
        <button class="btn btn-ghost btn-sm" phx-click="watch_dir:open_edit" phx-value-id={entry["id"]}>
          Edit
        </button>
        <%= if @watch_dir_delete_confirm == entry["id"] do %>
          <button class="btn btn-soft btn-error btn-sm" phx-click="watch_dir:delete" phx-value-id={entry["id"]}>
            Confirm
          </button>
          <button class="btn btn-ghost btn-sm" phx-click="watch_dir:delete_cancel">Cancel</button>
        <% else %>
          <button class="btn btn-ghost btn-sm text-error" phx-click="watch_dir:delete_confirm" phx-value-id={entry["id"]}>
            <.icon name="hero-trash" class="size-4" />
          </button>
        <% end %>
      </div>
    </li>
  </ul>
</div>
```

- [ ] **Step 9.7: Dialog template.** Always render (ADR — backdrop-filter):

```heex
<ModalShell.modal_shell
  open={@watch_dir_dialog != nil}
  on_close="watch_dir:close"
>
  <:title>{if @watch_dir_dialog && Enum.any?(@watch_dirs, &(&1["id"] == @watch_dir_dialog.entry["id"])), do: "Edit watch directory", else: "Add watch directory"}</:title>

  <form :if={@watch_dir_dialog} phx-change="watch_dir:validate" phx-submit="watch_dir:save" class="space-y-3">
    <div>
      <label class="text-sm font-medium">Directory</label>
      <input type="text" name="entry[dir]" value={@watch_dir_dialog.entry["dir"]} class="library-filter w-full" />
      <.watch_dir_errors errors={@watch_dir_dialog.validation.errors} field={:dir} />
    </div>

    <div>
      <label class="text-sm font-medium">Name <span class="text-base-content/50">(optional)</span></label>
      <input type="text" name="entry[name]" value={@watch_dir_dialog.entry["name"]} class="library-filter w-full" />
      <.watch_dir_errors errors={@watch_dir_dialog.validation.errors} field={:name} />
    </div>

    <details>
      <summary class="cursor-pointer text-sm text-base-content/60">Advanced — images directory</summary>
      <div class="mt-2">
        <input type="text" name="entry[images_dir]" value={@watch_dir_dialog.entry["images_dir"]} class="library-filter w-full" placeholder="Leave blank to use the default" />
        <.watch_dir_errors errors={@watch_dir_dialog.validation.errors} field={:images_dir} />
      </div>
    </details>

    <div :if={@watch_dir_dialog.validation.preview} class="glass-inset rounded-lg p-3 text-sm text-base-content/70">
      Found {@watch_dir_dialog.validation.preview.video_count} video files, {@watch_dir_dialog.validation.preview.subdir_count} subdirectories.
    </div>

    <div :for={warning <- @watch_dir_dialog.validation.warnings} class="text-warning text-sm">
      {WatchDirsLogic.error_message(warning)}
    </div>

    <div class="flex justify-end gap-2 pt-2">
      <button type="button" class="btn btn-ghost" phx-click="watch_dir:close">Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={not WatchDirsLogic.saveable?(@watch_dir_dialog.validation)}>
        Save
      </button>
    </div>
  </form>
</ModalShell.modal_shell>
```

Add the `watch_dir_errors` function component near the bottom of the module:

```elixir
attr :errors, :list, required: true
attr :field, :atom, required: true

defp watch_dir_errors(assigns) do
  ~H"""
  <div :for={err <- Enum.filter(@errors, fn
    {^@field, _} -> true
    {^@field, _, _} -> true
    _ -> false
  end)} class="text-error text-sm">
    {WatchDirsLogic.error_message(err)}
  </div>
  """
end
```

- [ ] **Step 9.8: Alias WatchDirsLogic** at the top of `settings_live.ex`:

```elixir
alias MediaCentarrWeb.SettingsLive.WatchDirsLogic
```

- [ ] **Step 9.9:** Run `mix compile --warnings-as-errors`.

- [ ] **Step 9.10: LiveView integration test** in `test/media_centarr_web/live/settings_live_watch_dirs_test.exs`:

```elixir
defmodule MediaCentarrWeb.SettingsLiveWatchDirsTest do
  use MediaCentarrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  setup do
    on_exit(fn -> :ok = Config.put_watch_dirs([]) end)
    :ok
  end

  test "deep link opens the add dialog", %{conn: conn} do
    {:ok, view, html} = live(conn, "/settings?section=library&add_watch_dir=1")
    assert html =~ "Add watch directory"
    assert render(view) =~ "name=\"entry[dir]\""
  end

  test "save persists and closes the dialog", %{conn: conn} do
    tmp = System.tmp_dir!() |> Path.join("wd-save-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, view, _} = live(conn, "/settings?section=library&add_watch_dir=1")

    view
    |> form("form", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_change()

    # Wait for debounced validation
    :timer.sleep(600)

    view
    |> form("form", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_submit()

    assert Config.watch_dirs_entries() |> Enum.map(& &1["dir"]) == [Path.expand(tmp)]
  end

  test "duplicate save is rejected", %{conn: conn} do
    tmp = System.tmp_dir!() |> Path.join("wd-dup-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "existing", "dir" => Path.expand(tmp), "images_dir" => nil, "name" => nil}
      ])

    {:ok, view, _} = live(conn, "/settings?section=library&add_watch_dir=1")

    view
    |> form("form", entry: %{dir: tmp, name: "", images_dir: ""})
    |> render_change()

    :timer.sleep(600)

    html = render(view)
    assert html =~ "already configured"
  end
end
```

- [ ] **Step 9.11:** `mix test test/media_centarr_web/live/settings_live_watch_dirs_test.exs` — green.

- [ ] **Step 9.12:** `jj desc -m "feat(settings-ui): watch-dirs card, add/edit dialog, delete flow"`

---

## Phase 5 — Cleanup + docs

### Task 10: Remove `watch_dirs` from defaults TOML

**Files:**
- Modify: `defaults/media-centarr.toml`

- [ ] **Step 10.1:** Replace the `watch_dirs` section (lines ~11-23) with:

```toml
# Watch directories are configured in the app: open Settings → Library →
# Watch Directories. The first boot of a new install imports any TOML
# watch_dirs found here, after which this key is ignored.
```

Leave the key itself out. `Config.load_toml` already defaults to `[]` when absent; the migration uses `Application.get_env(:media_centarr, :__raw_toml_watch_dirs, [])`.

- [ ] **Step 10.2:** Verify existing user TOML files are still parsed (migration still runs) — no action needed; `resolve_watch_dirs/2` already handles absent keys.

- [ ] **Step 10.3:** `jj desc -m "chore(config): remove watch_dirs from defaults TOML (moved to UI)"`

---

### Task 11: Full-suite pre-commit check

- [ ] **Step 11.1:** Run `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`. Expect green across compile/format/credo/sobelow/tests.

- [ ] **Step 11.2:** Run `bun test assets/js/input/` — still green (no JS changes but nothing should regress).

- [ ] **Step 11.3:** Manually exercise the UI:
  1. `mix phx.server`
  2. Visit `/settings?section=library` → click Add → type a valid path → watch validation turn green → Save
  3. Confirm the watcher process appears in `/status` or via `WatcherSupervisor.statuses()` from IEx
  4. Edit the entry, change the name only → no watcher restart (tail `journalctl --user -u media-centarr-dev -f`)
  5. Delete → confirm → watcher process gone
  6. Reload the app → entries survive

- [ ] **Step 11.4:** `jj desc -m "feat(watch-dirs): ship UI-managed watch directories with live reconcile"` (or append a combined summary if the individual task descriptions are preferred in history — leave as-is if so).

---

### Task 12: Wiki updates (follow-up — separate repo)

**Files (separate repo, `~/src/media-centarr/media-centarr.wiki/`):**
- `Configuration-File.md` — remove `watch_dirs` reference; point to Settings UI
- `Adding-Your-Library.md` — rewrite the "how to add a library" flow to use the Settings UI (screenshots helpful)
- `Settings-Reference.md` — document the new "Watch Directories" card

- [ ] **Step 12.1:** Open the wiki repo alongside the main repo if not already cloned.

- [ ] **Step 12.2:** Edit the three pages listed.

- [ ] **Step 12.3:**
```bash
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: watch dirs are now managed in the Settings UI"
jj bookmark set master -r @
jj git push
```

---

## Self-review

**Spec coverage:**
- Data model (UUID id, dir, images_dir, name) — Tasks 2, 3, 8 ✓
- TOML → Settings migration (idempotent) — Task 3 ✓
- `Config.watch_dirs/0` contract unchanged — Task 2 (refresh_watch_dirs_persistent_term preserves `:watch_dirs` and `:watch_dir_images`) ✓
- Live reconcile (start/stop/replace, name-only no-op) — Tasks 5, 6 ✓
- All 11 validation rules — Task 7 ✓
- Settings UI card + dialog (always-in-DOM, deep link, delete confirm) — Task 9 ✓
- Testing at each layer (pure + DataCase + LiveView) — Tasks 2/3/5/7/8/9 ✓
- Defaults TOML cleanup — Task 10 ✓
- Wiki updates — Task 12 ✓

**Placeholder scan:** all code blocks contain real code; no TBD/TODO. "Warning: add error handling" patterns absent.

**Type consistency:** entry maps use `"id"`, `"dir"`, `"images_dir"`, `"name"` consistently across validator, reconciler, logic, settings live, tests. Error tuples use `{field, reason}` or `{field, reason, detail}` consistently. `saveable?/1` reads `:errors` key across both the validator return and the logic module.

---

**Plan complete and saved to** `docs/superpowers/plans/2026-04-19-watch-dirs-runtime-config.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
