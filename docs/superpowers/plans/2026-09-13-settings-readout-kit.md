# Settings Readout Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Settings section composes from one kit whose resting state is a readout: an external connection is a row that shows what is configured and how it is doing, its form appears only on Edit, and every other setting saves the moment it changes.

**Architecture:** The shared kit moves from `MediaCentaurWeb.SettingsLive.Components` (no stories) to `MediaCentaurWeb.Components.Settings` under the components tree, with one new component, `connection_row/1`, and one restored, `settings_choice/1`. The Settings shell renders each section's intro; section modules render cards of rows. `SettingsLive` gains one `editing` assign (which connection row's form is open) and per-row events (`edit_connection`, `cancel_edit`, `test_connection`, `remove_client`, `review_detected`, `dismiss_detected`); the existing `save_*` handlers keep their save-then-test contract. Independently of the UI, the automatic quality policy loses its configurable floor and its 4K patience window across `AutoGrabSettings`, `WantSchedule`, `DownloadParams` and the drop planner, with a data migration that deletes the retired rows.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView 1.x, Ecto + SQLite, Phoenix Storybook, ExUnit, Tailwind v4 + daisyUI.

**Spec:** `docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md` (decisions cited as D1…D21). **Record:** UIDR-041. **Campaign:** `campaigns/settings-readout-kit.md`.

---

## Ground rules

- **Never run `mix` directly.** Every command below uses `~/scripts/agents/agent-mix`, which points `MIX_BUILD_ROOT` outside the checkout. A bare `mix` writes `.beam` files under the running dev server and can take it down.
- Tests before implementation. No network in tests: integrations go through their `Req.Test` stubs (`:prowlarr`, `:qbittorrent`, `:sabnzbd`, `:tmdb`).
- Storybook-first for components that already have a story; new components get their story in the same task (MC0009 fails precommit otherwise). Stories live under `storybook/settings/`, module namespace `MediaCentaurWeb.Storybook.Settings.*`.
- User-facing words are the spec's. Any new sentence goes through the two writing-copy gates (does it carry information the reader lacks; does it rest only on terms already given).
- `~/scripts/agents/agent-mix precommit` before the last commit of every phase; zero warnings.
- Commit after each task. Work on `main`; do not push until told.
- Each phase ships on its own. Do not start Phase C on a checkout where Phase B's precommit has not passed.

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `lib/media_centaur_web/components/settings.ex` | `MediaCentaurWeb.Components.Settings`: `settings_card/1`, `settings_row/1`, `settings_stepper/1`, `settings_choice/1`, `settings_text_row/1`, `settings_select_row/1`, `settings_field/1`, `settings_disclosure/1`, `path_status/1` |
| `lib/media_centaur_web/components/settings/connection_row.ex` | `MediaCentaurWeb.Components.Settings.ConnectionRow`: `connection_row/1`, the readout for one external endpoint with its edit slot |
| `lib/media_centaur_web/live/settings_live/connection_state.ex` | `MediaCentaurWeb.SettingsLive.ConnectionState`: pure — an integration's row state, state word and credential summary from config + persisted test |
| `lib/media_centaur_web/live/settings_live/ladder.ex` | `MediaCentaurWeb.SettingsLive.Ladder`: pure — neighbours on a fixed list of stepper values |
| `storybook/settings/_settings.index.exs` and one `storybook/settings/<function>.story.exs` per kit function | The kit's contracts |
| `priv/repo/data_migrations/20260913120000_quality_policy_loses_floor_and_patience.exs` | Deletes the retired settings rows; strips the retired per-title keys |
| `test/media_centaur_web/live/settings_live/connection_state_test.exs`, `.../ladder_test.exs` | Pure tests |

**Modified**

| Path | Change |
|---|---|
| `lib/media_centaur/acquisition/auto_grab_settings.ex` | Drop `default_min_quality`, `patience_hours`; add `floor/0`; `effective_min_quality/1`; drop `effective_max_quality/2`, `effective_patience_hours/2` |
| `lib/media_centaur/acquisition/want_schedule.ex` | `due?/2`; drop `floor_elevated?/3` and patience-expiry |
| `lib/media_centaur/acquisition/download_params.ex` | Only `min_quality` remains |
| `lib/media_centaur/acquisition/drop_planner.ex` | No patience; per-unit floor override goes |
| `lib/media_centaur/acquisition/jobs/pursue_target.ex:193`, `.../run_plan.ex:624` | `AutoGrabSettings.floor()` |
| `lib/media_centaur_web/live/settings_live.ex` | `@sections` descriptions; intro render; `editing`; new events; auto-grab per-row persistence; remove `persist_auto_grab_defaults/1` |
| `lib/media_centaur_web/live/settings_live/acquisition_section.ex`, `tmdb.ex`, `social_section.ex`, and every other section module | On the kit |
| `lib/media_centaur/capabilities.ex` | `clear_integration/1` |
| `test/media_centaur_web/live/settings_live_acquisition_test.exs`, `settings_live_social_test.exs`, `settings_live_test.exs` | Rewritten around rows |
| `test/e2e/screenshot.tour.js:175-200` | Locators |
| Wiki: `Settings-Reference.md`, `Release-Tracking.md` | Rows as shipped |

**Deleted**

| Path | Why |
|---|---|
| `lib/media_centaur_web/live/settings_live/components.ex` | Moved to the components tree |

---

## Phase A — the quality policy loses its floor and its patience window (D20)

Backend only; ships on its own. After this phase the Settings form still shows the two retired controls until Phase C removes them, and saving them writes rows nothing reads. That is acceptable for the hours between phases, not for a release: Phase A and Phase C ship in the same release, or Phase A's last task also deletes the two fields from `acquisition_section.ex` and `persist_auto_grab_defaults/1` (Task A7 does exactly that).

### Task A1: `AutoGrabSettings` — constant floor, no patience

**Files:**
- Modify: `lib/media_centaur/acquisition/auto_grab_settings.ex`
- Test: `test/media_centaur/acquisition/auto_grab_settings_test.exs`

- [ ] **Step 1: Rewrite the test file's affected describes**

Replace the `load/0 — defaults` assertions on `default_min_quality` / `patience_hours`, delete the `respects integer overrides` case for `auto_grab.4k_patience_hours` (keep the `max_attempts` half), and replace the last two describes with:

```elixir
  describe "floor/0 and effective_min_quality/1" do
    test "the automatic floor is 1080p" do
      assert AutoGrabSettings.floor() == "hd_1080p"
    end

    test "a title with no acceptance uses the floor" do
      assert AutoGrabSettings.effective_min_quality(nil) == "hd_1080p"
    end

    test "a title's lower-quality acceptance overrides the floor" do
      assert AutoGrabSettings.effective_min_quality("any") == "any"
    end
  end

  test "the struct carries no floor or patience field" do
    refute Map.has_key?(%AutoGrabSettings{}, :default_min_quality)
    refute Map.has_key?(%AutoGrabSettings{}, :patience_hours)
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: FAIL — `AutoGrabSettings.floor/0 is undefined`, `effective_min_quality/1 is undefined`.

- [ ] **Step 3: Implement**

In `auto_grab_settings.ex`: remove `"auto_grab.default_min_quality"` and `"auto_grab.4k_patience_hours"` from `@keys`; remove `default_min_quality` and `patience_hours` from `@builtin_defaults`, the `@type t`, and `load/0`; replace the three `effective_*` functions with:

```elixir
  @floor "hd_1080p"

  @doc """
  The automatic floor. Below it a release is taken only under a title's
  own lower-quality acceptance (ADR-063 §2). Fixed, not a setting: the
  owner's policy is "the best available now, then down the ladder", and
  a configurable floor only ever expressed "never 1080p", which nobody
  wanted once the patience window went (UIDR-041 §6).
  """
  @spec floor() :: quality()
  def floor, do: @floor

  @doc "A title's effective floor: its lower-quality acceptance when it has one, else `floor/0`."
  @spec effective_min_quality(String.t() | nil) :: quality()
  def effective_min_quality(nil), do: @floor
  def effective_min_quality(value) when is_binary(value), do: value
```

Rewrite the moduledoc's defaults list to: mode `"all_releases"`, max quality `"uhd_4k"`, max attempts 12, pack fit 75, size preference `"fidelity"`, and add one sentence: "The floor is fixed at 1080p (`floor/0`); there is no patience window."

- [ ] **Step 4: Run to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: PASS. Compilation of the rest of `lib/` will warn about callers; the next tasks fix them.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/auto_grab_settings.ex test/media_centaur/acquisition/auto_grab_settings_test.exs
git commit -m "refactor(acquisition): the automatic quality floor is a constant, patience is gone from settings"
```

### Task A2: `WantSchedule.due?/2`

**Files:**
- Modify: `lib/media_centaur/acquisition/want_schedule.ex`
- Test: `test/media_centaur/acquisition/want_schedule_test.exs`

- [ ] **Step 1: Rewrite the tests**

Delete the `floor_elevated?/3` describe and the last two `due?/3` cases (patience expiry). Change every remaining `WantSchedule.due?(want, _hours, now)` call to `WantSchedule.due?(want, now)`. The describe reads `describe "due?/2"`.

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/want_schedule_test.exs`
Expected: FAIL — `due?/2 is undefined`.

- [ ] **Step 3: Implement**

```elixir
  @doc """
  Whether the want should be searched at `now`. Never-searched wants
  are due immediately; otherwise the age-band interval applies.
  """
  @spec due?(struct(), DateTime.t()) :: boolean()
  def due?(%{last_searched_at: nil}, _now), do: true
  def due?(want, %DateTime{} = now), do: interval_elapsed?(want, now)
```

Delete `floor_elevated?/3`, `patience_expired_since_last_search?/3`, and the moduledoc's "Patience expiry forces due" paragraph and Q4 sentence.

- [ ] **Step 4: Run to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/want_schedule_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/want_schedule.ex test/media_centaur/acquisition/want_schedule_test.exs
git commit -m "refactor(acquisition): the want schedule is age bands only"
```

### Task A3: `DownloadParams` keeps only the lower-quality acceptance

**Files:**
- Modify: `lib/media_centaur/acquisition/download_params.ex`
- Test: `test/media_centaur/acquisition/title_download_params_test.exs`

- [ ] **Step 1: Rewrite the tests**

Every case that sets or asserts `quality_4k_patience_hours` or `max_quality` becomes the same case on `min_quality: "any"`. The defaults assertion becomes `assert TitleDownloadParams.get(1234, :tv_series) == %DownloadParams{min_quality: nil}`. The validation case becomes `min_quality: "sd"` refused with `%{min_quality: [_ | _]} = errors_on(changeset)`. Add:

```elixir
    test "the embedded params carry only the acceptance" do
      assert DownloadParams.__schema__(:fields) == [:min_quality]
    end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/title_download_params_test.exs`
Expected: FAIL on the fields assertion.

- [ ] **Step 3: Implement**

In `download_params.ex`: `embedded_schema` has one field, `field :min_quality, :string`; `@fields [:min_quality]`; delete `@max_patience_hours`, the `max_quality` and `quality_4k_patience_hours` type entries and validations; the moduledoc's ceiling sentence goes and the first paragraph reads "One title's lower-quality acceptance ([ADR-063] §2): `min_quality` is `"any"` when the title takes the best release that exists, `nil` when it holds to the automatic floor."

- [ ] **Step 4: Run to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/title_download_params_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/download_params.ex test/media_centaur/acquisition/title_download_params_test.exs
git commit -m "refactor(acquisition): a title's download params are its lower-quality acceptance only"
```

### Task A4: the drop planner plans at the floor immediately

**Files:**
- Modify: `lib/media_centaur/acquisition/drop_planner.ex:170-200, 226, 271, 340-365`
- Test: `test/media_centaur/acquisition/drop_planner_test.exs:240-270`

- [ ] **Step 1: Rewrite the patience test**

The case at line ~250 that puts `%{quality_4k_patience_hours: 24}` on a title and expects an elevated floor becomes:

```elixir
    test "a fresh want is planned at the floor right away; nothing elevates it" do
      # Same fixture as the neighbouring cases; no per-title params at all.
      assert {:ok, :planned} = DropPlanner.plan_due(now)
      [unit] = plan_units_for(item)
      assert unit.min_quality == nil
    end
