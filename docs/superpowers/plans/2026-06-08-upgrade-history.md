# Upgrade History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a newest-first list of versions the app has run (version + date) on the Status → Updates subsystem drill-in.

**Architecture:** A new `MediaCentaur.SelfUpdate.History` module records the running version into `Settings.Entry` (key `update.history`) at each boot, but only when the version changed (path-agnostic upgrade detection). `SelfUpdate.boot!/0` drives it; `SelfUpdate.upgrade_history/0` exposes it. `StatusLive` loads it into an assign at mount and the `self_update_widget` renders it.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto (SQLite via `Settings.Entry`), Phoenix Storybook, ExUnit (`MediaCentaur.DataCase`).

**Spec:** `docs/superpowers/specs/2026-06-08-upgrade-history-design.md`

**Conventions to honor:**
- Test-first (`automated-testing` skill): write the failing test, watch it fail, then implement.
- `SelfUpdate` boundary already declares `deps: [MediaCentaur.Settings]`; `History` lives inside it and may use `Settings` + `MediaCentaur.Version`.
- Storage parallels the existing `MediaCentaur.SelfUpdate.Storage` module (same `Settings.find_or_create_entry!/1` upsert + `Settings.get_by_key/1` read pattern).
- No real show titles / generic content rules don't apply here (versions only).

---

## File Structure

- **Create** `lib/media_centaur/self_update/history.ex` — the history log (record + list + storage encode/decode). One responsibility: the durable list of versions-run.
- **Create** `test/media_centaur/self_update/history_test.exs` — unit tests for the module.
- **Modify** `lib/media_centaur/self_update.ex` — add `History` alias, call `History.record_boot_version/0` in `boot!/0`, add public `upgrade_history/0`.
- **Modify** `lib/media_centaur_web/components/activity_widget_components.ex` — add `attr :history`, render the History section, add `history_date/1` helper.
- **Modify** `storybook/status/self_update_widget.story.exs` — add `history` to base + a `:with_history` variation (MC0009).
- **Modify** `lib/media_centaur_web/live/status_live.ex` — default `self_update_history` in `assign_defaults/1`, load it in `assign_self_update/1`, pass it in `activity_bundle/1`.

---

## Task 1: `History` module — record, dedup, cap, list

**Files:**
- Create: `lib/media_centaur/self_update/history.ex`
- Test: `test/media_centaur/self_update/history_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur/self_update/history_test.exs`:

```elixir
defmodule MediaCentaur.SelfUpdate.HistoryTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.SelfUpdate.History

  describe "record_boot_version/1 + list/0" do
    test "records the version when the log is empty" do
      assert :ok = History.record_boot_version("0.82.0")

      assert [%{version: "0.82.0", recorded_at: %DateTime{}}] = History.list()
    end

    test "records a new entry, newest-first, when the version changed" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.83.0")

      assert [%{version: "0.83.0"}, %{version: "0.82.0"}] = History.list()
    end

    test "is a no-op when the version is unchanged" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.82.0")

      assert [%{version: "0.82.0"}] = History.list()
    end

    test "caps the stored list at 50 entries, dropping the oldest" do
      for n <- 1..55, do: History.record_boot_version("0.0.#{n}")

      entries = History.list()
      assert length(entries) == 50
      # newest-first: most recent recorded is the head, oldest survivors at the tail
      assert hd(entries).version == "0.0.55"
      assert List.last(entries).version == "0.0.6"
    end

    test "list/0 returns [] when nothing has been recorded" do
      assert History.list() == []
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/self_update/history_test.exs`
Expected: FAIL — `MediaCentaur.SelfUpdate.History` is undefined / module not available.

- [ ] **Step 3: Write minimal implementation**

Create `lib/media_centaur/self_update/history.ex`:

```elixir
defmodule MediaCentaur.SelfUpdate.History do
  @moduledoc """
  Durable log of the versions this install has run, for the Status → Updates
  drill-in's history list.

  Captured by boot-time version detection: `record_boot_version/1` appends the
  running version only when it differs from the newest recorded entry, so the
  log gains one row per actual upgrade regardless of how that upgrade happened
  (in-app "Update now", manual reinstall, or installer script). `recorded_at`
  is the boot-observation time — effectively the upgrade moment.

  Persisted via `MediaCentaur.Settings.Entry` under `update.history`, mirroring
  the rest of the SelfUpdate subsystem (no dedicated table). The list is kept
  newest-first and capped at #{50} entries — a small, append-only display log.
  """

  alias MediaCentaur.Settings

  @key "update.history"
  @max_entries 50

  @type entry :: %{version: String.t(), recorded_at: DateTime.t()}

  @doc """
  Records the currently running version. Appends a new newest-first entry only
  when it differs from the most recent recorded version (or the log is empty).
  Defaults to `MediaCentaur.Version.current_version/0`; the arity-1 form exists
  for tests to drive version transitions.
  """
  @spec record_boot_version() :: :ok
  def record_boot_version, do: record_boot_version(MediaCentaur.Version.current_version())

  @spec record_boot_version(String.t()) :: :ok
  def record_boot_version(version) when is_binary(version) do
    raw = read_entries()

    case raw do
      [%{"version" => ^version} | _] ->
        :ok

      _ ->
        new_entry = %{"version" => version, "recorded_at" => DateTime.to_iso8601(DateTime.utc_now())}
        entries = Enum.take([new_entry | raw], @max_entries)
        Settings.find_or_create_entry!(%{key: @key, value: %{"entries" => entries}})
        :ok
    end
  end

  @doc "Returns the recorded versions newest-first, as `%{version, recorded_at}` maps."
  @spec list() :: [entry()]
  def list do
    read_entries()
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  defp read_entries do
    case Settings.get_by_key(@key) do
      {:ok, %{value: %{"entries" => entries}}} when is_list(entries) -> entries
      _ -> []
    end
  end

  defp decode(%{"version" => version, "recorded_at" => iso}) when is_binary(version) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> %{version: version, recorded_at: at}
      _ -> nil
    end
  end

  defp decode(_), do: nil
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/media_centaur/self_update/history_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/self_update/history.ex test/media_centaur/self_update/history_test.exs
git commit -m "feat(self-update): record per-boot version history"
```