```

(Use the file's own helpers for `now`, `item` and reading the plan's units; the assertion is that no unit carries a `min_quality` override.)

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs`
Expected: FAIL — `effective_patience_hours/2 is undefined` (compile error in `drop_planner.ex`).

- [ ] **Step 3: Implement**

In `plan_item/4`: delete the `patience =` binding; `due = Enum.filter(wants, &WantSchedule.due?(&1, now))`; call `plan_tv_drop(item, due, settings, now)` and `plan_movie_drop(item, &1, settings, now)`. Drop the `patience` parameter from both function heads and both clauses. At lines 226 and 271 the unit attr becomes `min_quality: nil`. Delete `floor_for/5` and its comment. At lines 342–343:

```elixir
      AutoGrabSettings.effective_min_quality(params.min_quality),
      settings.default_max_quality
```

Update the moduledoc lines 17 and 61 (they describe the patience floor stamp) to: "Every unit is planned at the automatic floor; a title's lower-quality acceptance lowers it."

- [ ] **Step 4: Run the acquisition suite**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition`
Expected: PASS except `pursue_target` / `run_plan` compile errors, fixed in A5.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/drop_planner.ex test/media_centaur/acquisition/drop_planner_test.exs
git commit -m "refactor(acquisition): the drop planner has no patience window"
```

### Task A5: the two remaining readers of the retired floor

**Files:**
- Modify: `lib/media_centaur/acquisition/jobs/pursue_target.ex:193`, `lib/media_centaur/acquisition/jobs/run_plan.ex:624`, comments at `plans.ex:248`, `plans/plan_unit.ex:70`, `run_plan.ex:161,438`, `pursue_target.ex:184`

- [ ] **Step 1: Replace the reads**

Both lines become `min_quality: Map.get(criteria, "min_quality") || AutoGrabSettings.floor(),`. Each comment that names "the patience elevation" or "Q4" now reads "a per-unit `min_quality` is the title's lower-quality acceptance (ADR-063 §2); nothing else sets one".

- [ ] **Step 2: Run the full suite**

Run: `~/scripts/agents/agent-mix test`
Expected: PASS. If `test/media_centaur/acquisition/planner_test.exs` or `run_plan_test.exs` build prefs with `min_quality:` from a settings struct, change those fixtures to `AutoGrabSettings.floor()`.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur/acquisition test/media_centaur/acquisition
git commit -m "refactor(acquisition): every automatic path reads the constant floor"
```

### Task A6: data migration for the retired rows and keys

**Files:**
- Create: `priv/repo/data_migrations/20260913120000_quality_policy_loses_floor_and_patience.exs`
- Test: `test/media_centaur/data_migrations_test.exs` (append a describe)

- [ ] **Step 1: Write the test**

```elixir
  describe "QualityPolicyLosesFloorAndPatience" do
    alias MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatience

    test "deletes the two retired settings rows and strips the retired per-title keys" do
      Repo.query!("INSERT INTO settings (id, key, value, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [Ecto.UUID.bingenerate(), "auto_grab.default_min_quality", ~s({"value":"hd_1080p"}), now(), now()])
      Repo.query!("INSERT INTO settings (id, key, value, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [Ecto.UUID.bingenerate(), "auto_grab.4k_patience_hours", ~s({"value":48}), now(), now()])
      Repo.query!("INSERT INTO settings (id, key, value, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [Ecto.UUID.bingenerate(), "auto_grab.max_attempts", ~s({"value":12}), now(), now()])

      Repo.query!(
        "INSERT INTO title_download_params (id, tmdb_id, media_type, params, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        [Ecto.UUID.bingenerate(), 1, "movie", ~s({"min_quality":"any","max_quality":"uhd_4k","quality_4k_patience_hours":24}), now(), now()]
      )
      Repo.query!(
        "INSERT INTO title_download_params (id, tmdb_id, media_type, params, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        [Ecto.UUID.bingenerate(), 2, "movie", ~s({"max_quality":"hd_1080p"}), now(), now()]
      )

      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)
      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)

      keys = Repo.query!("SELECT key FROM settings WHERE key LIKE 'auto_grab.%' ORDER BY key").rows
      assert keys == [["auto_grab.max_attempts"]]

      rows = Repo.query!("SELECT tmdb_id, params FROM title_download_params ORDER BY tmdb_id").rows
      assert rows == [[1, ~s({"min_quality":"any"})]]
    end
  end
```

(`now/0` and the `Repo` alias follow the file's existing helpers; check the `settings` and `title_download_params` column lists against `priv/repo/migrations` before writing the INSERTs — the id column types are what the schema migrations created.)

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/data_migrations_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Write the migration**

```elixir
defmodule MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatience do
  @moduledoc """
  UIDR-041 §6: the automatic quality policy keeps a highest resolution and
  a within-resolution preference and nothing else. The configurable floor
  (`auto_grab.default_min_quality`) and the 4K patience window
  (`auto_grab.4k_patience_hours`) are retired, and a title's download
  params keep only the lower-quality acceptance (`min_quality`).

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style. Idempotent — a second run finds nothing.
  """
  use Ecto.Migration

  @drop_settings "DELETE FROM settings WHERE key IN ('auto_grab.default_min_quality', 'auto_grab.4k_patience_hours')"
  @strip_keys "UPDATE title_download_params SET params = json_remove(params, '$.max_quality', '$.quality_4k_patience_hours')"
  @drop_empty "DELETE FROM title_download_params WHERE json_extract(params, '$.min_quality') IS NULL"

  def up, do: sweep(repo())

  def down, do: :ok

  @doc "Deletes the retired settings rows, strips the retired per-title keys, drops emptied rows. Returns `:ok`."
  def sweep(repo) do
    repo.query!(@drop_settings, [])
    repo.query!(@strip_keys, [])
    repo.query!(@drop_empty, [])
    :ok
  end
end
```

- [ ] **Step 4: Run to verify it passes, then run the real migration**

Run: `~/scripts/agents/agent-mix test test/media_centaur/data_migrations_test.exs`
Expected: PASS.

The dev server applies data migrations at boot; the owner's checkout runs it on the next restart. Do not run it by hand against the real DB.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/data_migrations/20260913120000_quality_policy_loses_floor_and_patience.exs test/media_centaur/data_migrations_test.exs
git commit -m "chore(acquisition): data migration retires the quality floor and patience rows"
```

### Task A7: the Settings form stops writing the retired keys

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/acquisition_section.ex:570-610` (delete the "4K patience (hours)" and "Minimum quality (final fallback)" fields), `lib/media_centaur_web/live/settings_live.ex:2832-2849` (delete the two tuples)
- Modify: `test/media_centaur_web/live/settings_live_acquisition_test.exs` if any case submits those fields

- [ ] **Step 1: Delete the two fields and the two persistence tuples; run precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS, zero warnings.

- [ ] **Step 2: Wiki**

In `~/src/media-centaur/media-centaur.wiki/Settings-Reference.md` delete the "4K patience (hours)" and "Minimum quality (final fallback)" bullets (lines ~136–137) and in `Release-Tracking.md` line ~65 replace the minimum/maximum sentence with: "Quality is governed by the Auto-acquisition settings: the highest resolution and the within-resolution preference. Below 1080p a release is taken only when the title's own lower-quality acceptance is on."

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: quality policy loses the floor and the patience window" && cd -
```

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/live/settings_live/acquisition_section.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur_web/live/settings_live_acquisition_test.exs
git commit -m "feat(settings): auto-acquisition no longer offers a floor or a patience window"
```

---

## Phase B — the kit moves to the components tree, with stories (D5, D1, D2)

After this phase every section renders as before through the new module; the shell renders section intros; the old kit module is gone.

### Task B1: `MediaCentaurWeb.Components.Settings` with the moved components and their stories

**Files:**
- Create: `lib/media_centaur_web/components/settings.ex`
- Create: `storybook/settings/_settings.index.exs`, `storybook/settings/settings_row.story.exs`, `storybook/settings/settings_stepper.story.exs`, `storybook/settings/settings_field.story.exs`, `storybook/settings/path_status.story.exs`
- Modify: every `import MediaCentaurWeb.SettingsLive.Components` (files: `system_settings.ex`, `tmdb.ex`, `library.ex`, `acquisition_section.ex`, `social_section.ex`, `services.ex`, `preferences.ex`, `playback.ex`) → `import MediaCentaurWeb.Components.Settings`
- Delete: `lib/media_centaur_web/live/settings_live/components.ex`

- [ ] **Step 1: Create the module by moving the code**

`git mv lib/media_centaur_web/live/settings_live/components.ex lib/media_centaur_web/components/settings.ex`, rename the module to `MediaCentaurWeb.Components.Settings`, keep `use MediaCentaurWeb, :html` and the `ConnectionTest` / `PathCheck` aliases. Moduledoc:

```elixir
  @moduledoc """
  The Settings kit (UIDR-041): the components every Settings section
  composes from. A section is cards of rows. `settings_card/1` is the
  card; `settings_row/1` (toggle), `settings_stepper/1`,
  `settings_choice/1`, `settings_text_row/1` and `settings_select_row/1`
  are the rows, each saving on the act; `settings_field/1` is the
  label/control/help unit inside a connection row's edit form;
  `settings_disclosure/1` hides rare content; `path_status/1` is the glyph
  beside a path label. The connection row lives in
  `MediaCentaurWeb.Components.Settings.ConnectionRow`.
  """
```

Delete `settings_card_header/1`, `status_dot/1` and `connection_status/1` only after Tasks B2 and C-phase callers move off them; in this task keep them (they are still called).

- [ ] **Step 2: Update the eight imports; compile**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 3: The storybook index and four stories**

`storybook/settings/_settings.index.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Settings do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "sliders", :thin, "psb:mr-1"}

  def entry("settings_card"), do: [icon: {:fa, "square", :thin}, name: "Card"]
  def entry("settings_row"), do: [icon: {:fa, "toggle-on", :thin}, name: "Toggle row"]
  def entry("settings_stepper"), do: [icon: {:fa, "plus-minus", :thin}, name: "Stepper row"]
  def entry("settings_choice"), do: [icon: {:fa, "grip-lines", :thin}, name: "Choice row"]
  def entry("settings_text_row"), do: [icon: {:fa, "input-text", :thin}, name: "Text row"]
  def entry("settings_select_row"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Select row"]
  def entry("settings_field"), do: [icon: {:fa, "rectangle-list", :thin}, name: "Field"]
  def entry("settings_disclosure"), do: [icon: {:fa, "chevron-right", :thin}, name: "Disclosure"]
  def entry("path_status"), do: [icon: {:fa, "circle-check", :thin}, name: "Path status"]
  def entry("connection_row"), do: [icon: {:fa, "plug", :thin}, name: "Connection row"]
end
```

`storybook/settings/settings_row.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Settings.SettingsRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_row/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :on,
        attributes: %{
          label: "Share what you watch",
          description: "Friends see a movie or an episode when you finish it.",
          checked: true,
          event: "toggle_share_watched"
        }
      },
      %Variation{
        id: :off,
        attributes: %{
          label: "Share your watchlist",
          description: "A title you list is shared with your friends; one you drop is withdrawn.",
          checked: false,
          event: "toggle_share_watchlist"
        }
      }
    ]
  end
end
```

`storybook/settings/settings_stepper.story.exs` — variations `:mid` (value_label "75%", down 70, up 80, reset 75, all flags false except `at_default: true`), `:at_min` (`at_min: true`), `:at_max` (`at_max: true`), each with `label: "Season packs"`, `description: "Take a pack only when you want at least this share of its episodes."`, `event: "set_auto_grab"`.

`storybook/settings/settings_field.story.exs` — `:inline` (label "Address", description "Must be reachable from this machine.", slot `<input class="input input-bordered font-mono text-sm" value="http://localhost:9696" />`) and `:stacked` (`layout: :stacked`, same slot with `w-full`).

`storybook/settings/path_status.story.exs` — `:found` (`path: "/usr/bin/env", kind: :executable`) and `:missing` (`path: "/nonexistent/mpv", kind: :executable`).

- [ ] **Step 4: Render the stories**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/storybook_compile_test.exs`
Expected: PASS. Open `http://localhost:2160/storybook/settings/settings_row` and confirm the toggle renders dark.

- [ ] **Step 5: Commit**

```bash
git add -A lib/media_centaur_web/components/settings.ex lib/media_centaur_web/live/settings_live storybook/settings
git commit -m "refactor(settings): the settings kit moves to the components tree with stories"
```

### Task B2: `settings_card/1`, `settings_choice/1`, `settings_text_row/1`, `settings_select_row/1`, `settings_disclosure/1`

**Files:**
- Modify: `lib/media_centaur_web/components/settings.ex`
- Create: `storybook/settings/settings_card.story.exs`, `settings_choice.story.exs`, `settings_text_row.story.exs`, `settings_select_row.story.exs`, `settings_disclosure.story.exs`

- [ ] **Step 1: Write the five stories first** (each `use PhoenixStorybook.Story, :component`, `render_source :function`):

- `settings_card`: `:plain` (`title: "Search"`, slot `<p class="text-sm">body</p>`), `:with_description_and_action` (`title: "Download clients"`, `description: "One client per protocol. Prowlarr sends each grab to the client that matches the indexer."`, slots `["<:action><button class=\"btn btn-ghost btn-xs\">Detect from Prowlarr</button></:action>", "<p class=\"text-sm\">rows</p>"]`).
- `settings_choice`: `:two` (`label: "Highest resolution"`, `description: "The best available is taken right away."`, `options: [{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}]`, `selected: "uhd_4k"`, `event: "set_auto_grab"`, `event_value: %{"key" => "default_max_quality"}`), `:three` (When a release appears; `[{"all_releases", "Grab it"}, {"ask", "Ask first"}, {"off", "Notify only"}]`, selected `"ask"`).
- `settings_text_row`: `:path` (`label: "Data directory"`, `description: "Where cached posters and backdrops are stored."`, `name: "data_dir"`, `value: "/home/sample/.local/share/media-centaur"`, `placeholder: "/path"`, `event: "save_data_dir"`, `mono: true`).
- `settings_select_row`: `:languages` (`label: "Preferred audio"`, `description: "Which audio track plays first."`, `name: "audio"`, `options: [{"original", "Original language"}, {"understood", "A language you understand"}, {"any", "Any"}]`, `selected: "original"`, `event: "set_language_policy"`).
- `settings_disclosure`: `:closed` (`label: "Secret key"`, slot `<p class="text-xs">hidden until opened</p>`), `:open` (`open: true`).

- [ ] **Step 2: Run the render test to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement the five components**

```elixir
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global
  slot :action
  slot :inner_block, required: true

  @doc "One card in a settings section (UIDR-041 §3): uppercase title, optional description and action, a body of rows."
  def settings_card(assigns) do
    ~H"""
    <div class={["glass-surface rounded-xl p-5 space-y-3", @class]} {@rest}>
      <div class="flex items-baseline justify-between gap-4">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">{@title}</h3>
        <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
      </div>
      <p :if={@description} class="text-xs text-base-content/55 max-w-[60ch]">{@description}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :any, required: true
  attr :description, :string, default: nil
  attr :options, :list, required: true, doc: "`[{value, label}]`, at most four."
  attr :selected, :any, required: true
  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "extra `phx-value-*` params (string keys)."
  attr :id, :string, default: nil

  @doc """
  A pick-one-of-N row on the house segmented pill (UIDR-041 §2). Each
  option is a nav item; the chosen one carries `aria-pressed`. Clicking
  pushes `@event` with `choice` set to the option value (never `value`:
  a button's native `value` property would clobber it, MC0021).
  """
  def settings_choice(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg">
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p :if={@description} class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <div id={@id} class="tabs tabs-boxed segmented-control w-fit shrink-0" role="group" aria-label={@label}>
        <button
          :for={{value, label} <- @options}
          type="button"
          class="tab text-sm"
          phx-click={@event}
          phx-value-choice={value}
          {phx_values(@event_value)}
          aria-pressed={to_string(value == @selected)}
          data-nav-item
          tabindex="0"
        >
          {label}
        </button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :event, :string, required: true, doc: "pushed with `%{name => value}` on Enter and on blur."
  attr :mono, :boolean, default: false
  attr :id, :string, default: nil
  slot :label_suffix, doc: "a glyph beside the label, e.g. `path_status`."

  @doc "A free-text setting that commits on Enter or blur (UIDR-041 §2). Wide control below the label."
  def settings_text_row(assigns) do
    ~H"""
    <form id={@id} phx-submit={@event} phx-change="noop" class="py-2.5 px-3.5 space-y-1.5">
      <div class="flex items-center gap-1.5">
        <span class="font-medium">{@label}</span>
        {render_slot(@label_suffix)}
      </div>
      <p :if={@description} class="text-xs text-base-content/55">{@description}</p>
      <input
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        phx-blur={@event}
        phx-value-name={@name}
        class={["input input-bordered w-full text-sm", @mono && "font-mono"]}
        data-nav-item
        tabindex="0"
      />
    </form>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :name, :string, required: true
  attr :options, :list, required: true, doc: "`[{value, label}]`, more than four."
  attr :selected, :any, required: true
  attr :event, :string, required: true, doc: "pushed on change with `%{name => value}`."
  attr :id, :string, default: nil

  @doc "An enum too wide for the pill: a native select on the right, saving on change (UIDR-041 §2)."
  def settings_select_row(assigns) do
    ~H"""
    <form id={@id} phx-change={@event} class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg">
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p :if={@description} class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <select name={@name} class="select select-bordered select-sm shrink-0 text-sm" data-nav-item tabindex="0">
        <option :for={{value, label} <- @options} value={value} selected={value == @selected}>{label}</option>
      </select>
    </form>
    """
  end

  attr :label, :string, required: true
  attr :open, :boolean, default: false
  attr :id, :string, default: nil
  slot :inner_block, required: true

  @doc "Rare content behind a caret and a label (UIDR-041): the secret key, service details."
  def settings_disclosure(assigns) do
    ~H"""
    <details id={@id} class="settings-disclosure" open={@open}>
      <summary class="cursor-pointer select-none text-xs text-base-content/55 inline-flex items-center gap-1.5" data-nav-item tabindex="0">
        <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
        <span>{@label}</span>
      </summary>
      <div class="mt-3 ml-5 space-y-4 border-l border-base-content/10 pl-4 text-sm">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end
```

The `phx-blur` on the text row sends `%{"value" => typed, "name" => name}`; the `phx-submit` sends `%{name => typed}`. The handler accepts both shapes (see Task E2). `phx-change="noop"` needs `handle_event("noop", _, socket)` returning `{:noreply, socket}` in `SettingsLive`, so typing does not raise; add it in this task.

In `assets/css/app.css` rename `.release-notes-disclosure` to `.settings-disclosure` (four rules at ~2907) and update `release_notes.ex` and `system_settings.ex` to the new class; Social moves off it in Phase D. Run `~/scripts/agents/agent-mix assets.build` (the dev asset watchers are off).

- [ ] **Step 4: Render**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/storybook_compile_test.exs`
Expected: PASS. Check `/storybook/settings/settings_choice` shows the lifted active segment.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/settings.ex storybook/settings assets/css/app.css lib/media_centaur_web/live/settings_live lib/media_centaur_web/live/settings_live.ex
git commit -m "feat(settings): card, choice, text, select and disclosure join the kit"
```