---

## Task 2: Wire boot capture + public API

**Files:**
- Modify: `lib/media_centaur/self_update.ex` (alias list ~line 33, `boot!/0` ~line 237, add `upgrade_history/0`)
- Test: `test/media_centaur/self_update/history_test.exs` (add a facade test)

- [ ] **Step 1: Write the failing test**

Append a new `describe` block to `test/media_centaur/self_update/history_test.exs`:

```elixir
  describe "SelfUpdate.upgrade_history/0" do
    test "delegates to History.list/0, newest-first" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.83.0")

      assert [%{version: "0.83.0"}, %{version: "0.82.0"}] =
               MediaCentaur.SelfUpdate.upgrade_history()
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/self_update/history_test.exs`
Expected: FAIL — `MediaCentaur.SelfUpdate.upgrade_history/0` is undefined.

- [ ] **Step 3: Implement — alias, boot hook, public function**

In `lib/media_centaur/self_update.ex`, add `History` to the alias list:

```elixir
  alias MediaCentaur.SelfUpdate.{CheckerJob, Health, History, Storage, UpdateChecker, Updater}
```

In `boot!/0`, record the running version right after hydrating the cache. Change:

```elixir
  def boot! do
    :ok = Storage.hydrate_cache()
```

to:

```elixir
  def boot! do
    :ok = Storage.hydrate_cache()
    # Record the version we just booted into, if it changed since last boot.
    # Path-agnostic upgrade capture: keys off the running version, not any one
    # apply path. Prod-gated by the `enabled?/0` guard around boot!/0 in
    # application.ex — dev rebuilds from source and must not pollute the log.
    :ok = History.record_boot_version()
```

Add a public delegating function (place it near `last_check_at/0`, after its `@spec`/`def`):

```elixir
  @doc """
  Returns the upgrade history newest-first — `[%{version, recorded_at}]` — for
  the Status → Updates drill-in. See `MediaCentaur.SelfUpdate.History`.
  """
  @spec upgrade_history() :: [History.entry()]
  def upgrade_history, do: History.list()
```

- [ ] **Step 4: Run tests**

Run: `mix test test/media_centaur/self_update/history_test.exs test/media_centaur/self_update_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/self_update.ex test/media_centaur/self_update/history_test.exs
git commit -m "feat(self-update): capture version history at boot, expose upgrade_history/0"
```

---

## Task 3: Render the History section in the widget + story

**Files:**
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex` (`self_update_widget/1` attrs + template ~line 507-586, add `history_date/1` near the other private defs ~line 588)
- Modify: `storybook/status/self_update_widget.story.exs`

- [ ] **Step 1: Add the `history` attr**

In `lib/media_centaur_web/components/activity_widget_components.ex`, add this attr alongside the other `self_update_widget` attrs (after the `attr :apply_progress` line, before `def self_update_widget`):

```elixir
  attr :history, :list,
    default: [],
    doc: "upgrade history, newest-first: [%{version, recorded_at}] — version + date only"
```

- [ ] **Step 2: Render the History section**

In the `self_update_widget/1` template, insert this block immediately after the "Automatic install" `</div>` (the block ending at the line with `</span>\n        </div>`) and before the `<div :if={apply_active?(@apply_phase)} ...>` apply-progress block:

```heex
        <div :if={@history != []} class="mt-1 border-t border-base-content/10 pt-2" data-component="update-history">
          <p class="text-xs text-base-content/50 mb-1">History</p>
          <ul class="space-y-0.5">
            <li
              :for={entry <- @history}
              id={"update-history-#{entry.version}"}
              class="flex items-center justify-between text-xs"
            >
              <span class="font-mono text-base-content/70">v{entry.version}</span>
              <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
            </li>
          </ul>
        </div>