### Task B3: the shell renders the section intro (D1)

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex:65-88` (`@sections`), `:1790-1810` (nav loop unchanged), the content column at `:1812`
- Modify: every section module that renders its own `h2` (`preferences.ex`, `services.ex`, `import_section.ex`, `playback.ex`, `language.ex:30,113`, `maintenance_section.ex:38`, `danger.ex:19`, `controls.ex:30`, `tmdb.ex:23`, `social_section.ex:43`, `acquisition_section.ex:55,140,288,414,468,527`) — in this task only delete the section-level `h2` where the card has exactly one and the intro replaces it (`preferences`, `services`, `import_section`, `playback`, `maintenance_section`, `danger`, `controls`); Acquisition, TMDB, Social, Language keep theirs until their own tasks.
- Test: `test/media_centaur_web/live/settings_live_test.exs`

- [ ] **Step 1: Test**

```elixir
  describe "section intro" do
    test "every section shows its title and description from the shell", %{conn: conn} do
      for %{id: id, label: label, description: description} <- MediaCentaurWeb.SettingsLive.sections() do
        {:ok, _view, html} = live_async!(conn, ~p"/settings?section=#{id}")
        assert html =~ ~s(<h2 class="text-lg font-semibold">#{Plug.HTML.html_escape(label)}</h2>)
        assert html =~ Plug.HTML.html_escape(description)
      end
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs --only describe:"section intro"`
Expected: FAIL — `sections/0` undefined.

- [ ] **Step 3: Implement**

Add a `description` to each `@sections` entry:

| id | description |
|---|---|
| system | This install: version, updates, the service, and a health check. |
| services | Background work that runs while the app is up. |
| preferences | How the app looks and behaves for you. |
| controls | Keyboard and gamepad bindings. |
| library | Where your media lives and how long absent files are kept. |
| tmdb | The Movie Database: metadata and artwork for everything in the library. |
| social | Your identity, the relays your activity travels over, and what you share. Friends are managed on the Discovery page. |
| acquisition | Where releases are searched for and downloaded, and what happens when a tracked title's release appears. |
| import | How new files are classified and matched on their way into the library. |
| playback | The mpv player this app drives. |
| language | The languages you understand, and which audio and subtitle tracks play first. |
| maintenance | Repairs you can run on the library. Nothing here deletes your files. |
| danger | Actions that cannot be undone. |

Add `def sections, do: @sections` (public, `@doc false`). In `render/1`, above `<.section_content …>`:

```heex
<div class="min-w-0 mb-1">
  <h2 class="text-lg font-semibold">{section_meta(@active_section).label}</h2>
  <p class="text-sm text-base-content/55 mt-0.5">{section_meta(@active_section).description}</p>
</div>
```

with `defp section_meta(id), do: Enum.find(@sections, &(&1.id == id))`, and wrap the intro plus content in `space-y-4`. Delete the seven section-level `h2` blocks named above (keep each card's body); the Danger card keeps its glyph beside its first action row instead of beside a title.

- [ ] **Step 4: Run the settings suite**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/page_smoke_test.exs`
Expected: PASS. Then `~/scripts/agents/agent-mix precommit` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live test/media_centaur_web/live/settings_live_test.exs
git commit -m "feat(settings): the shell renders every section's intro"
```

---

## Phase C — Acquisition and TMDB on connection rows (D6–D14, D16–D19, D21)

### Task C1: `ConnectionState` (pure)

**Files:**
- Create: `lib/media_centaur_web/live/settings_live/connection_state.ex`
- Test: `test/media_centaur_web/live/settings_live/connection_state_test.exs`

- [ ] **Step 1: Test**

```elixir
defmodule MediaCentaurWeb.SettingsLive.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.SettingsLive.ConnectionState

  @tested ~U[2026-09-13 10:00:00Z]

  test "not configured when the integration lacks its settings" do
    assert ConnectionState.state(false, nil) == :not_configured
  end

  test "configured but never tested" do
    assert ConnectionState.state(true, nil) == :not_tested
  end

  test "ok and error follow the persisted test" do
    assert ConnectionState.state(true, %{status: :ok, tested_at: @tested}) == :ok
    assert ConnectionState.state(true, %{status: :error, tested_at: @tested}) == :error
  end

  test "state words per integration" do
    assert ConnectionState.label(:prowlarr, :ok) == "Connected"
    assert ConnectionState.label(:prowlarr, :error) == "Unreachable"
    assert ConnectionState.label(:download_client, :error) == "Unreachable or auth failed"
    assert ConnectionState.label(:usenet_download_client, :error) == "Unreachable or bad API key"
    assert ConnectionState.label(:tmdb, :not_tested) == "Not tested"
    assert ConnectionState.label(:tmdb, :not_configured) == "Not configured"
  end

  test "credential summary names what is stored, never the value" do
    assert ConnectionState.credential_summary(:tmdb, %{tmdb_api_key_configured?: true}) == "API key set"
    assert ConnectionState.credential_summary(:prowlarr, %{prowlarr_api_key_configured?: false}) == nil

    assert ConnectionState.credential_summary(:download_client, %{
             download_client_username: "admin",
             download_client_password_configured?: true
           }) == "admin · password set"

    assert ConnectionState.credential_summary(:download_client, %{
             download_client_username: nil,
             download_client_password_configured?: true
           }) == "password set"

    assert ConnectionState.credential_summary(:usenet_download_client, %{
             usenet_download_client_api_key_configured?: true
           }) == "API key set"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live/connection_state_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaurWeb.SettingsLive.ConnectionState do
  @moduledoc """
  Pure view helpers for a connection row (UIDR-041 §1): the row's state
  from "is it configured" plus the persisted connection test, the state
  word each integration uses, and the credential summary the detail line
  shows. Nothing here reads Settings; `SettingsLive` passes the config map
  and `Capabilities.load_test_result/1`.
  """

  @type state :: :not_configured | :not_tested | :ok | :error
  @type subject :: :tmdb | :prowlarr | :download_client | :usenet_download_client

  @spec state(boolean(), map() | nil) :: state()
  def state(false, _test), do: :not_configured
  def state(true, nil), do: :not_tested
  def state(true, %{status: :ok}), do: :ok
  def state(true, %{status: :error}), do: :error

  @spec label(subject(), state()) :: String.t()
  def label(_subject, :not_configured), do: "Not configured"
  def label(_subject, :not_tested), do: "Not tested"
  def label(_subject, :ok), do: "Connected"
  def label(:download_client, :error), do: "Unreachable or auth failed"
  def label(:usenet_download_client, :error), do: "Unreachable or bad API key"
  def label(_subject, :error), do: "Unreachable"

  @spec credential_summary(subject(), map()) :: String.t() | nil
  def credential_summary(:tmdb, config), do: if(config[:tmdb_api_key_configured?], do: "API key set")
  def credential_summary(:prowlarr, config), do: if(config[:prowlarr_api_key_configured?], do: "API key set")

  def credential_summary(:usenet_download_client, config),
    do: if(config[:usenet_download_client_api_key_configured?], do: "API key set")

  def credential_summary(:download_client, config) do
    [
      present(config[:download_client_username]),
      if(config[:download_client_password_configured?], do: "password set")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp present(""), do: nil
  defp present(value), do: value
end
```

- [ ] **Step 4: Run to verify it passes; commit**

```bash
git add lib/media_centaur_web/live/settings_live/connection_state.ex test/media_centaur_web/live/settings_live/connection_state_test.exs
git commit -m "feat(settings): connection state, word and credential summary as pure helpers"
```

### Task C2: `connection_row/1` with its story

**Files:**
- Create: `lib/media_centaur_web/components/settings/connection_row.ex`
- Create: `storybook/settings/connection_row.story.exs`

- [ ] **Step 1: Story first** — variations, each with `id: "connection-<variation>"`:

| id | attributes |
|---|---|
| `:connected` | `name: "Prowlarr"`, `state: :ok`, `state_label: "Connected"`, `tested_at: ~U[2026-05-18 09:00:00Z]`, `address: "http://localhost:9696"`, `detail: "API key set"`, actions slot with a Test and an Edit button |
| `:connected_client` | `name: "qBittorrent"`, `kind: "torrent"`, `state: :ok`, `state_label: "Connected"`, `tested_at`, `address: "http://localhost:8080"`, `detail: "admin · password set"`, same actions |
| `:unreachable` | `name: "SABnzbd"`, `kind: "usenet"`, `state: :error`, `state_label: "Unreachable or bad API key"`, `tested_at`, `address`, `detail: "API key set"` |
| `:not_tested` | `state: :not_tested`, `state_label: "Not tested"`, no `tested_at` |
| `:not_configured` | `name: "Usenet client"`, `state: :not_configured`, `state_label: "Not configured"`, `detail: "SABnzbd. Repairs and unpacks; the finished file imports like any other download."`, actions slot with a Set up button |
| `:detected` | `name: "qBittorrent"`, `kind: "torrent"`, `state: :detected`, `state_label: "Detected from Prowlarr, not saved"`, `address: "http://qbittorrent:8080"`, actions Review · Dismiss |
| `:editing` | `state: :ok`, `editing: true`, `edit` slot holding two `settings_field`s and a footer of Cancel / Save and test / Save buttons |
| `:relay` | `name: "wss://relay.example"`, `monospace_name: true`, `state: :ok`, `state_label: "Synced"`, actions Remove |
| `:relay_rejected` | `state: :error`, `state_label: "Rejected"`, `detail: "auth-required: this relay requires authentication"` |

- [ ] **Step 2: Run the compile test to see it fail**, then implement:

```elixir
defmodule MediaCentaurWeb.Components.Settings.ConnectionRow do
  @moduledoc """
  The readout for one external endpoint (UIDR-041 §1): a state dot, the
  name with an optional kind tag, a detail line (the address as a link to
  the endpoint's own web UI, then the credential summary or a
  description), the state word with the test's age, and the actions the
  host passes in. When `editing` the host's `edit` slot renders beneath,
  indented under a hairline. The component draws; `SettingsLive` and
  `ConnectionState` decide.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Live.SettingsLive.ConnectionTest

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :kind, :string, default: nil, doc: "protocol tag beside the name: torrent, usenet."
  attr :monospace_name, :boolean, default: false, doc: "relays: the name is a URL."
  attr :state, :atom, required: true, values: [:not_configured, :not_tested, :ok, :error, :detected]
  attr :state_label, :string, required: true
  attr :tested_at, :any, default: nil, doc: "`DateTime` of the persisted test, or nil."
  attr :address, :string, default: nil, doc: "linked to the endpoint's web UI."
  attr :detail, :string, default: nil, doc: "credential summary, description, or last error."
  attr :editing, :boolean, default: false
  slot :actions
  slot :edit

  def connection_row(assigns) do
    assigns = assign(assigns, :age, assigns.tested_at && ConnectionTest.relative_age(assigns.tested_at))

    ~H"""
    <li id={@id} class="py-3 border-t border-base-content/5 first:border-t-0 first:pt-0 last:pb-0">
      <div class="flex items-center gap-4">
        <span class={["size-2 rounded-full shrink-0", dot_class(@state)]} aria-hidden="true"></span>
        <div class="min-w-0 flex-1">
          <div class="flex items-baseline gap-2">
            <span class={["text-sm font-medium truncate", @monospace_name && "font-mono"]}>{@name}</span>
            <span :if={@kind} class="text-xs text-base-content/55">{@kind}</span>
          </div>
          <div :if={@editing} class="text-xs text-base-content/60">
            Editing. Saving clears the last test; test again afterwards.
          </div>
          <div :if={!@editing && (@address || @detail)} class="text-xs text-base-content/60 flex items-center gap-1.5 min-w-0">
            <a
              :if={@address}
              href={@address}
              target="_blank"
              rel="noopener"
              class="font-mono truncate inline-flex items-center gap-1 hover:text-base-content"
              data-nav-item
              tabindex="0"
            >
              {@address} <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
            </a>
            <span :if={@address && @detail}>·</span>
            <span :if={@detail} class="truncate" title={@detail}>{@detail}</span>
          </div>
        </div>
        <div class={["text-sm shrink-0 text-right", state_text_class(@state)]}>
          {@state_label}
          <span :if={@age} class="text-xs text-base-content/40">· tested {@age}</span>
        </div>
        <div :if={!@editing && @actions != []} class="flex gap-1 shrink-0">{render_slot(@actions)}</div>
      </div>
      <div :if={@editing} class="mt-3 ml-6 pl-4 border-l border-base-content/10">
        {render_slot(@edit)}
      </div>
    </li>
    """
  end

  defp dot_class(:ok), do: "bg-success"
  defp dot_class(:error), do: "bg-error"
  defp dot_class(:not_tested), do: "bg-base-content/30"
  defp dot_class(:detected), do: "bg-base-content/30"
  defp dot_class(:not_configured), do: "bg-base-content/20"

  defp state_text_class(:not_configured), do: "text-base-content/55"
  defp state_text_class(_state), do: "text-base-content/70"
end
```

`ConnectionTest.relative_age/1` returns strings like "118 days ago"; the row prefixes "tested".

- [ ] **Step 3: Render; commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs`
Expected: PASS.

```bash
git add lib/media_centaur_web/components/settings/connection_row.ex storybook/settings/connection_row.story.exs
git commit -m "feat(settings): the connection row"
```

### Task C3: `Capabilities.clear_integration/1`

**Files:**
- Modify: `lib/media_centaur/capabilities.ex` (after `save_integration/2`)
- Test: `test/media_centaur/capabilities_test.exs` (append)

- [ ] **Step 1: Test**

```elixir
  test "clear_integration/1 empties every field of the slot and drops its test result" do
    Config.update(:download_client_type, "qbittorrent")
    Config.update(:download_client_url, "http://localhost:8080")
    Config.update(:download_client_username, "admin")
    Config.update(:download_client_password, "hunter2")
    Capabilities.save_test_result(:download_client, :ok)

    assert :ok = Capabilities.clear_integration(:download_client)

    refute Capabilities.configured?(:download_client)
    assert Config.get(:download_client_username) == nil
    assert Capabilities.load_test_result(:download_client) == nil
  end
```

- [ ] **Step 2: Fail, then implement**

```elixir
  @doc """
  Empties every field of an integration and drops its test result — the
  Remove client action. The slot reads as never configured afterwards.
  """
  @spec clear_integration(subject()) :: :ok
  def clear_integration(subject) do
    @integration_fields
    |> Map.fetch!(subject)
    |> Enum.each(fn {key, _kind} -> Config.update(key, nil) end)

    clear_test_result(subject)
  end
```

- [ ] **Step 3: Pass; commit**

```bash
git add lib/media_centaur/capabilities.ex test/media_centaur/capabilities_test.exs
git commit -m "feat(capabilities): clear an integration's slot"
```

### Task C4: `Ladder` (pure) for the steppers

**Files:**
- Create: `lib/media_centaur_web/live/settings_live/ladder.ex`
- Test: `test/media_centaur_web/live/settings_live/ladder_test.exs`

- [ ] **Step 1: Test**

```elixir
defmodule MediaCentaurWeb.SettingsLive.LadderTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.SettingsLive.Ladder

  @hours [1, 2, 3, 4, 6, 8, 12, 24]

  test "neighbours on a fixed list" do
    assert Ladder.down(@hours, 6) == 4
    assert Ladder.up(@hours, 6) == 8
  end

  test "the ends clamp to themselves" do
    assert Ladder.down(@hours, 1) == 1
    assert Ladder.up(@hours, 24) == 24
  end

  test "a value off the ladder snaps to the nearest rung first" do
    assert Ladder.down(@hours, 5) == 4
    assert Ladder.up(@hours, 5) == 6
  end

  test "a range ladder" do
    assert Ladder.up(Ladder.range(5, 100, 5), 75) == 80
    assert Ladder.down(Ladder.range(1, 50, 1), 1) == 1
  end
end
```

- [ ] **Step 2: Fail, then implement**

```elixir
defmodule MediaCentaurWeb.SettingsLive.Ladder do
  @moduledoc """
  Neighbours on a fixed list of stepper values (UIDR-041 §2). The
  stepper is a dumb renderer that carries absolute targets; the value's
  owner picks them here. Off-ladder values step from the nearest rung.
  """

  @spec range(integer(), integer(), pos_integer()) :: [integer()]
  def range(first, last, step), do: Enum.to_list(first..last//step)

  @spec down([number()], number()) :: number()
  def down(ladder, value) do
    case Enum.filter(ladder, &(&1 < value)) do
      [] -> List.first(ladder)
      lower -> List.last(lower)
    end
  end

  @spec up([number()], number()) :: number()
  def up(ladder, value) do
    case Enum.filter(ladder, &(&1 > value)) do
      [] -> List.last(ladder)
      higher -> List.first(higher)
    end
  end
end
```

- [ ] **Step 3: Pass; commit**

```bash
git add lib/media_centaur_web/live/settings_live/ladder.ex test/media_centaur_web/live/settings_live/ladder_test.exs
git commit -m "feat(settings): stepper ladders"
```

### Task C5: the Acquisition section on the kit, with `SettingsLive`'s row events

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/acquisition_section.ex` (rewrite)
- Modify: `lib/media_centaur_web/live/settings_live.ex` — mount assigns, `section_content("acquisition")`, new events, changed events
- Test: `test/media_centaur_web/live/settings_live_acquisition_test.exs` (rewrite)

- [ ] **Step 1: Rewrite the acquisition test file around rows**

Keep the setup block. Replace the describes with these (each `live_async!(conn, ~p"/settings?section=acquisition")`):

```elixir
  describe "readout" do
    test "a configured install shows rows with no inputs until Edit", %{conn: conn} do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      {:ok, view, html} = live_async!(conn, ~p"/settings?section=acquisition")

      assert html =~ "http://localhost:9696"
      assert html =~ "API key set"
      refute has_element?(view, "#connection-prowlarr input")
      refute has_element?(view, "#connection-prowlarr select")
    end

    test "an unconfigured row reads Not configured with Set up", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      assert has_element?(view, "#connection-prowlarr", "Not configured")
      assert has_element?(view, "#connection-prowlarr-setup", "Set up")
    end

    test "Test on the readout re-tests the saved values and leaves them alone", %{conn: conn} do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view |> element("#connection-prowlarr-test") |> render_click()
      render_async(view)

      assert Config.get(:prowlarr_url) == "http://localhost:9696"
      assert has_element?(view, "#connection-prowlarr", "Connected")
    end
  end

  describe "edit state" do
    setup do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      :ok
    end

    test "Edit opens the form; Cancel closes it with nothing changed", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      assert has_element?(view, "#connection-prowlarr-form input[name=prowlarr_url]")

      view |> element("#connection-prowlarr-cancel") |> render_click()
      refute has_element?(view, "#connection-prowlarr-form")
      assert Config.get(:prowlarr_url) == "http://localhost:9696"
    end

    test "opening a second row's form closes the first", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      view |> element("#connection-torrent-setup") |> render_click()
      refute has_element?(view, "#connection-prowlarr-form")
      assert has_element?(view, "#connection-torrent-form")
    end

    test "Save persists and returns the row to Not tested", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      refute has_element?(view, "#connection-prowlarr-form")
      assert has_element?(view, "#connection-prowlarr", "Not tested")
    end

    test "Save and test persists BEFORE running the test and keeps a failed form open", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "test"})

      render_async(view)
      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      assert has_element?(view, "#connection-prowlarr-form input[value='http://prowlarr.example.com:9696']")
    end

    test "Escape cancels", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      render_keydown(view, "cancel_edit", %{"key" => "Escape"})
      refute has_element?(view, "#connection-prowlarr-form")
    end
  end

  describe "download clients" do
    test "Remove client empties the slot", %{conn: conn} do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://localhost:8080")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-torrent-edit") |> render_click()
      view |> element("#connection-torrent-remove") |> render_click()

      assert Config.get(:download_client_type) == nil
      assert has_element?(view, "#connection-torrent", "Not configured")
    end

    test "a blank API key on save keeps the stored usenet key", %{conn: conn} do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://localhost:8085")
      Config.update(:usenet_download_client_api_key, "keep-me")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-usenet-edit") |> render_click()

      view
      |> form("#connection-usenet-form", %{"usenet_download_client_url" => "http://localhost:8085", "usenet_download_client_api_key" => ""})
      |> render_submit(%{"_action" => "save"})

      assert MediaCentaur.Secret.expose(Config.get(:usenet_download_client_api_key)) == "keep-me"
    end

    test "Detect from Prowlarr puts each client on its row as a pending detection", %{conn: conn} do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"implementation" => "QBittorrent", "name" => "qb", "fields" => [%{"name" => "host", "value" => "qbittorrent"}, %{"name" => "port", "value" => 8080}, %{"name" => "username", "value" => "admin"}]},
          %{"implementation" => "Sabnzbd", "name" => "sab", "fields" => [%{"name" => "host", "value" => "sabnzbd"}, %{"name" => "port", "value" => 8085}]}
        ])
      end)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view |> element("#detect-download-clients") |> render_click()
      render_async(view)

      assert has_element?(view, "#connection-torrent", "Detected from Prowlarr, not saved")
      assert has_element?(view, "#connection-usenet", "Detected from Prowlarr, not saved")
      assert Config.get(:download_client_url) == nil

      view |> element("#connection-torrent-review") |> render_click()
      assert has_element?(view, "#connection-torrent-form input[name=download_client_url][value='http://qbittorrent:8080']")

      view |> element("#connection-usenet-dismiss") |> render_click()
      refute has_element?(view, "#connection-usenet", "Detected from Prowlarr")
    end
  end

  describe "gated cards" do
    test "state their prerequisite while Prowlarr is not ready", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      assert has_element?(view, "#card-download-button", "Available once Prowlarr's connection test passes.")
      assert has_element?(view, "#card-auto-acquisition", "Available once Prowlarr's connection test passes.")
      refute has_element?(view, "#card-auto-acquisition button")
    end
  end

  describe "auto-acquisition rows (Prowlarr ready)" do
    setup do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    test "a choice persists on click", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#auto-grab-default_max_quality button[phx-value-choice=hd_1080p]") |> render_click()
      assert MediaCentaur.Acquisition.AutoGrabSettings.load().default_max_quality == "hd_1080p"
    end

    test "a stepper persists its absolute target", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#auto-grab-pack_min_fit button[aria-label='Increase Season packs']") |> render_click()
      assert MediaCentaur.Acquisition.AutoGrabSettings.load().pack_min_fit == 80
    end

    test "the planning mode is a choice row in the button's words", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#planning-mode button[phx-value-choice=auto_select_best_release]") |> render_click()
      assert MediaCentaur.Settings.Preferences.PlanningMode.value() == :auto_select_best_release
    end
  end

  test "the release-tracking interval steps along its ladder", %{conn: conn} do
    {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
    view |> element("#release-tracking-interval button[aria-label='Increase Check TMDB for new release dates']") |> render_click()
    assert Config.get(:release_tracking_refresh_interval_hours) == 8
  end
```

The detect stub's JSON shape must match what `Acquisition.discover_download_clients_async/1` parses; read `lib/media_centaur/acquisition/` for the Prowlarr `/api/v1/downloadclient` decoder and copy its field names (the existing test at old line 306 has a working payload — reuse it verbatim).

- [ ] **Step 2: Run to verify the suite fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_acquisition_test.exs`
Expected: FAIL on missing ids and events.

- [ ] **Step 3: `SettingsLive` — assigns and events**

In `mount/3` add `|> assign(editing: nil)`.

Events (add near the existing acquisition handlers):

```elixir
  @connection_subjects %{
    "tmdb" => :tmdb,
    "prowlarr" => :prowlarr,
    "torrent" => :download_client,
    "usenet" => :usenet_download_client
  }

  def handle_event("edit_connection", %{"connection" => slot}, socket) when is_map_key(@connection_subjects, slot) do
    {:noreply, assign(socket, editing: String.to_existing_atom(slot))}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("test_connection", %{"connection" => slot}, socket) when is_map_key(@connection_subjects, slot) do
    {:noreply, start_connection_test(socket, @connection_subjects[slot])}
  end

  def handle_event("remove_client", %{"connection" => slot}, socket) when slot in ["torrent", "usenet"] do
    Capabilities.clear_integration(@connection_subjects[slot])

    {:noreply,
     socket
     |> assign(editing: nil, config: load_config())
     |> assign(test_key(@connection_subjects[slot]), nil)
     |> put_flash(:info, "#{slot_name(slot)} removed")}
  end

  def handle_event("review_detected", %{"connection" => slot}, socket) when slot in ["torrent", "usenet"] do
    {:noreply, assign(socket, editing: String.to_existing_atom(slot))}
  end

  def handle_event("dismiss_detected", %{"connection" => "torrent"}, socket),
    do: {:noreply, assign(socket, detected_download_client: nil)}

  def handle_event("dismiss_detected", %{"connection" => "usenet"}, socket),
    do: {:noreply, assign(socket, detected_usenet_client: nil)}

  def handle_event("set_auto_grab", %{"key" => key, "choice" => raw}, socket) do
    if Capabilities.prowlarr_ready?() do
      persist_auto_grab(key, raw)
      {:noreply, assign(socket, auto_grab: AutoGrabSettings.load())}
    else
      {:noreply, put_flash(socket, :error, "Prowlarr is not ready — connect it first")}
    end
  end

  def handle_event("set_planning_mode", %{"choice" => mode}, socket)
      when mode in ~w(manually_select_release auto_select_best_release) do
    planning_mode = PlanningMode.parse(%{"mode" => mode})
    PlanningMode.set(planning_mode)
    {:noreply, assign(socket, planning_mode: planning_mode)}
  end

  def handle_event("set_release_tracking_interval", %{"choice" => raw}, socket) do
    case Integer.parse(raw) do
      {hours, _} when hours in @refresh_hours_ladder ->
        Config.update(:release_tracking_refresh_interval_hours, hours)
        {:noreply, assign(socket, config: load_config())}

      _ ->
        {:noreply, socket}
    end
  end
```

with

```elixir
  @refresh_hours_ladder [1, 2, 3, 4, 6, 8, 12, 24]

  @auto_grab_keys %{
    "default_mode" => {:string, ~w(all_releases ask off)},
    "default_max_quality" => {:string, ~w(uhd_4k hd_1080p)},
    "size_preference" => {:string, ~w(fidelity space)},
    "pack_min_fit" => {:integer, 5..100},
    "max_attempts" => {:integer, 1..50}
  }

  defp persist_auto_grab(key, raw) when is_map_key(@auto_grab_keys, key) do
    {type, allowed} = @auto_grab_keys[key]

    value =
      case {type, raw} do
        {:string, value} when is_binary(value) -> if(value in allowed, do: value)
        {:integer, value} -> with {n, _} <- Integer.parse(value), true <- n in allowed, do: n, else: (_ -> nil)
      end

    if value, do: Settings.find_or_create_entry!(%{key: "auto_grab.#{key}", value: %{"value" => value}})
  end

  defp start_connection_test(socket, :tmdb) do
    socket
    |> assign(tmdb_testing: true)
    |> start_async_test(:tmdb_test_result, fn ->
      case MediaCentaur.TMDB.Client.configuration() do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end
    end)
  end

  defp start_connection_test(socket, :prowlarr) do
    socket
    |> assign(prowlarr_testing: true)
    |> start_async_test(:prowlarr_test_result, fn ->
      case Acquisition.test_prowlarr() do
        :ok -> :ok
        {:error, _} -> :error
      end
    end)
  end

  defp start_connection_test(socket, :download_client) do
    socket
    |> assign(download_client_testing: true)
    |> start_async_test(:download_client_test_result, fn ->
      case Acquisition.test_download_client() do
        :ok -> :ok
        {:error, _} -> :error
      end
    end)
  end

  defp start_connection_test(socket, :usenet_download_client) do
    socket
    |> assign(usenet_client_testing: true)
    |> start_async_test(:usenet_client_test_result, fn ->
      case Acquisition.test_download_client(:usenet) do
        :ok -> :ok
        {:error, _} -> :error
      end
    end)
  end

  defp test_key(:tmdb), do: :tmdb_test
  defp test_key(:prowlarr), do: :prowlarr_test
  defp test_key(:download_client), do: :download_client_test
  defp test_key(:usenet_download_client), do: :usenet_client_test

  defp slot_name("torrent"), do: "Torrent client"
  defp slot_name("usenet"), do: "Usenet client"
```

The four existing `save_*` handlers change in two ways: their `"test"` branch calls `start_connection_test(socket, subject)` instead of inlining the async (delete the inline copies), and their save branch adds `editing: nil` to the assigns. In each `handle_async(:*_test_result, {:ok, status}, socket)` clause, on `:error` leave `editing` as it is (a failed Save and test keeps the form open per D9), on `:ok` set `editing: nil`. Delete `persist_auto_grab_defaults/1`, `coerce/2`, and the `save_auto_grab_defaults` / `save_release_tracking` handlers. Assign `auto_grab: AutoGrabSettings.load()` in mount (and refresh on `set_auto_grab`) instead of loading in `section_content`.

In `render/1` add `phx-window-keydown={@editing && "cancel_edit"} phx-key="Escape"` on the page root div (the `data-page-behavior="settings"` element).

In `section_content("acquisition")`, replace the display maps with a row spec per connection built from `ConnectionState`:

```elixir
  defp section_content(%{active_section: "acquisition"} = assigns) do
    config = assigns.config

    assigns =
      assign(assigns,
        prowlarr_row: connection_row_spec(:prowlarr, config, assigns.prowlarr_test),
        torrent_row: connection_row_spec(:download_client, config, assigns.download_client_test, assigns[:detected_download_client]),
        usenet_row: connection_row_spec(:usenet_download_client, config, assigns.usenet_client_test, assigns[:detected_usenet_client]),
        prowlarr_configured: Capabilities.configured?(:prowlarr),
        prowlarr_ready: Capabilities.prowlarr_ready?()
      )

    ~H"""
    <AcquisitionSection.render
      config={@config}
      editing={@editing}
      prowlarr_row={@prowlarr_row}
      torrent_row={@torrent_row}
      usenet_row={@usenet_row}
      prowlarr_configured={@prowlarr_configured}
      prowlarr_ready={@prowlarr_ready}
      prowlarr_testing={@prowlarr_testing}
      download_client_testing={@download_client_testing}
      download_client_detecting={@download_client_detecting}
      usenet_client_testing={@usenet_client_testing}
      auto_grab={@auto_grab}
      planning_mode={@planning_mode}
    />
    """
  end

  # The row's readout facts. A pending detection wins over the stored
  # values for the form's prefill and marks the row `:detected`.
  defp connection_row_spec(subject, config, test, detected \\ nil) do
    configured? = Capabilities.configured?(subject)
    state = if detected, do: :detected, else: ConnectionState.state(configured?, test)

    %{
      subject: subject,
      state: state,
      state_label: if(detected, do: "Detected from Prowlarr, not saved", else: ConnectionState.label(subject, state)),
      tested_at: if(is_map(test) and is_nil(detected), do: test.tested_at),
      address: address_for(subject, config, detected),
      credential: ConnectionState.credential_summary(subject, config),
      prefill: detected || %{}
    }
  end

  defp address_for(:tmdb, _config, _detected), do: nil
  defp address_for(:prowlarr, config, _detected), do: config[:prowlarr_url]
  defp address_for(:download_client, config, detected), do: detected[:url] || config[:download_client_url]
  defp address_for(:usenet_download_client, config, detected), do: detected[:url] || config[:usenet_download_client_url]
```

`connection_row_spec/4` is used by the TMDB section too (Task C6), so it lives in `SettingsLive` beside `section_content`.

- [ ] **Step 4: Rewrite `acquisition_section.ex`**

```elixir
defmodule MediaCentaurWeb.SettingsLive.AcquisitionSection do
  @moduledoc """
  The Acquisition section of the Settings page (UIDR-041): five cards.
  Search holds the Prowlarr connection row; Download clients the torrent
  and usenet rows with Detect from Prowlarr on the card; Download button
  and Auto-acquisition are gated on Prowlarr's readiness and say so while
  they wait; Release tracking is one stepper. `SettingsLive` builds each
  row's spec (`connection_row_spec/4`), owns `editing`, and hosts every
  event this module names.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.SettingsLive.Ladder

  @refresh_hours [1, 2, 3, 4, 6, 8, 12, 24]
  @pack_fit Ladder.range(5, 100, 5)
  @attempts Ladder.range(1, 50, 1)

  attr :config, :map, required: true
  attr :editing, :atom, default: nil
  attr :prowlarr_row, :map, required: true, doc: "`SettingsLive.connection_row_spec/4` for Prowlarr."
  attr :torrent_row, :map, required: true
  attr :usenet_row, :map, required: true
  attr :prowlarr_configured, :boolean, required: true
  attr :prowlarr_ready, :boolean, required: true
  attr :prowlarr_testing, :boolean, required: true
  attr :download_client_testing, :boolean, required: true
  attr :download_client_detecting, :boolean, required: true
  attr :usenet_client_testing, :boolean, required: true
  attr :auto_grab, MediaCentaur.Acquisition.AutoGrabSettings, required: true
  attr :planning_mode, :atom, required: true, values: [:manually_select_release, :auto_select_best_release]

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.settings_card title="Search">
        <ul>
          <.integration_row
            slot="prowlarr"
            name="Prowlarr"
            row={@prowlarr_row}
            editing={@editing == :prowlarr}
            testing={@prowlarr_testing}
            description="Searches your indexers and forwards each grab to a download client."
          >
            <:form>
              <.settings_field label="Address" layout={:stacked}>
                <input type="text" name="prowlarr_url" value={@config[:prowlarr_url]} placeholder="http://localhost:9696"
                  class="input input-bordered w-full font-mono text-sm" phx-mounted={JS.focus()} data-nav-item tabindex="0" />
              </.settings_field>
              <.settings_field label="API key" description="Prowlarr → Settings → General → Security → API Key." layout={:stacked}>
                <input type="password" name="prowlarr_api_key" autocomplete="off"
                  placeholder={secret_placeholder(@config[:prowlarr_api_key_configured?], "key")}
                  class="input input-bordered w-full font-mono text-sm" data-nav-item tabindex="0" />
              </.settings_field>
            </:form>
          </.integration_row>
        </ul>
      </.settings_card>

      <.settings_card
        title="Download clients"
        description="One client per protocol. Prowlarr sends each grab to the client that matches the indexer."
      >
        <:action>
          <.button
            id="detect-download-clients"
            variant="dismiss"
            size="xs"
            phx-click="detect_download_client"
            disabled={@download_client_detecting || !@prowlarr_configured}
            title={if !@prowlarr_configured, do: "Needs Prowlarr"}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_detecting} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@download_client_detecting} name="hero-magnifying-glass-mini" class="size-3.5" />
            {if @download_client_detecting, do: "Detecting…", else: "Detect from Prowlarr"}
          </.button>
        </:action>
        <ul>
          <.integration_row
            slot="torrent"
            name={if @torrent_row.state == :not_configured, do: "Torrent client", else: "qBittorrent"}
            kind="torrent"
            row={@torrent_row}
            editing={@editing == :torrent}
            testing={@download_client_testing}
            removable
            description="qBittorrent. Also powers the download progress on Incoming."
          >
            <:form>
              <div class="flex gap-3">
                <.settings_field label="Client" layout={:stacked} class="w-44 shrink-0">
                  <select name="download_client_type" class="select select-bordered w-full text-sm" data-nav-item tabindex="0">
                    <option value="qbittorrent" selected>qBittorrent</option>
                  </select>
                </.settings_field>
                <.settings_field label="Address" layout={:stacked} class="min-w-0 flex-1"
                  description="Must be reachable from this machine. A detected address is often a hostname that only resolves inside Docker.">
                  <input type="text" name="download_client_url" value={@torrent_row.prefill[:url] || @config[:download_client_url]}
                    placeholder="http://localhost:8080" class="input input-bordered w-full font-mono text-sm" phx-mounted={JS.focus()} data-nav-item tabindex="0" />
                </.settings_field>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <.settings_field label="Username" layout={:stacked}>
                  <input type="text" name="download_client_username" value={@torrent_row.prefill[:username] || @config[:download_client_username]}
                    placeholder="admin" autocomplete="off" class="input input-bordered w-full font-mono text-sm" data-nav-item tabindex="0" />
                </.settings_field>
                <.settings_field label="Password" layout={:stacked}>
                  <input type="password" name="download_client_password" autocomplete="off"
                    placeholder={secret_placeholder(@config[:download_client_password_configured?], "password")}
                    class="input input-bordered w-full font-mono text-sm" data-nav-item tabindex="0" />
                </.settings_field>
              </div>
            </:form>
          </.integration_row>

          <.integration_row
            slot="usenet"
            name={if @usenet_row.state == :not_configured, do: "Usenet client", else: "SABnzbd"}
            kind="usenet"
            row={@usenet_row}
            editing={@editing == :usenet}
            testing={@usenet_client_testing}
            removable
            description="SABnzbd. Repairs and unpacks; the finished file imports like any other download."
          >
            <:form>
              <div class="flex gap-3">
                <.settings_field label="Client" layout={:stacked} class="w-44 shrink-0">
                  <select name="usenet_download_client_type" class="select select-bordered w-full text-sm" data-nav-item tabindex="0">
                    <option value="sabnzbd" selected>SABnzbd</option>
                  </select>
                </.settings_field>
                <.settings_field label="Address" layout={:stacked} class="min-w-0 flex-1"
                  description="Must be reachable from this machine. A detected address is often a hostname that only resolves inside Docker.">
                  <input type="text" name="usenet_download_client_url" value={@usenet_row.prefill[:url] || @config[:usenet_download_client_url]}
                    placeholder="http://localhost:8085" class="input input-bordered w-full font-mono text-sm" phx-mounted={JS.focus()} data-nav-item tabindex="0" />
                </.settings_field>
              </div>
              <.settings_field label="API key" description="SABnzbd → Config → General → API Key." layout={:stacked}>
                <input type="password" name="usenet_download_client_api_key" autocomplete="off"
                  placeholder={secret_placeholder(@config[:usenet_download_client_api_key_configured?], "key")}
                  class="input input-bordered w-full font-mono text-sm" data-nav-item tabindex="0" />
              </.settings_field>
            </:form>
          </.integration_row>
        </ul>
      </.settings_card>

      <.settings_card id="card-download-button" title="Download button">
        <.gate :if={!@prowlarr_ready} />
        <.settings_choice
          :if={@prowlarr_ready}
          id="planning-mode"
          label="Default action on a title you don't own yet"
          description="The other choice stays in the button's menu."
          options={for mode <- PlanningMode.modes(), do: {Atom.to_string(mode), Logic.planning_mode_label(mode)}}
          selected={Atom.to_string(@planning_mode)}
          event="set_planning_mode"
        />
      </.settings_card>

      <.settings_card
        id="card-auto-acquisition"
        title="Auto-acquisition"
        description={@prowlarr_ready && "Applied when a tracked title's release appears. A title's own tracking controls take precedence."}
      >
        <.gate :if={!@prowlarr_ready} />
        <div :if={@prowlarr_ready} class="space-y-0.5">
          <.settings_choice
            id="auto-grab-default_mode"
            label="When a release appears"
            description="Ask first parks the plan on Incoming until you approve it."
            options={[{"all_releases", "Grab it"}, {"ask", "Ask first"}, {"off", "Notify only"}]}
            selected={@auto_grab.default_mode}
            event="set_auto_grab"
            event_value={%{"key" => "default_mode"}}
          />
          <.settings_choice
            id="auto-grab-default_max_quality"
            label="Highest resolution"
            description="The best available is taken right away. Nothing found at this resolution falls back to 1080p; anything lower needs the title's own acceptance."
            options={[{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}]}
            selected={@auto_grab.default_max_quality}
            event="set_auto_grab"
            event_value={%{"key" => "default_max_quality"}}
          />
          <.settings_choice
            id="auto-grab-size_preference"
            label="Within a resolution"
            description="Best fidelity takes a remux first. Save space takes compact encodes first, and still takes a remux when nothing smaller exists."
            options={[{"fidelity", "Best fidelity"}, {"space", "Save space"}]}
            selected={@auto_grab.size_preference}
            event="set_auto_grab"
            event_value={%{"key" => "size_preference"}}
          />
          <.settings_stepper
            id="auto-grab-pack_min_fit"
            label="Season packs"
            description="Take a pack only when you want at least this share of its episodes. Below it, episodes are grabbed one by one and the pack is offered."
            value_label={"#{@auto_grab.pack_min_fit}%"}
            down_value={Ladder.down(@pack_fit, @auto_grab.pack_min_fit)}
            up_value={Ladder.up(@pack_fit, @auto_grab.pack_min_fit)}
            reset_value={75}
            at_min={@auto_grab.pack_min_fit <= 5}
            at_max={@auto_grab.pack_min_fit >= 100}
            at_default={@auto_grab.pack_min_fit == 75}
            event="set_auto_grab"
            event_value={%{"key" => "pack_min_fit"}}
          />
          <.settings_stepper
            id="auto-grab-max_attempts"
            label="Search attempts"
            description="Failed search cycles before a release is given up on."
            value_label={Integer.to_string(@auto_grab.max_attempts)}
            down_value={Ladder.down(@attempts, @auto_grab.max_attempts)}
            up_value={Ladder.up(@attempts, @auto_grab.max_attempts)}
            reset_value={12}
            at_min={@auto_grab.max_attempts <= 1}
            at_max={@auto_grab.max_attempts >= 50}
            at_default={@auto_grab.max_attempts == 12}
            event="set_auto_grab"
            event_value={%{"key" => "max_attempts"}}
          />
        </div>
      </.settings_card>

      <.settings_card title="Release tracking">
        <.settings_stepper
          id="release-tracking-interval"
          label="Check TMDB for new release dates"
          description="A change applies after the current cycle finishes."
          value_label={"every #{refresh_hours(@config)}h"}
          down_value={Ladder.down(@refresh_hours, refresh_hours(@config))}
          up_value={Ladder.up(@refresh_hours, refresh_hours(@config))}
          reset_value={6}
          at_min={refresh_hours(@config) <= 1}
          at_max={refresh_hours(@config) >= 24}
          at_default={refresh_hours(@config) == 6}
          event="set_release_tracking_interval"
        />
      </.settings_card>
    </div>
    """
  end

  defp refresh_hours(config), do: config[:release_tracking_refresh_interval_hours] || 6

  defp secret_placeholder(true, noun), do: "Leave blank to keep the current #{noun}"
  defp secret_placeholder(_stored, "key"), do: "Enter the API key"
  defp secret_placeholder(_stored, "password"), do: "Enter the password"

  # The one line a gated card shows while Prowlarr is not ready (UIDR-041 §4).
  defp gate(assigns) do
    ~H"""
    <p class="text-sm text-base-content/60">Available once Prowlarr's connection test passes.</p>
    """
  end

  attr :slot, :string, required: true, values: ["tmdb", "prowlarr", "torrent", "usenet"]
  attr :name, :string, required: true
  attr :kind, :string, default: nil
  attr :row, :map, required: true
  attr :editing, :boolean, required: true
  attr :testing, :boolean, required: true
  attr :removable, :boolean, default: false
  attr :description, :string, required: true, doc: "shown on the detail line while nothing is configured."
  slot :form, required: true

  # A connection row for one integration: the readout's actions per state
  # and the edit form with its footer. Used by this section and by the
  # TMDB section, so it is public.
  def integration_row(assigns) do
    ~H"""
    <.connection_row
      id={"connection-#{@slot}"}
      name={@name}
      kind={@kind}
      state={@row.state}
      state_label={@row.state_label}
      tested_at={@row.tested_at}
      address={if @row.state != :not_configured, do: @row.address}
      detail={if @row.state == :not_configured, do: @description, else: @row.credential}
      editing={@editing}
    >
      <:actions>
        <%= case @row.state do %>
          <% :not_configured -> %>
            <.button id={"connection-#{@slot}-setup"} variant="secondary" size="xs" phx-click="edit_connection" phx-value-connection={@slot} data-nav-item tabindex="0">
              Set up
            </.button>
          <% :detected -> %>
            <.button id={"connection-#{@slot}-review"} variant="secondary" size="xs" phx-click="review_detected" phx-value-connection={@slot} data-nav-item tabindex="0">
              Review
            </.button>
            <.button id={"connection-#{@slot}-dismiss"} variant="dismiss" size="xs" phx-click="dismiss_detected" phx-value-connection={@slot} data-nav-item tabindex="0">
              Dismiss
            </.button>
          <% _configured -> %>
            <.button id={"connection-#{@slot}-test"} variant="neutral" size="xs" phx-click="test_connection" phx-value-connection={@slot} disabled={@testing} data-nav-item tabindex="0">
              <span :if={@testing} class="loading loading-spinner loading-xs"></span>
              <.icon :if={!@testing} name="hero-signal-mini" class="size-3.5" />
              {if @testing, do: "Testing…", else: "Test"}
            </.button>
            <.button id={"connection-#{@slot}-edit"} variant="dismiss" size="xs" phx-click="edit_connection" phx-value-connection={@slot} data-nav-item tabindex="0">
              Edit
            </.button>
        <% end %>
      </:actions>
      <:edit>
        <form id={"connection-#{@slot}-form"} phx-submit={save_event(@slot)} class="space-y-4">
          {render_slot(@form)}
          <div class="flex items-center justify-between gap-3 pt-1">
            <div>
              <.button :if={@removable} id={"connection-#{@slot}-remove"} variant="destructive_inline" size="sm" type="button" phx-click="remove_client" phx-value-connection={@slot} data-nav-item tabindex="0">
                Remove client
              </.button>
            </div>
            <div class="flex items-center gap-2">
              <.button id={"connection-#{@slot}-cancel"} variant="dismiss" size="sm" type="button" phx-click="cancel_edit" data-nav-item tabindex="0">Cancel</.button>
              <.button type="submit" variant="neutral" size="sm" name="_action" value="test" disabled={@testing} data-nav-item tabindex="0">
                <.icon name="hero-signal-mini" class="size-4" /> Save and test
              </.button>
              <.button type="submit" variant="secondary" size="sm" name="_action" value="save" data-nav-item tabindex="0">Save</.button>
            </div>
          </div>
        </form>
      </:edit>
    </.connection_row>
    """
  end

  defp save_event("tmdb"), do: "save_tmdb"
  defp save_event("prowlarr"), do: "save_prowlarr"
  defp save_event("torrent"), do: "save_download_client"
  defp save_event("usenet"), do: "save_usenet_client"
end
```

`settings_field/1` gains a `class` attr (string, default nil) on its outer div for the two-column form rows; add it in the kit with the change. `integration_row/1` is a function component under `live/`, not `components/`, so MC0009 does not require a story; its states are the connection row's, which has one.

- [ ] **Step 5: Run the acquisition suite until green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_acquisition_test.exs`
Expected: PASS. Then look at it: `~/scripts/agents/page-shot --url 'http://127.0.0.1:2160/settings?section=acquisition' --selector '[data-nav-zone=grid]' --viewport 1920x1080 --wait-ms 3500 -o /tmp/acq-new.png` and compare with the approved mockup (`scratchpad/settings-mockup.html`, artboard 1): row heights, the address link, the state column alignment.

- [ ] **Step 6: Screenshot-tour locators**

In `test/e2e/screenshot.tour.js` lines ~179–200 replace `#settings-download-client` with `#connection-torrent` and `#settings-prowlarr` with `#connection-prowlarr`. No regeneration.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live/acquisition_section.ex lib/media_centaur_web/components/settings.ex test/media_centaur_web/live/settings_live_acquisition_test.exs test/e2e/screenshot.tour.js
git commit -m "feat(settings): acquisition is connection rows, choices and steppers"
```

### Task C6: TMDB on the same row

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/tmdb.ex` (rewrite), `settings_live.ex` `section_content("tmdb")`
- Test: `test/media_centaur_web/live/settings_live_acquisition_test.exs` "tmdb form" describe

- [ ] **Step 1: Test** — replace the tmdb describe with:

```elixir
  describe "tmdb row" do
    test "Save and test persists the key BEFORE running the test", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=tmdb")
      view |> element("#connection-tmdb-setup") |> render_click()

      view
      |> form("#connection-tmdb-form", %{"tmdb_api_key" => "tmdb-key-123"})
      |> render_submit(%{"_action" => "test"})

      render_async(view)
      assert MediaCentaur.Secret.expose(Config.get(:tmdb_api_key)) == "tmdb-key-123"
    end
  end
```

(The setup block resets `:tmdb_api_key` too — add `Config.update(:tmdb_api_key, nil)` to it.)

- [ ] **Step 2: Implement**

```elixir
defmodule MediaCentaurWeb.SettingsLive.Tmdb do
  @moduledoc "The TMDB section of the Settings page: one card, one connection row (UIDR-041)."

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.SettingsLive.AcquisitionSection, only: [integration_row: 1]

  attr :config, :map, required: true
  attr :row, :map, required: true
  attr :editing, :boolean, required: true
  attr :tmdb_testing, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.settings_card title="TMDB">
      <ul>
        <.integration_row
          slot="tmdb"
          name="The Movie Database"
          row={@row}
          editing={@editing}
          testing={@tmdb_testing}
          description="Metadata and artwork for everything in the library."
        >
          <:form>
            <.settings_field label="API key" layout={:stacked}>
              <input type="password" name="tmdb_api_key" autocomplete="off"
                placeholder={if @config[:tmdb_api_key_configured?], do: "Leave blank to keep the current key", else: "Enter the API key"}
                class="input input-bordered w-full font-mono text-sm" phx-mounted={JS.focus()} data-nav-item tabindex="0" />
              <p class="mt-1 text-xs text-base-content/55">
                Free at <a href="https://www.themoviedb.org/settings/api" target="_blank" rel="noopener noreferrer" class="link link-primary">themoviedb.org/settings/api</a>.
              </p>
            </.settings_field>
          </:form>
        </.integration_row>
      </ul>
    </.settings_card>
    """
  end
end
```

`section_content("tmdb")` passes `row={connection_row_spec(:tmdb, @config, @tmdb_test)}` and `editing={@editing == :tmdb}`.

- [ ] **Step 3: Pass; precommit; commit**

Run: `~/scripts/agents/agent-mix precommit` → PASS.

```bash
git add lib/media_centaur_web/live/settings_live/tmdb.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur_web/live/settings_live_acquisition_test.exs
git commit -m "feat(settings): TMDB is a connection row"
```

### Task C7: wiki for Acquisition and TMDB

- [ ] **Step 1: Rewrite `Settings-Reference.md` §Acquisition and §TMDB** in the reference register: one table per card (Row · Kind · Options/ladder · Default · Effect), the connection-row states table from spec D7, and the edit-form fields table from D9. Delete the Save-per-form instructions. In `Download-Clients.md` and `Prowlarr-Integration.md`, replace "click Save, then Test connection" flows with "press Set up on the row, fill the form, press Save and test".

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Acquisition and TMDB settings as connection rows" && cd -
```

---

## Phase D — Social on the kit (D2, D15)

### Task D1: three cards, relays as connection rows

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/social_section.ex`
- Test: `test/media_centaur_web/live/settings_live_social_test.exs:98-140`

- [ ] **Step 1: Tests** — in the relays describe, replace the "lights the section's status dot" case with:

```elixir
    test "a relay row's dot follows its connection state", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=social")
      view |> form("#add-relay-form", %{"url" => "wss://relay.example"}) |> render_submit()

      send(view.pid, {:relay_status, %{"wss://relay.example" => %{state: :synced, last_error: nil}}})
      assert has_element?(view, "#relay-wss-relay-example .bg-success")
      assert has_element?(view, "#relay-wss-relay-example", "Synced")

      send(view.pid, {:relay_status, %{"wss://relay.example" => %{state: :auth_failed, last_error: "auth-required"}}})
      assert has_element?(view, "#relay-wss-relay-example .bg-error")
      assert has_element?(view, "#relay-wss-relay-example", "auth-required")
    end