```

- [ ] **Step 3: Add the `history_date/1` helper**

Add this private function next to the other `self_update_widget` helpers (e.g. just after `defp apply_active?/1`):

```elixir
  # Friendly, non-zero-padded date for the upgrade-history rows, e.g. "Jun 7, 2026".
  defp history_date(%DateTime{} = at),
    do: "#{Calendar.strftime(at, "%b")} #{at.day}, #{at.year}"
```

- [ ] **Step 4: Update the story (MC0009)**

In `storybook/status/self_update_widget.story.exs`, add `history: []` to the `base/0` map (so every existing variation keeps a defined value), then add a new variation to the `variations/0` list:

Change `base/0` to include the key:

```elixir
  defp base do
    %{
      version: "0.80.0",
      status: :up_to_date,
      latest_release: nil,
      last_check_at: @recent,
      now: @now,
      check_enabled?: true,
      interval_minutes: 15,
      auto_install?: true,
      apply_phase: nil,
      apply_progress: nil,
      history: []
    }
  end
```

Add this variation (e.g. after `:up_to_date`):

```elixir
      %Variation{
        id: :with_history,
        description: "On the latest release, with prior upgrades listed",
        attributes:
          variant(
            history: [
              %{version: "0.80.0", recorded_at: ~U[2026-06-07 15:00:00Z]},
              %{version: "0.79.1", recorded_at: ~U[2026-05-28 11:30:00Z]},
              %{version: "0.79.0", recorded_at: ~U[2026-05-21 08:15:00Z]}
            ]
          )
      },
```

- [ ] **Step 5: Run the storybook compile + render tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS (the new variation compiles and renders).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/activity_widget_components.ex storybook/status/self_update_widget.story.exs
git commit -m "feat(status): render upgrade history in the self-update widget"
```

---

## Task 4: Wire `StatusLive` to load and pass history

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex` (`assign_defaults/1` ~line 107-112, `assign_self_update/1` ~line 123-128, `activity_bundle/1` self_update keys ~line 215-226)

- [ ] **Step 1: Write the failing test**

The drill-in is rendered by `StatusLive`; `self_update` is the registered `"Updates"` board subsystem. Append a `describe` to `test/media_centaur_web/live/status_live_test.exs`, mirroring the file's existing pattern (`MediaCentaurWeb.ConnCase`, `import Phoenix.LiveViewTest`, the `live_async!/2` helper, and string path form already used throughout):

```elixir
  describe "Updates drill-in — upgrade history" do
    test "lists recorded versions in the Updates activity widget", %{conn: conn} do
      :ok = MediaCentaur.SelfUpdate.History.record_boot_version("0.81.0")
      :ok = MediaCentaur.SelfUpdate.History.record_boot_version("0.82.0")

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=self_update")

      assert html =~ "update-history"
      assert html =~ "v0.82.0"
      assert html =~ "v0.81.0"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: FAIL on the new test — the history markup (`update-history`, `v0.82.0`) is absent because `StatusLive` doesn't pass `history` yet.

- [ ] **Step 3: Implement the wiring**

In `assign_defaults/1`, add a default (after the `self_update_apply_progress: nil` line):

```elixir
    |> assign(self_update_history: [])
```

In `assign_self_update/1`, load it (add to the `assign(socket, …)` keyword list):

```elixir
    assign(socket,
      self_update_status: status,
      self_update_release: release,
      self_update_last_check_at: SelfUpdate.last_check_at(),
      self_update_history: SelfUpdate.upgrade_history(),
      self_update_apply_phase: if(phase != :idle, do: phase)
    )
```

In `activity_bundle/1`, pass it through (add to the self_update group of keys, e.g. after `last_check_at:`):

```elixir
      history: assigns.self_update_history,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS (all, including the new test).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): load upgrade history into the Updates drill-in"
```

---

## Task 5: Full precommit

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: PASS — compile (zero warnings), format, credo --strict (incl. MC0009 storybook coverage), boundaries, deps.audit, sobelow, full test suite.

- [ ] **Step 2: Fix anything precommit reports**

If credo flags formatting/Quokka, re-run `mix format` and re-stage. If a flaky concurrency failure appears in the full suite (known: SQLite "Database busy" under parallelism), confirm the touched files are clean with `mix test <file> --repeat-until-failure 20` before blaming the change.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "chore: precommit fixups for upgrade history"
```

---

## Done criteria

- `SelfUpdate.upgrade_history/0` returns newest-first `%{version, recorded_at}` entries; boot records on version change only, capped at 50.
- The Status → Updates drill-in shows the History list (version + date, newest-first) when history exists, and omits the section when empty.
- Storybook has a populated `:with_history` variation; `mix precommit` is green.

## Notes / deferred (not in this plan)

- No backfill of versions run before this shipped — history begins at the landing version.
- No build SHA / notes links per entry (version + date only, by decision).
- User-facing surfaces: nothing in the wiki changes shape materially (the history is a passive read-out on an existing operator page); if desired, a one-line mention can be added to the Status/Updates wiki page as a follow-up.