```

(Use whatever message the existing test sends to simulate a status update; keep its shape.) Add `refute html =~ "Social <span"` is not needed; instead assert the section renders three cards: `assert html =~ "Your identity"`, `"Relays"`, `"Sharing"` as `h3` text.

- [ ] **Step 2: Implement** — `render/1` becomes three `settings_card`s. Your identity: the card description, the npub `code` + Copy row, and `settings_disclosure` label "Secret key" wrapping the existing reveal/import block unchanged. Relays:

```heex
<.settings_card title="Relays" description="The servers your activity is published to and read from. Your group's own relay first; public relays are more entries.">
  <ul :if={@relays != []}>
    <.connection_row
      :for={relay <- @relays}
      id={relay_dom_id(relay.url)}
      name={relay.url}
      monospace_name
      state={relay_state(@status[relay.url])}
      state_label={RelayStatusRow.state_label(@status[relay.url])}
      detail={last_error(@status[relay.url])}
    >
      <:actions>
        <.button variant="dismiss" size="xs" phx-click="remove_relay" phx-value-url={relay.url} data-nav-item tabindex="0">Remove</.button>
      </:actions>
    </.connection_row>
  </ul>
  <form id="add-relay-form" phx-submit="add_relay" class="flex items-center gap-2 pt-1">
    …unchanged input + Add relay…
  </form>
</.settings_card>
```

with

```elixir
  defp relay_state(%{state: state}) when state in [:connected, :synced], do: :ok
  defp relay_state(%{state: :connecting}), do: :not_tested
  defp relay_state(_absent_or_failed), do: :error
```

Sharing: `settings_card` with the two `settings_row`s. Delete `any_connected?/1` and the section-level `h2`; `import MediaCentaurWeb.Components.Settings.ConnectionRow`.

- [ ] **Step 3: Pass; precommit; wiki §Social (remove the header-dot sentence, describe the row dot); commit**

```bash
git add lib/media_centaur_web/live/settings_live/social_section.ex test/media_centaur_web/live/settings_live_social_test.exs
git commit -m "feat(settings): social is three cards; relays are connection rows"
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Social settings rows" && cd -
```

---

## Phase E — the remaining sections adopt the kit

One task per section; each is a commit. The rule for every task: cards become `settings_card`; fields become rows of the kind the spec's table names; Save buttons go; the section's tests move from `form(...) |> render_submit` to the row's event. Each task ends with `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/page_smoke_test.exs` green and a look at the section on the dev server.

### Task E1: Services, Preferences, Controls

- Services: `settings_card title="Background services"`, body the four `settings_row`s. Preferences: `settings_card title="Display"` for the toggles and the interface-scale stepper (one card). Controls: each binding group (`controls.ex:72`) is a `settings_card` with its group name; the `text-2xl` heading was already removed in B3.
- Commit: `refactor(settings): services, preferences and controls on the kit`.

### Task E2: Library

**Files:** `library.ex`, `settings_live.ex` (`save_data_dir` handler accepts the text row's payloads; two new stepper events), `settings_live_test.exs`.

- Data directory → `settings_text_row` (`name: "data_dir"`, `event: "save_data_dir"`, `mono`). The handler:

```elixir
  def handle_event("save_data_dir", %{"value" => value}, socket), do: save_data_dir(value, socket)
  def handle_event("save_data_dir", %{"data_dir" => value}, socket), do: save_data_dir(value, socket)
```

with `save_data_dir/2` the existing body. A blur that changes nothing must not flash: compare with `Config.get(:data_dir)` first.

- Cleanup → two `settings_stepper`s, events `set_absence_ttl_days` and `set_recent_changes_days`, ladder `Ladder.range(1, 14, 1) ++ Ladder.range(21, 90, 7)`, defaults from `Config`. Handlers write `Config.update/2` with the parsed integer when it is on the ladder.
- Media directories and Excluded directories: already list settings; wrap in `settings_card` (title, existing `:action` Add).
- Tests: add "typing a data directory and blurring persists it" and "stepping the absence TTL persists" cases; delete the Save-based ones.
- Commit: `refactor(settings): library on the kit; cleanup windows are steppers`.

### Task E3: Media Import

**Files:** `import_section.ex`, `settings_live.ex` (`save_import` splits into `add_extras_dir`, `remove_extras_dir`, `add_skip_dir`, `remove_skip_dir`, `set_auto_approve_threshold`, `set_image_resolution`), `settings_live_test.exs:383-447`.

- Extras folder names and Ignored folder names → list settings: `settings_card` each; `<ul>` of rows (`<li class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2">` name + Remove button `phx-value-name`), then `<form phx-submit="add_extras_dir" class="flex items-center gap-2 pt-1">` with a text input `name="name"` and an Add button. Handlers append/remove on the config list (trim, reject blank, no duplicates) and `Config.update/2`.
- Auto-approve threshold → `settings_stepper`, ladder `for n <- 50..100//5, do: n / 100`, `value_label` formatted `"0.85"`, event `set_auto_approve_threshold` (Float.parse; accept when on the ladder within 0.001).
- Artwork resolution → `settings_choice` (`[{"4k", "4K"}, {"1080p", "1080p"}]`, event `set_image_resolution`); the handler keeps the re-fetch trigger that `save_import` ran when the resolution changed (`settings_live.ex:1030-1060`).
- Tests: the four media-import cases move to the new events (`render_click` on the choice; the re-fetch assertions stay).
- Commit: `refactor(settings): media import on the kit; folder names are lists`.

### Task E4: Playback

- mpv path and IPC socket directory → `settings_text_row` (`mono`, `label_suffix` slot holding `path_status`), events `set_mpv_path`, `set_mpv_socket_dir`; timeout → `settings_stepper` ladder `Ladder.range(100, 5000, 100)`, event `set_mpv_socket_timeout_ms`. Handlers `Config.update/2`. Delete `save_playback`.
- Commit: `refactor(settings): playback on the kit`.

### Task E5: Language

- "Languages you understand" card: `settings_card` around the existing add form and chip list. "Audio & subtitles": one `settings_card` with a `settings_select_row` per policy select (`language.ex:136-242`; `name` and `options` are each select's existing ones), event `set_language_policy`; the handler receives `%{name => value}` (one key per change), merges it into the draft the existing `save_language_policy` normalised, and persists through the same `LanguagePolicy` write. Delete the Save.
- Tests: `settings_live_test.exs:306` "saving the audio/subtitle form persists a normalized policy" becomes one `render_change` per select.
- Commit: `refactor(settings): language policy selects save on change`.

### Task E6: Maintenance and Danger Zone

- Maintenance: one `settings_card title="Library repairs"` (or split by the existing groups if `maintenance_section.ex` already groups them) with an action row per repair: `<div class="flex items-start justify-between py-2.5 px-3.5 gap-4">` label + description left, the existing button right. Danger: `settings_card class="border border-error/20" title="Danger zone"` with the existing action row and the triangle glyph beside the label.
- Commit: `refactor(settings): maintenance and danger zone on the kit`.

### Task E7: System

- Service, Health Check, Guide and Updates cards → `settings_card` (title, description = today's subtitle, `:action` = today's right-hand control). Updates: the interval input → `settings_stepper` over `[15, 30, 60, 120, 240, 720, 1440]` minutes (floor applied from `Config.update_check_interval_floor_minutes/0`), event `set_update_check_interval`; its toggles are already rows. The grouped status lists and the identity block stay.
- Tests: `settings_live_update_automation_test.exs` interval cases move to the stepper.
- Commit: `refactor(settings): system on the kit`.

### Task E8: retire what nothing calls

- Delete `settings_card_header/1`, `status_dot/1`, `connection_status/1` from the kit and their stories if any were added; `grep -rn "settings_card_header\|status_dot\|connection_status" lib/ storybook/` returns nothing.
- `~/scripts/agents/agent-mix precommit` → PASS.
- Commit: `chore(settings): retire the pre-kit header and status helpers`.

### Task E9: wiki for the remaining sections

- `Settings-Reference.md` §System (Updates interval as a stepper), §Library (Data directory commits on Enter or blur; Cleanup steppers), §Media Import (lists, stepper, choice), §Playback, §Language (selects save on change). Reference register: tables.

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Settings reference on the readout kit" && cd -
```

---

## Phase F — closure

### Task F1: terms, docs, skill

- `docs/GLOSSARY.md`: add rows for **Connection row**, **Readout state / Edit state**, **Save on the act**, **Gated card**, **Settings kit** (from the spec's glossary; owner-module column names `MediaCentaurWeb.Components.Settings` / `.ConnectionRow`).
- `.claude/skills/user-interface/SKILL.md`: the "Non-toggle settings controls" section becomes a "Settings kit" section listing the row kinds and the connection row, pointing at `/storybook/settings/*`; the component inventory gains the kit; the stale `settings_choice`-from-git sentence goes.
- `docs/storybook.md`: the settings area in the triage table.
- `campaigns/settings-readout-kit.md`: reconcile, then retire the file and its README entry (ADR-042).
- Commit: `docs: settings kit terms, skill and storybook notes`.

### Task F2: owner look

Open `/settings?section=acquisition`, `?section=social`, `?section=import` on the dev server for the owner. Do not screenshot when their browser is open. Note anything they want changed in the campaign file before retiring it.

---

## Self-review

**Spec coverage.** D1 → B3. D2 → B2 (card) + every E task. D3 → B1/B2 (row kinds) + C5/E. D4 → C5 (auto-grab, planning mode, release tracking), E2–E7. D5 → B1/B2/C2 (stories). D6–D8 → C1/C2/C5. D9 → C5 (`integration_row` footer, save-then-test, `editing` on failure). D10 → C5 (`edit_connection` replaces `editing`). D11 → C5 (`description` while not configured, Set up). D12 → C3/C5. D13 → C5 (`review_detected`/`dismiss_detected`, card action). D14 → C6. D15 → D1. D16–D19 → C5. D20 → Phase A. D21 → C5. Other-sections table → E1–E7. Copy → spec words used verbatim. Wiki/tour → A7, C5 step 6, C7, D1, E9. Anti-patterns: E8 removes the last header/status helpers; no card header carries a Save after E.

**Type consistency.** `connection_row_spec/4` returns `%{subject, state, state_label, tested_at, address, credential, prefill}` and `integration_row/1` reads exactly those keys. `ConnectionState.state/2` values match `connection_row/1`'s `values:` list plus `:detected`, which `connection_row_spec/4` sets itself. `settings_choice/1` and `settings_stepper/1` both push `choice`; `set_auto_grab` reads `key` + `choice`; `settings_stepper/1` needs an `event_value` attr for `key` — add it in B1 (same `phx_values/1` spread as `settings_row/1`) and an `id` attr, and change its three `aria-label`s from "Decrease scale" to `"Decrease #{@label}"` etc., which the C5 tests rely on. `Ladder.range/3` returns a list, so `@pack_fit` and `@attempts` are module attributes computed at compile time.

**Placeholders.** The E tasks give rows, events, ladders and handler shapes rather than full templates; the templates are one component call per row with the attrs those tables name, against the component contracts defined in full in B1/B2/C2. The detect-stub payload in C5 must be copied from the existing test (named), not invented.
