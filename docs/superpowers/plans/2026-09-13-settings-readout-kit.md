# Settings Readout Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Settings section composes from one kit whose resting state is a readout: an external connection is a row that shows what is configured and how it is doing, its form appears only on Edit, and every other setting saves the moment it changes.

**Architecture:** `MediaCentaur.IntegrationHealth` becomes the one owner of connection state for the four `Capabilities` subjects: it runs every connection test, persists an explicit verify's result for readiness, seeds from the persisted test at boot and probes nothing on its own. The shared kit moves to `MediaCentaurWeb.Components.Settings` under the components tree with one new component, `connection_row/1`, a pure projection of the owner's status. The Settings shell renders each section's intro; section modules render cards of rows; `SettingsLive` holds `connections` and `editing`, one `save_connection` event and per-row events, and no test machinery of its own. Independently, the automatic quality policy loses its configurable floor and its 4K patience window, with a data migration that deletes the retired rows.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView 1.x, Ecto + SQLite, Phoenix Storybook, ExUnit, Tailwind v4 + daisyUI.

**Spec:** `docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md` (decisions cited as D1…D33). **Record:** UIDR-041. **Campaign:** `campaigns/settings-readout-kit.md`.

---

## Ground rules

- **Never run `mix` directly.** Every command below uses `~/scripts/agents/agent-mix`, which points `MIX_BUILD_ROOT` outside the checkout. A bare `mix` writes `.beam` files under the running dev server and can take it down.
- Tests before implementation. No network in tests: integrations go through their `Req.Test` stubs or the injected `integration_health_verifier`.
- Storybook-first for components that already have a story; new components get their story in the same task (MC0009 fails precommit otherwise). Stories live under `storybook/settings/`, module namespace `MediaCentaurWeb.Storybook.Settings.*`.
- User-facing words are the spec's. Any new sentence goes through the two writing-copy gates.
- `~/scripts/agents/agent-mix precommit` before the last commit of every phase; zero warnings.
- Commit after each task. Work on `main`; do not push until told.
- **Release grouping:** Phases A, C and D ship in one release (A leaves two dead form fields until D; C leaves two writers of the persisted test until D). Phases B, E, F, G can each ship alone.

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `lib/media_centaur/settings/ladder.ex` | `MediaCentaur.Settings.Ladder`: neighbours on a fixed list of stepper values (pure) |
| `lib/media_centaur_web/components/settings.ex` | `MediaCentaurWeb.Components.Settings`: `settings_card/1`, `settings_row/1`, `settings_stepper/1`, `settings_choice/1`, `settings_text_row/1`, `settings_select_row/1`, `settings_field/1`, `settings_input/1`, `settings_list/1`, `settings_disclosure/1`, `path_status/1` |
| `lib/media_centaur_web/components/settings/connection_row.ex` | `MediaCentaurWeb.Components.Settings.ConnectionRow`: `connection_row/1` |
| `lib/media_centaur_web/live/settings_live/connection_state.ex` | `MediaCentaurWeb.SettingsLive.ConnectionState`: struct + `build/3` from `%IntegrationHealth.Status{}` and the config map (pure) |
| `storybook/settings/_settings.index.exs` and one `storybook/settings/<function>.story.exs` per kit function | The kit's contracts |
| `priv/repo/data_migrations/20260913120000_quality_policy_loses_floor_and_patience.exs` | Deletes the retired settings rows; strips the retired per-title keys |
| `test/media_centaur/settings/ladder_test.exs`, `test/media_centaur_web/live/settings_live/connection_state_test.exs` | Pure tests |

**Modified**

| Path | Change |
|---|---|
| `lib/media_centaur/acquisition/auto_grab_settings.ex` | Drop floor + patience; `floor/0`; `effective_min_quality/1`; `put/2`; ladders |
| `lib/media_centaur/acquisition/want_schedule.ex`, `download_params.ex`, `drop_planner.ex`, `jobs/pursue_target.ex`, `jobs/run_plan.ex` | No patience; constant floor |
| `lib/media_centaur/integration_health.ex`, `integration_health/verifier.ex`, `integration_health/status.ex` | Four ids; per-slot verifier; persist explicit verifies; seed from persisted; `:unknown` on config change |
| `lib/media_centaur/downloads.ex` | `config_key?/1` removed |
| `lib/media_centaur/capabilities.ex` | `clear_integration/1` |
| `lib/media_centaur/settings.ex` | Boundary exports `Ladder` |
| `lib/media_centaur_web/live/settings_live.ex` | Section descriptions + intro; `connections`, `editing`; `save_connection` and row events; test machinery removed; auto-grab through `AutoGrabSettings.put/2` |
| Every section module under `lib/media_centaur_web/live/settings_live/` | On the kit |
| `test/media_centaur/integration_health_test.exs`, `test/media_centaur_web/live/settings_live_acquisition_test.exs`, `settings_live_social_test.exs`, `settings_live_test.exs`, `settings_live_update_automation_test.exs` | Rewritten around the owner and the rows |
| `test/e2e/screenshot.tour.js:175-200` | Locators |
| Wiki: `Settings-Reference.md`, `Release-Tracking.md`, `Download-Clients.md`, `Prowlarr-Integration.md`, `Setup` page if it names Test | Rows as shipped |

**Deleted**

| Path | Why |
|---|---|
| `lib/media_centaur_web/live/settings_live/components.ex` | Moved to the components tree |

---

## Phase A — the quality policy loses its floor and its patience window (D20, D29)

### Task A1: `AutoGrabSettings` — constant floor, no patience, `put/2`

**Files:**
- Modify: `lib/media_centaur/acquisition/auto_grab_settings.ex`
- Test: `test/media_centaur/acquisition/auto_grab_settings_test.exs`

- [ ] **Step 1: Rewrite the test file** (full file; the `load/0` overrides keep mode, max_attempts, pack fit and size preference):

```elixir
defmodule MediaCentaur.Acquisition.AutoGrabSettingsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Settings

  describe "load/0 — defaults when nothing persisted" do
    test "returns built-in defaults when no settings rows exist" do
      settings = AutoGrabSettings.load()

      assert settings.default_mode == "all_releases"
      assert settings.default_max_quality == "uhd_4k"
      assert settings.max_attempts == 12
      assert settings.pack_min_fit == 75
      assert settings.size_preference == "fidelity"
    end

    test "the struct carries no floor or patience field" do
      refute Map.has_key?(%AutoGrabSettings{}, :default_min_quality)
      refute Map.has_key?(%AutoGrabSettings{}, :patience_hours)
    end
  end

  describe "load/0 — values overridden by Settings entries" do
    test "respects mode override" do
      Settings.find_or_create_entry!(%{key: "auto_grab.default_mode", value: %{"value" => "off"}})
      assert %{default_mode: "off"} = AutoGrabSettings.load()
    end

    test "respects integer overrides" do
      Settings.find_or_create_entry!(%{key: "auto_grab.max_attempts", value: %{"value" => 6}})
      assert %{max_attempts: 6} = AutoGrabSettings.load()
    end

    test "respects pack-fit override" do
      Settings.find_or_create_entry!(%{key: "auto_grab.pack_min_fit", value: %{"value" => 50}})
      assert %{pack_min_fit: 50} = AutoGrabSettings.load()
    end

    test "respects size-preference override" do
      Settings.find_or_create_entry!(%{key: "auto_grab.size_preference", value: %{"value" => "space"}})
      assert %{size_preference: "space"} = AutoGrabSettings.load()
    end
  end

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

  describe "put/2 — the one write" do
    test "persists an allowed enum value" do
      assert :ok = AutoGrabSettings.put(:default_max_quality, "hd_1080p")
      assert AutoGrabSettings.load().default_max_quality == "hd_1080p"
    end

    test "persists an integer on its ladder" do
      assert :ok = AutoGrabSettings.put(:pack_min_fit, 80)
      assert :ok = AutoGrabSettings.put(:max_attempts, 3)
      settings = AutoGrabSettings.load()
      assert settings.pack_min_fit == 80
      assert settings.max_attempts == 3
    end

    test "refuses a value outside the enum or off the ladder" do
      assert {:error, :invalid} = AutoGrabSettings.put(:default_mode, "sometimes")
      assert {:error, :invalid} = AutoGrabSettings.put(:pack_min_fit, 77)
      assert {:error, :invalid} = AutoGrabSettings.put(:max_attempts, 0)
      assert {:error, :invalid} = AutoGrabSettings.put(:size_preference, 3)
      assert AutoGrabSettings.load() == %AutoGrabSettings{}
    end

    test "refuses an unknown field" do
      assert {:error, :invalid} = AutoGrabSettings.put(:patience_hours, 24)
    end
  end

  describe "ladders" do
    test "pack fit runs 5–100 by 5; attempts 1–50" do
      assert AutoGrabSettings.pack_fit_ladder() == Enum.to_list(5..100//5)
      assert AutoGrabSettings.attempts_ladder() == Enum.to_list(1..50)
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: FAIL — `floor/0`, `effective_min_quality/1`, `put/2`, ladders undefined.

- [ ] **Step 3: Implement**

In `auto_grab_settings.ex`: remove the two retired keys from `@keys`; remove `default_min_quality` and `patience_hours` from `@builtin_defaults`, `@type t` and `load/0`; replace the three `effective_*` functions with the block below; add the ladders and `put/2`.

```elixir
  @floor "hd_1080p"
  @pack_fit_ladder Enum.to_list(5..100//5)
  @attempts_ladder Enum.to_list(1..50)

  @allowed %{
    default_mode: ~w(all_releases ask off),
    default_max_quality: ~w(uhd_4k hd_1080p),
    size_preference: ~w(fidelity space),
    pack_min_fit: @pack_fit_ladder,
    max_attempts: @attempts_ladder
  }

  @storage_key %{
    default_mode: "auto_grab.default_mode",
    default_max_quality: "auto_grab.default_max_quality",
    size_preference: "auto_grab.size_preference",
    pack_min_fit: "auto_grab.pack_min_fit",
    max_attempts: "auto_grab.max_attempts"
  }

  @doc """
  The automatic floor. Below it a release is taken only under a title's
  own lower-quality acceptance (ADR-063 §2). Fixed, not a setting: the
  policy is "the best available now, then down the ladder" (UIDR-041 §6).
  """
  @spec floor() :: quality()
  def floor, do: @floor

  @doc "A title's effective floor: its lower-quality acceptance when it has one, else `floor/0`."
  @spec effective_min_quality(String.t() | nil) :: quality()
  def effective_min_quality(nil), do: @floor
  def effective_min_quality(value) when is_binary(value), do: value

  @doc "The stepper ladder for `pack_min_fit`: 5–100 in steps of 5."
  @spec pack_fit_ladder() :: [pos_integer()]
  def pack_fit_ladder, do: @pack_fit_ladder

  @doc "The stepper ladder for `max_attempts`: 1–50."
  @spec attempts_ladder() :: [pos_integer()]
  def attempts_ladder, do: @attempts_ladder

  @doc """
  The one write for a global auto-grab default. Refuses a field it does
  not own, an enum value it does not list, or an integer off the ladder.
  """
  @spec put(atom(), term()) :: :ok | {:error, :invalid}
  def put(field, value) when is_map_key(@allowed, field) do
    if value in Map.fetch!(@allowed, field) do
      Settings.find_or_create_entry!(%{key: Map.fetch!(@storage_key, field), value: %{"value" => value}})
      :ok
    else
      {:error, :invalid}
    end
  end

  def put(_field, _value), do: {:error, :invalid}
```

Moduledoc: defaults list reads mode `"all_releases"`, max quality `"uhd_4k"`, max attempts 12, pack fit 75, size preference `"fidelity"`; add "The floor is fixed at 1080p (`floor/0`); there is no patience window. `put/2` is the only writer of the `auto_grab.*` rows."

- [ ] **Step 4: Run to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: PASS (other files warn until A2–A5).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/auto_grab_settings.ex test/media_centaur/acquisition/auto_grab_settings_test.exs
git commit -m "refactor(acquisition): auto-grab settings own their writes; the floor is a constant, patience is gone"
```

### Task A2: `WantSchedule.due?/2`

**Files:**
- Modify: `lib/media_centaur/acquisition/want_schedule.ex`
- Test: `test/media_centaur/acquisition/want_schedule_test.exs`

- [ ] **Step 1: Rewrite the tests.** Delete the `floor_elevated?/3` describe and the last two `due?/3` cases (patience expiry). Every remaining `WantSchedule.due?(want, _hours, now)` becomes `WantSchedule.due?(want, now)`; the describe reads `"due?/2"`.
- [ ] **Step 2: Run** `~/scripts/agents/agent-mix test test/media_centaur/acquisition/want_schedule_test.exs` → FAIL, `due?/2` undefined.
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

Delete `floor_elevated?/3`, `patience_expired_since_last_search?/3`, and the moduledoc's patience paragraph and Q4 sentence.

- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `refactor(acquisition): the want schedule is age bands only`.

### Task A3: `DownloadParams` keeps only the lower-quality acceptance

**Files:**
- Modify: `lib/media_centaur/acquisition/download_params.ex`
- Test: `test/media_centaur/acquisition/title_download_params_test.exs`

- [ ] **Step 1: Rewrite the tests.** Every case that sets or asserts `quality_4k_patience_hours` or `max_quality` becomes the same case on `min_quality: "any"`. The defaults assertion becomes `assert TitleDownloadParams.get(1234, :tv_series) == %DownloadParams{min_quality: nil}`. The validation case becomes `min_quality: "sd"` refused with `%{min_quality: [_ | _]} = errors_on(changeset)`. Add `test "the embedded params carry only the acceptance" do assert DownloadParams.__schema__(:fields) == [:min_quality] end`.
- [ ] **Step 2: Run** → FAIL on the fields assertion.
- [ ] **Step 3: Implement.** `embedded_schema` has one field, `field :min_quality, :string`; `@fields [:min_quality]`; delete `@max_patience_hours`, the two retired type entries and validations. Moduledoc first paragraph: "One title's lower-quality acceptance ([ADR-063] §2): `min_quality` is `"any"` when the title takes the best release that exists, `nil` when it holds to the automatic floor."
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `refactor(acquisition): a title's download params are its lower-quality acceptance only`.

### Task A4: the drop planner plans at the floor immediately

**Files:**
- Modify: `lib/media_centaur/acquisition/drop_planner.ex:170-200, 226, 271, 340-365`
- Test: `test/media_centaur/acquisition/drop_planner_test.exs:236-273`

- [ ] **Step 1: Rewrite the patience test.** The describe `"run_tick/0 — patience quality floors"` becomes `"run_tick/0 — no patience window"` with one case: same stubs and fixtures, **no** `TitleDownloadParams.put`, and the assertions flip: both units commit at 1080p — `assert length(Units.for_pursuit(pursuit.id)) == 2` (or two pursuits, per how the fixture's TV drop groups units; read the neighbouring cases), and `ReleaseTracking.open_wants_for_item(item.id) == []`.
- [ ] **Step 2: Run** → FAIL (compile: `effective_patience_hours/2` undefined).
- [ ] **Step 3: Implement.** In `plan_item/4`: delete the `patience =` binding; `due = Enum.filter(wants, &WantSchedule.due?(&1, now))`; call `plan_tv_drop(item, due, settings, now)` and `plan_movie_drop(item, &1, settings, now)`; drop the `patience` parameter from both heads and clauses. Lines 226 and 271: `min_quality: nil`. Delete `floor_for/5` and its comment. Lines 342–343:

```elixir
      AutoGrabSettings.effective_min_quality(params.min_quality),
      settings.default_max_quality
```

Moduledoc lines 17 and 61: "Every unit is planned at the automatic floor; a title's lower-quality acceptance lowers it."

- [ ] **Step 4: Run** `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs` → PASS.
- [ ] **Step 5: Commit** `refactor(acquisition): the drop planner has no patience window`.

### Task A5: the two remaining readers of the retired floor

**Files:** `lib/media_centaur/acquisition/jobs/pursue_target.ex:193`, `jobs/run_plan.ex:624`; comments at `plans.ex:248`, `plans/plan_unit.ex:70`, `run_plan.ex:161,438`, `pursue_target.ex:184`.

- [ ] **Step 1:** Both reads become `min_quality: Map.get(criteria, "min_quality") || AutoGrabSettings.floor(),`. Each comment naming "the patience elevation" or "Q4" now reads "a per-unit `min_quality` is the title's lower-quality acceptance (ADR-063 §2); nothing else sets one".
- [ ] **Step 2: Run** `~/scripts/agents/agent-mix test` → PASS. (`planner_test.exs` builds prefs literally; unchanged.)
- [ ] **Step 3: Commit** `refactor(acquisition): every automatic path reads the constant floor`.

### Task A6: data migration for the retired rows and keys

**Files:**
- Create: `priv/repo/data_migrations/20260913120000_quality_policy_loses_floor_and_patience.exs`
- Test: `test/media_centaur/data_migrations_test.exs` (append a describe)

- [ ] **Step 1: Test.** Follow the file's existing describes for the insert helpers and column lists (check `settings` and `title_download_params` columns in `priv/repo/migrations` first):

```elixir
  describe "QualityPolicyLosesFloorAndPatience" do
    alias MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatience

    test "deletes the two retired settings rows and strips the retired per-title keys" do
      insert_setting!("auto_grab.default_min_quality", ~s({"value":"hd_1080p"}))
      insert_setting!("auto_grab.4k_patience_hours", ~s({"value":48}))
      insert_setting!("auto_grab.max_attempts", ~s({"value":12}))
      insert_title_params!(1, "movie", ~s({"min_quality":"any","max_quality":"uhd_4k","quality_4k_patience_hours":24}))
      insert_title_params!(2, "movie", ~s({"max_quality":"hd_1080p"}))

      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)
      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)

      assert Repo.query!("SELECT key FROM settings WHERE key LIKE 'auto_grab.%' ORDER BY key").rows == [["auto_grab.max_attempts"]]
      assert Repo.query!("SELECT tmdb_id, params FROM title_download_params ORDER BY tmdb_id").rows == [[1, ~s({"min_quality":"any"})]]
    end
  end
```

with `insert_setting!/2` and `insert_title_params!/3` as private helpers at the bottom of the test file doing raw `Repo.query!` INSERTs with `Ecto.UUID.bingenerate()` ids (or the id type the schema migration uses) and `now()` timestamps.

- [ ] **Step 2: Run** → FAIL, module undefined.
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

- [ ] **Step 4: Run** → PASS. The dev server applies data migrations at boot; do not run it by hand.
- [ ] **Step 5: Commit** `chore(acquisition): data migration retires the quality floor and patience rows`.

### Task A7: the Settings form stops writing the retired keys

- [ ] **Step 1:** Delete the "4K patience (hours)" and "Minimum quality (final fallback)" fields from `acquisition_section.ex:570-610`; in `settings_live.ex:2832-2849` delete the two tuples. Adjust any acquisition test that submitted them.
- [ ] **Step 2:** `~/scripts/agents/agent-mix precommit` → PASS.
- [ ] **Step 3: Wiki.** `Settings-Reference.md`: delete the two bullets (~136–137). `Release-Tracking.md:65`: "Quality is governed by the Auto-acquisition settings: the highest resolution and the within-resolution preference. Below 1080p a release is taken only when the title's own lower-quality acceptance is on."

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: quality policy loses the floor and the patience window" && cd -
```

- [ ] **Step 4: Commit** `feat(settings): auto-acquisition no longer offers a floor or a patience window`.

---

## Phase B — the kit moves to the components tree, with stories (D1, D2, D5, D29–D33)

### Task B1: `MediaCentaurWeb.Components.Settings` with the moved components and their stories

**Files:**
- `git mv lib/media_centaur_web/live/settings_live/components.ex lib/media_centaur_web/components/settings.ex`
- Create: `storybook/settings/_settings.index.exs`, `settings_row.story.exs`, `settings_stepper.story.exs`, `settings_field.story.exs`, `path_status.story.exs`
- Modify: the eight `import MediaCentaurWeb.SettingsLive.Components` lines (`system_settings.ex`, `tmdb.ex`, `library.ex`, `acquisition_section.ex`, `social_section.ex`, `services.ex`, `preferences.ex`, `playback.ex`) → `import MediaCentaurWeb.Components.Settings`

- [ ] **Step 1: Move and rename** the module to `MediaCentaurWeb.Components.Settings`; keep `use MediaCentaurWeb, :html` and the aliases. Moduledoc:

```elixir
  @moduledoc """
  The Settings kit (UIDR-041): the components every Settings section
  composes from. A section is cards of rows. `settings_card/1` is the
  card; `settings_row/1` (toggle), `settings_stepper/1`,
  `settings_choice/1`, `settings_text_row/1` and `settings_select_row/1`
  are the rows, each saving on the act; `settings_list/1` is a
  string-list setting; `settings_field/1` and `settings_input/1` are the
  label/control/help unit and the house input inside a connection row's
  edit form; `settings_disclosure/1` hides rare content; `path_status/1`
  is the glyph beside a path label. The connection row lives in
  `MediaCentaurWeb.Components.Settings.ConnectionRow`.
  """
```

Keep `settings_card_header/1`, `status_dot/1` and `connection_status/1` for now (Phase F retires them). In `settings_row/1` delete the `color` attr and hardcode `toggle-info`; delete `color="info"` from every caller (`preferences.ex`, `services.ex`, `system_settings.ex`). In `settings_stepper/1` add `attr :id, :string, default: nil` (on the outer div), `attr :event_value, :map, default: %{}` (spread with `phx_values/1` on all three buttons), and make the three `aria-label`s `"Decrease #{@label}"`, `"Increase #{@label}"`, `"Reset #{@label}"`.

- [ ] **Step 2: Compile** `~/scripts/agents/agent-mix compile --warnings-as-errors` → clean.

- [ ] **Step 3: Index and four stories**

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
  def entry("settings_list"), do: [icon: {:fa, "list", :thin}, name: "List setting"]
  def entry("settings_field"), do: [icon: {:fa, "rectangle-list", :thin}, name: "Field"]
  def entry("settings_input"), do: [icon: {:fa, "i-cursor", :thin}, name: "Input"]
  def entry("settings_disclosure"), do: [icon: {:fa, "chevron-right", :thin}, name: "Disclosure"]
  def entry("path_status"), do: [icon: {:fa, "circle-check", :thin}, name: "Path status"]
  def entry("connection_row"), do: [icon: {:fa, "plug", :thin}, name: "Connection row"]
end
```

`settings_row.story.exs`:

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

`settings_stepper.story.exs`: variations `:mid` (`value_label: "75%"`, `down_value: 70`, `up_value: 80`, `reset_value: 75`, `at_min: false`, `at_max: false`, `at_default: true`), `:at_min` (`value_label: "5%"`, `at_min: true`, others false), `:at_max` (`"100%"`, `at_max: true`), each with `label: "Season packs"`, `description: "Take a pack only when you want at least this share of its episodes."`, `event: "set_auto_grab"`, `event_value: %{"key" => "pack_min_fit"}`.

`settings_field.story.exs`: `:inline` (`label: "Address"`, `description: "Must be reachable from this machine."`, slot `["<input class=\"input input-bordered font-mono text-sm\" value=\"http://localhost:9696\" />"]`) and `:stacked` (`layout: :stacked`, same slot with `w-full`).

`path_status.story.exs`: `:found` (`path: "/usr/bin/env"`, `kind: :executable`), `:missing` (`path: "/nonexistent/mpv"`, `kind: :executable`).

- [ ] **Step 4: Render** `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/storybook_compile_test.exs` → PASS; open `/storybook/settings/settings_row`.
- [ ] **Step 5: Commit** `refactor(settings): the settings kit moves to the components tree with stories`.

### Task B2: the new kit components and the core ladder

**Files:**
- Create: `lib/media_centaur/settings/ladder.ex`, `test/media_centaur/settings/ladder_test.exs`
- Modify: `lib/media_centaur/settings.ex` (`exports: [Entry, Services, Ladder]`)
- Modify: `lib/media_centaur_web/components/settings.ex`; `assets/css/app.css` (`.release-notes-disclosure` → `.settings-disclosure`), `release_notes.ex`, `system_settings.ex` (class rename)
- Create: `storybook/settings/settings_card.story.exs`, `settings_choice.story.exs`, `settings_text_row.story.exs`, `settings_select_row.story.exs`, `settings_list.story.exs`, `settings_input.story.exs`, `settings_disclosure.story.exs`

- [ ] **Step 1: Ladder test**

```elixir
defmodule MediaCentaur.Settings.LadderTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Settings.Ladder

  @hours [1, 2, 3, 4, 6, 8, 12, 24]

  test "neighbours on a fixed list" do
    assert Ladder.down(@hours, 6) == 4
    assert Ladder.up(@hours, 6) == 8
  end

  test "the ends clamp to themselves" do
    assert Ladder.down(@hours, 1) == 1
    assert Ladder.up(@hours, 24) == 24
  end

  test "a value off the ladder steps from the nearest rung" do
    assert Ladder.down(@hours, 5) == 4
    assert Ladder.up(@hours, 5) == 6
  end

  test "range/3 builds a ladder" do
    assert Ladder.range(5, 100, 5) == Enum.to_list(5..100//5)
  end
end
```

- [ ] **Step 2: Run** → FAIL, then implement

```elixir
defmodule MediaCentaur.Settings.Ladder do
  @moduledoc """
  Neighbours on a fixed list of stepper values (UIDR-041 §2). A stepper
  is a dumb renderer carrying absolute targets; the value's owner picks
  them here. Off-ladder values step from the nearest rung.
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

Add `Ladder` to the Settings boundary exports.

- [ ] **Step 3: Seven stories first** (`use PhoenixStorybook.Story, :component`, `render_source :function`):

- `settings_card`: `:plain` (`title: "Search"`, slot `["<p class=\"text-sm\">body</p>"]`); `:with_description_and_action` (`title: "Download clients"`, `description: "One client per protocol. Prowlarr sends each grab to the client that matches the indexer."`, slots `["<:action><button class=\"btn btn-ghost btn-xs\">Detect from Prowlarr</button></:action>", "<p class=\"text-sm\">rows</p>"]`).
- `settings_choice`: `:two` (`label: "Highest resolution"`, `description: "The best available is taken right away."`, `options: [{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}]`, `selected: "uhd_4k"`, `event: "set_auto_grab"`, `event_value: %{"key" => "default_max_quality"}`); `:three` (`label: "When a release appears"`, `options: [{"all_releases", "Grab it"}, {"ask", "Ask first"}, {"off", "Notify only"}]`, `selected: "ask"`, `event: "set_auto_grab"`).
- `settings_text_row`: `:path` (`label: "Data directory"`, `description: "Where cached posters and backdrops are stored."`, `name: "data_dir"`, `value: "/home/sample/.local/share/media-centaur"`, `placeholder: "/path"`, `event: "save_data_dir"`, `mono: true`).
- `settings_select_row`: `:languages` (`label: "Preferred audio"`, `description: "Which audio track plays first."`, `name: "audio"`, `options: [{"original", "Original language"}, {"understood", "A language you understand"}, {"any", "Any"}]`, `selected: "original"`, `event: "set_language_policy"`).
- `settings_list`: `:items` (`items: ["Extras", "Featurettes"]`, `remove_event: "config_list_remove"`, `add_event: "config_list_add"`, `event_value: %{"key" => "extras_dirs"}`, `placeholder: "Folder name"`, `add_label: "Add"`); `:empty_with_error` (`items: []`, `error: "That path is inside a media directory."`, `mono: true`, `placeholder: "/path"`).
- `settings_input`: `:text` (`name: "prowlarr_url"`, `value: "http://localhost:9696"`, `mono: true`); `:password` (`type: "password"`, `name: "prowlarr_api_key"`, `placeholder: "Leave blank to keep the current key"`, `mono: true`).
- `settings_disclosure`: `:closed` (`label: "Secret key"`, slot `["<p class=\"text-xs\">hidden until opened</p>"]`); `:open` (`open: true`).

- [ ] **Step 4: Run** the compile test → FAIL, then implement the seven components:

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

  attr :type, :string, default: "text"
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :mono, :boolean, default: false
  attr :autofocus, :boolean, default: false, doc: "focus on mount — the first field of an edit form."
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete phx-blur phx-keydown phx-key phx-value-name min max step)

  @doc "The house text input (UIDR-041 §31): bordered, full width, monospace for paths and keys, a nav item."
  def settings_input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      phx-mounted={@autofocus && JS.focus()}
      class={["input input-bordered w-full text-sm", @mono && "font-mono", @class]}
      data-nav-item
      tabindex="0"
      {@rest}
    />
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :event, :string, required: true, doc: "pushed with `%{\"name\" => name, \"value\" => typed}` on Enter and on blur."
  attr :mono, :boolean, default: false
  attr :id, :string, default: nil
  slot :label_suffix, doc: "a glyph beside the label, e.g. `path_status`."

  @doc "A free-text setting that commits on Enter or blur (UIDR-041 §2, §30). One payload shape, no form."
  def settings_text_row(assigns) do
    ~H"""
    <div id={@id} class="py-2.5 px-3.5 space-y-1.5">
      <div class="flex items-center gap-1.5">
        <span class="font-medium">{@label}</span>
        {render_slot(@label_suffix)}
      </div>
      <p :if={@description} class="text-xs text-base-content/55">{@description}</p>
      <.settings_input
        name={@name}
        value={@value}
        placeholder={@placeholder}
        mono={@mono}
        phx-blur={@event}
        phx-keydown={@event}
        phx-key="Enter"
        phx-value-name={@name}
      />
    </div>
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

  attr :id, :string, default: nil
  attr :items, :list, required: true, doc: "the current entries, strings."
  attr :remove_event, :string, required: true, doc: "pushed with `phx-value-item` = the entry, plus `event_value`."
  attr :add_event, :string, required: true, doc: "the inline form's submit; the input is named `item`."
  attr :event_value, :map, default: %{}, doc: "extra `phx-value-*` on Remove and hidden inputs on the add form, e.g. the config key."
  attr :placeholder, :string, default: nil
  attr :add_label, :string, default: "Add"
  attr :mono, :boolean, default: false
  attr :error, :string, default: nil

  @doc "A string-list setting (UIDR-041 §32): one row per entry with Remove, an inline input with Add, an optional error line."
  def settings_list(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <ul :if={@items != []} class="space-y-2">
        <li :for={item <- @items} class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2">
          <span class={["min-w-0 flex-1 truncate text-sm", @mono && "font-mono"]} title={item}>{item}</span>
          <.button variant="dismiss" size="xs" class="shrink-0" phx-click={@remove_event} phx-value-item={item} {phx_values(@event_value)} data-nav-item tabindex="0">
            Remove
          </.button>
        </li>
      </ul>
      <form phx-submit={@add_event} class="flex items-center gap-2">
        <input :for={{key, value} <- @event_value} type="hidden" name={key} value={value} />
        <.settings_input name="item" placeholder={@placeholder} mono={@mono} autocomplete="off" class="min-w-0 flex-1" />
        <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">{@add_label}</.button>
      </form>
      <p :if={@error} class="text-xs text-error">{@error}</p>
    </div>
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

`settings_field/1` gains `attr :class, :string, default: nil` on its outer div. `alias Phoenix.LiveView.JS` at the top. Rename the CSS class (four rules near `app.css:2907`) and its two users; `~/scripts/agents/agent-mix assets.build`.

- [ ] **Step 5: Render** → PASS; check `/storybook/settings/settings_choice` shows the lifted segment and `/storybook/settings/settings_list` the add form.
- [ ] **Step 6: Commit** `feat(settings): card, choice, text, select, list, input and disclosure join the kit; ladders in core`.

### Task B3: the shell renders the section intro (D1)

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex` (`@sections`, `render/1`); section modules whose only `h2` is the section title: `preferences.ex`, `services.ex`, `import_section.ex`, `playback.ex`, `maintenance_section.ex`, `danger.ex`, `controls.ex` (Acquisition, TMDB, Social, Language keep theirs until their own tasks)
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

- [ ] **Step 2: Run** → FAIL, `sections/0` undefined.
- [ ] **Step 3: Implement.** Descriptions per id:

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

`@doc false def sections, do: @sections`. In `render/1`, wrap intro + content in a `space-y-4` div, the intro being:

```heex
<div class="min-w-0 mb-1">
  <h2 class="text-lg font-semibold">{section_meta(@active_section).label}</h2>
  <p class="text-sm text-base-content/55 mt-0.5">{section_meta(@active_section).description}</p>
</div>
```

with `defp section_meta(id), do: Enum.find(@sections, &(&1.id == id))`. Delete the seven section-level `h2` blocks; the Danger card keeps its triangle beside its first action row.

- [ ] **Step 4: Run** the settings + smoke suites → PASS; `~/scripts/agents/agent-mix precommit` → PASS.
- [ ] **Step 5: Commit** `feat(settings): the shell renders every section's intro`.

---

## Phase C — one owner of connection state (D22–D25)

### Task C1: four ids, `configured?` from Capabilities, a per-slot verifier

**Files:**
- Modify: `lib/media_centaur/integration_health.ex`, `integration_health/status.ex`, `integration_health/verifier.ex`, `lib/media_centaur/downloads.ex` (remove `config_key?/1` and its `@config_keys` if nothing else reads it)
- Test: `test/media_centaur/integration_health_test.exs`

- [ ] **Step 1: Tests.** Replace the "two-slot" describe with:

```elixir
  describe "the four ids are the Capabilities subjects" do
    test "known/0 lists them in UI order" do
      assert IntegrationHealth.known() == [:tmdb, :prowlarr, :download_client, :usenet_download_client]
    end

    test "each slot's configured? is its own" do
      config = :persistent_term.get({Config, :config})

      :persistent_term.put(
        {Config, :config},
        config
        |> Map.put(:download_client_type, nil)
        |> Map.put(:download_client_url, nil)
        |> Map.put(:usenet_download_client_type, "sabnzbd")
        |> Map.put(:usenet_download_client_url, "http://localhost:8080")
      )

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert %Status{id: :download_client, configured?: false} = IntegrationHealth.status(:download_client)
      assert %Status{id: :usenet_download_client, configured?: true} = IntegrationHealth.status(:usenet_download_client)
    end

    test "a usenet key change flips only the usenet slot" do
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      Config.update(:usenet_download_client_url, "http://sab:8085")

      assert_receive {:integration_health_changed, %Status{id: :usenet_download_client}}
      refute_receive {:integration_health_changed, %Status{id: :download_client}}, 100
    end
  end
```

Add a Verifier test file `test/media_centaur/integration_health/verifier_test.exs` asserting `run(:download_client)` and `run(:usenet_download_client)` return `{:error, :not_configured}` with no slot configured (pure, no network).

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** `@integrations [:tmdb, :prowlarr, :download_client, :usenet_download_client]`; `Status.@type id` the same four; `configured_for?(id)` is `Capabilities.configured?(id)` for every id (delete the Downloads clause and the `Downloads` alias/dep if unused); `@config_keys` gains `download_client: [:download_client_type, :download_client_url, :download_client_username, :download_client_password]` and `usenet_download_client: [:usenet_download_client_type, :usenet_download_client_url, :usenet_download_client_api_key]`; `integration_for_key/1` is `Enum.find(@integrations, fn id -> key in Map.fetch!(@config_keys, id) end)`. `all_statuses/0`'s fallback becomes `unknown(id, Capabilities.configured?(id))`. Verifier:

```elixir
  def run(:download_client), do: run_slot(:torrent)
  def run(:usenet_download_client), do: run_slot(:usenet)

  defp run_slot(protocol) do
    case Dispatcher.driver_for(protocol) do
      {:ok, {config, module}} -> module.test_connection(config)
      {:error, _none} -> {:error, :not_configured}
    end
  end
```

Delete `Downloads.config_key?/1` and its `@config_keys` if the grep shows no other reader. Update the moduledocs (four ids; the two-slot paragraph goes).

- [ ] **Step 4: Run** `~/scripts/agents/agent-mix test test/media_centaur/integration_health_test.exs test/media_centaur/integration_health test/media_centaur_web/live/setup_live_test.exs` → PASS.
- [ ] **Step 5: Commit** `refactor(integration-health): four ids, one per Capabilities subject`.

### Task C2: an explicit verify persists; boot seeds from the persisted test; a config change means not tested

**Files:**
- Modify: `lib/media_centaur/integration_health.ex`
- Test: `test/media_centaur/integration_health_test.exs`, `test/media_centaur/setup/gate_test.exs` (if a `:pending`-at-boot case exists)

- [ ] **Step 1: Tests**

```elixir
  describe "verify/1 persists for readiness" do
    test "an :ok result is saved through Capabilities" do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      IntegrationHealth.verify(:prowlarr)
      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :pending}}
      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :ok}}

      assert %{status: :ok} = MediaCentaur.Capabilities.load_test_result(:prowlarr)
    end

    test "an error result is saved too" do
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      Config.update(:tmdb_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      IntegrationHealth.verify(:tmdb)
      assert_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :error}}
      assert %{status: :error} = MediaCentaur.Capabilities.load_test_result(:tmdb)
    end
  end

  describe "boot" do
    test "seeds from the persisted test and probes nothing" do
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      Config.update(:tmdb_api_key, "k")
      %{tested_at: tested_at} = MediaCentaur.Capabilities.save_test_result(:tmdb, :ok)

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert %Status{test_state: :ok, last_tested_at: ^tested_at} = IntegrationHealth.status(:tmdb)
      refute_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :pending}}, 100
    end

    test "an integration with no persisted test is :unknown" do
      Config.update(:tmdb_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      assert %Status{configured?: true, test_state: :unknown} = IntegrationHealth.status(:tmdb)
    end
  end

  describe "a config change" do
    test "resets the integration to :unknown, not :pending" do
      Config.update(:tmdb_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      Config.update(:tmdb_api_key, "k2")
      assert_receive {:integration_health_changed, %Status{id: :tmdb, configured?: true, test_state: :unknown}}
    end
  end
```

Delete the old "transitions :unknown → :pending → :ok" expectations that relied on the boot probe (the happy-path describe's first case seeds via configured + boot kick; re-point it at `verify/1`). Check `drain_initial_seed_broadcasts/0`: with no boot probes it drains at most one broadcast per id, or none; adjust it to drain with a short timeout.

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** `handle_continue(:seed, _)`: for each id, `write(id, seeded(id))` with

```elixir
  defp seeded(id) do
    configured? = configured_for?(id)

    case Capabilities.load_test_result(id) do
      %{status: status, tested_at: tested_at} when configured? ->
        %Status{id: id, configured?: true, test_state: status, last_tested_at: tested_at}

      _none ->
        %Status{id: id, configured?: configured?, test_state: :unknown}
    end
  end
```

and no `kick_test`. In `handle_info({:config_updated, ...})` write `test_state: :unknown` regardless. In `apply_test_result/2`, after the ETS write and before `broadcast/1`: `Capabilities.save_test_result(id, :ok)` / `(id, :error)`. Moduledoc: the lifecycle section reads "On boot: seed each id from `Capabilities.configured?/1` and the persisted test; nothing is probed. On a tracked config change: `configured?` follows, `test_state` becomes `:unknown`. On `verify/1`: `:pending`, the test on `Task.Supervisor`, then the result written, persisted through `Capabilities.save_test_result/2`, and broadcast." The Gate's `:pending` comment ("most often observed at boot") becomes "a verify in flight".

- [ ] **Step 4: Run** the integration-health, setup and capabilities suites → PASS. `~/scripts/agents/agent-mix precommit` → PASS.
- [ ] **Step 5: Commit** `feat(integration-health): an explicit verify persists; boot seeds from the persisted test`.

---

## Phase D — Acquisition and TMDB on connection rows (D6–D19, D21, D26–D28)

### Task D1: `ConnectionState` (pure struct)

**Files:**
- Create: `lib/media_centaur_web/live/settings_live/connection_state.ex`
- Test: `test/media_centaur_web/live/settings_live/connection_state_test.exs`

- [ ] **Step 1: Test**

```elixir
defmodule MediaCentaurWeb.SettingsLive.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.IntegrationHealth.Status
  alias MediaCentaurWeb.SettingsLive.ConnectionState

  @tested ~U[2026-09-13 10:00:00Z]

  defp status(id, configured?, test_state, opts \\ []) do
    %Status{id: id, configured?: configured?, test_state: test_state, last_tested_at: opts[:tested_at]}
  end

  test "not configured" do
    row = ConnectionState.build(status(:prowlarr, false, :unknown), %{}, nil)
    assert %ConnectionState{id: :prowlarr, state: :not_configured, state_label: "Not configured", address: nil, tested_at: nil} = row
  end

  test "configured, not tested" do
    row = ConnectionState.build(status(:prowlarr, true, :unknown), %{prowlarr_url: "http://localhost:9696", prowlarr_api_key_configured?: true}, nil)
    assert %ConnectionState{state: :not_tested, state_label: "Not tested", address: "http://localhost:9696", credential: "API key set"} = row
  end

  test "pending, ok and error follow the owner's test_state and words" do
    assert %{state: :pending, state_label: "Testing…"} = ConnectionState.build(status(:tmdb, true, :pending), %{}, nil)

    assert %{state: :ok, state_label: "Connected", tested_at: @tested} =
             ConnectionState.build(status(:prowlarr, true, :ok, tested_at: @tested), %{}, nil)

    assert %{state: :error, state_label: "Unreachable"} = ConnectionState.build(status(:prowlarr, true, :error), %{}, nil)
    assert %{state_label: "Unreachable or auth failed"} = ConnectionState.build(status(:download_client, true, :error), %{}, nil)
    assert %{state_label: "Unreachable or bad API key"} = ConnectionState.build(status(:usenet_download_client, true, :error), %{}, nil)
  end

  test "a pending detection overrides the state and prefills the form" do
    detected = %{type: "qbittorrent", url: "http://qbittorrent:8080", username: "admin"}
    row = ConnectionState.build(status(:download_client, false, :unknown), %{}, detected)
    assert %{state: :detected, state_label: "Detected from Prowlarr, not saved", address: "http://qbittorrent:8080", prefill: ^detected} = row
  end

  test "credential summary names what is stored, never the value" do
    build = &ConnectionState.build(status(&1, true, :unknown), &2, nil).credential
    assert build.(:tmdb, %{tmdb_api_key_configured?: true}) == "API key set"
    assert build.(:prowlarr, %{prowlarr_api_key_configured?: false}) == nil
    assert build.(:download_client, %{download_client_username: "admin", download_client_password_configured?: true}) == "admin · password set"
    assert build.(:download_client, %{download_client_username: nil, download_client_password_configured?: true}) == "password set"
    assert build.(:usenet_download_client, %{usenet_download_client_api_key_configured?: true}) == "API key set"
  end
end
```

- [ ] **Step 2: Run** → FAIL, then implement

```elixir
defmodule MediaCentaurWeb.SettingsLive.ConnectionState do
  @moduledoc """
  What a connection row shows for one integration (UIDR-041 §1, §7):
  the owner's `%IntegrationHealth.Status{}` projected with the config
  map's address and credential presence, and a pending detection when
  Detect from Prowlarr found values that are not saved. Pure; the row
  component draws it, `SettingsLive` builds it.
  """

  alias MediaCentaur.IntegrationHealth.Status

  @type state :: :not_configured | :not_tested | :pending | :ok | :error | :detected

  @type t :: %__MODULE__{
          id: Status.id(),
          state: state(),
          state_label: String.t(),
          tested_at: DateTime.t() | nil,
          address: String.t() | nil,
          credential: String.t() | nil,
          prefill: map()
        }

  @enforce_keys [:id, :state, :state_label]
  defstruct [:id, :state, :state_label, :tested_at, :address, :credential, prefill: %{}]

  @spec build(Status.t(), map(), map() | nil) :: t()
  def build(%Status{id: id} = status, config, nil) do
    state = state(status)

    %__MODULE__{
      id: id,
      state: state,
      state_label: label(id, state),
      tested_at: if(state in [:ok, :error], do: status.last_tested_at),
      address: address(id, config),
      credential: credential(id, config)
    }
  end

  def build(%Status{id: id}, _config, detected) when is_map(detected) do
    %__MODULE__{
      id: id,
      state: :detected,
      state_label: "Detected from Prowlarr, not saved",
      address: detected[:url],
      prefill: detected
    }
  end

  defp state(%Status{configured?: false}), do: :not_configured
  defp state(%Status{test_state: :unknown}), do: :not_tested
  defp state(%Status{test_state: state}), do: state

  defp label(_id, :not_configured), do: "Not configured"
  defp label(_id, :not_tested), do: "Not tested"
  defp label(_id, :pending), do: "Testing…"
  defp label(_id, :ok), do: "Connected"
  defp label(:download_client, :error), do: "Unreachable or auth failed"
  defp label(:usenet_download_client, :error), do: "Unreachable or bad API key"
  defp label(_id, :error), do: "Unreachable"

  defp address(:tmdb, _config), do: nil
  defp address(:prowlarr, config), do: config[:prowlarr_url]
  defp address(:download_client, config), do: config[:download_client_url]
  defp address(:usenet_download_client, config), do: config[:usenet_download_client_url]

  defp credential(:tmdb, config), do: if(config[:tmdb_api_key_configured?], do: "API key set")
  defp credential(:prowlarr, config), do: if(config[:prowlarr_api_key_configured?], do: "API key set")
  defp credential(:usenet_download_client, config), do: if(config[:usenet_download_client_api_key_configured?], do: "API key set")

  defp credential(:download_client, config) do
    [present(config[:download_client_username]), if(config[:download_client_password_configured?], do: "password set")]
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

- [ ] **Step 3: Run** → PASS; commit `feat(settings): the connection state a row shows, as a struct`.

### Task D2: `connection_row/1` with its story

**Files:**
- Create: `lib/media_centaur_web/components/settings/connection_row.ex`, `storybook/settings/connection_row.story.exs`

- [ ] **Step 1: Story first** — variations:

| id | attributes |
|---|---|
| `:connected` | `id: "connection-prowlarr"`, `name: "Prowlarr"`, `state: :ok`, `state_label: "Connected"`, `tested_at: ~U[2026-05-18 09:00:00Z]`, `address: "http://localhost:9696"`, `detail: "API key set"`, actions slot: `<button class="btn btn-soft btn-xs">Test</button><button class="btn btn-ghost btn-xs">Edit</button>` |
| `:connected_client` | `name: "qBittorrent"`, `kind: "torrent"`, `state: :ok`, `address: "http://localhost:8080"`, `detail: "admin · password set"`, same actions |
| `:pending` | `name: "Prowlarr"`, `state: :pending`, `state_label: "Testing…"`, `address`, `detail: "API key set"` |
| `:unreachable` | `name: "SABnzbd"`, `kind: "usenet"`, `state: :error`, `state_label: "Unreachable or bad API key"`, `tested_at`, `address`, `detail: "API key set"` |
| `:not_tested` | `state: :not_tested`, `state_label: "Not tested"` |
| `:not_configured` | `name: "Usenet client"`, `state: :not_configured`, `state_label: "Not configured"`, `detail: "SABnzbd. Repairs and unpacks; the finished file imports like any other download."`, actions: `<button class="btn btn-soft btn-primary text-base-content btn-xs">Set up</button>` |
| `:detected` | `name: "qBittorrent"`, `kind: "torrent"`, `state: :detected`, `state_label: "Detected from Prowlarr, not saved"`, `address: "http://qbittorrent:8080"`, actions Review · Dismiss |
| `:editing` | `state: :ok`, `editing: true`, `edit` slot with two `settings_field`s and a footer of Cancel / Save and test / Save |
| `:relay` | `name: "wss://relay.example"`, `monospace_name: true`, `state: :ok`, `state_label: "Synced"`, actions Remove |
| `:relay_rejected` | `state: :error`, `state_label: "Rejected"`, `detail: "auth-required: this relay requires authentication"` |

- [ ] **Step 2: Compile test → FAIL, then implement**

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
  attr :state, :atom, required: true, values: [:not_configured, :not_tested, :pending, :ok, :error, :detected]
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
            <a :if={@address} href={@address} target="_blank" rel="noopener"
              class="font-mono truncate inline-flex items-center gap-1 hover:text-base-content" data-nav-item tabindex="0">
              {@address} <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
            </a>
            <span :if={@address && @detail}>·</span>
            <span :if={@detail} class="truncate" title={@detail}>{@detail}</span>
          </div>
        </div>
        <div class={["text-sm shrink-0 text-right inline-flex items-center gap-2", state_text_class(@state)]}>
          <span :if={@state == :pending} class="loading loading-spinner loading-xs"></span>
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
  defp dot_class(:not_configured), do: "bg-base-content/20"
  defp dot_class(_neutral), do: "bg-base-content/30"

  defp state_text_class(:not_configured), do: "text-base-content/55"
  defp state_text_class(_state), do: "text-base-content/70"
end
```

- [ ] **Step 3: Render → PASS; commit** `feat(settings): the connection row`.

### Task D3: `Capabilities.clear_integration/1`

**Files:** `lib/media_centaur/capabilities.ex`, `test/media_centaur/capabilities_test.exs`

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

- [ ] **Step 2: Implement**

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

- [ ] **Step 3: Pass; commit** `feat(capabilities): clear an integration's slot`.

### Task D4: `SettingsLive` reads the owner and loses its test machinery

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex`

- [ ] **Step 1: Mount.** `IntegrationHealth.subscribe()` under `connected?`. Assign `connections: IntegrationHealth.all_statuses()`, `editing: nil`, `auto_grab: AutoGrabSettings.load()`. Delete the assigns `tmdb_test`, `prowlarr_test`, `download_client_test`, `usenet_client_test`, `tmdb_testing`, `prowlarr_testing`, `download_client_testing`, `usenet_client_testing` everywhere (mount, `load_*` at ~322, render, section_content).

- [ ] **Step 2: Owner broadcasts**

```elixir
  def handle_info({:integration_health_changed, %IntegrationHealth.Status{} = status}, socket) do
    editing =
      if status.test_state == :ok and socket.assigns.editing == status.id,
        do: nil,
        else: socket.assigns.editing

    {:noreply,
     socket
     |> assign(connections: Map.put(socket.assigns.connections, status.id, status))
     |> assign(editing: editing)}
  end
```

- [ ] **Step 3: Events.** Delete `save_tmdb`, `save_prowlarr`, `save_download_client`, `save_usenet_client`, the four `handle_async(:*_test_result, ...)` clauses, `start_async_test/3`, `load_test_result/1`, `save_test_result/2`, `persist_auto_grab_defaults/1`, `coerce/2`, `save_auto_grab_defaults`, `save_release_tracking`. Add:

```elixir
  @connections [:tmdb, :prowlarr, :download_client, :usenet_download_client]

  defp connection_id(id) when id in ~w(tmdb prowlarr download_client usenet_download_client),
    do: String.to_existing_atom(id)

  def handle_event("edit_connection", %{"connection" => id}, socket),
    do: {:noreply, assign(socket, editing: connection_id(id))}

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("test_connection", %{"connection" => id}, socket) do
    IntegrationHealth.verify(connection_id(id))
    {:noreply, socket}
  end

  # Save and Save-and-test share one submit: `_action` says which. A save
  # that changed anything clears the persisted test (Capabilities) and the
  # owner resets the row to Not tested on the config broadcast; a test then
  # verifies through the owner and the form stays open until :ok lands
  # (handle_info above) — a failed test keeps the typed values in view.
  def handle_event("save_connection", %{"connection" => id, "_action" => action} = params, socket) do
    subject = connection_id(id)
    changed? = Capabilities.save_integration(subject, params)
    socket = socket |> after_save(subject, changed?) |> assign(config: load_config())

    case action do
      "test" ->
        IntegrationHealth.verify(subject)
        {:noreply, socket}

      _save ->
        {:noreply, socket |> assign(editing: nil) |> put_flash(:info, "#{connection_name(subject)} saved")}
    end
  end

  def handle_event("remove_client", %{"connection" => id}, socket) when id in ~w(download_client usenet_download_client) do
    subject = connection_id(id)
    Capabilities.clear_integration(subject)

    {:noreply,
     socket
     |> after_save(subject, true)
     |> assign(editing: nil, config: load_config())
     |> put_flash(:info, "#{connection_name(subject)} removed")}
  end

  def handle_event("review_detected", %{"connection" => id}, socket),
    do: {:noreply, assign(socket, editing: connection_id(id))}

  def handle_event("dismiss_detected", %{"connection" => "download_client"}, socket),
    do: {:noreply, assign(socket, detected_download_client: nil)}

  def handle_event("dismiss_detected", %{"connection" => "usenet_download_client"}, socket),
    do: {:noreply, assign(socket, detected_usenet_client: nil)}

  def handle_event("set_auto_grab", %{"key" => key, "choice" => raw}, socket) do
    if Capabilities.prowlarr_ready?() do
      field = String.to_existing_atom(key)
      value = if field in [:pack_min_fit, :max_attempts], do: parse_int(raw), else: raw

      case AutoGrabSettings.put(field, value) do
        :ok -> {:noreply, assign(socket, auto_grab: AutoGrabSettings.load())}
        {:error, :invalid} -> {:noreply, socket}
      end
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

  @refresh_hours_ladder [1, 2, 3, 4, 6, 8, 12, 24]

  def handle_event("set_release_tracking_interval", %{"choice" => raw}, socket) do
    case parse_int(raw) do
      hours when hours in @refresh_hours_ladder ->
        Config.update(:release_tracking_refresh_interval_hours, hours)
        {:noreply, assign(socket, config: load_config())}

      _off_ladder ->
        {:noreply, socket}
    end
  end

  # What a save of one integration also does, beyond the write.
  defp after_save(socket, :tmdb, true) do
    # A fresh key may unblock files stranded by an earlier TMDB auth
    # failure; give the pipeline another pass at them.
    MediaCentaur.Watcher.Rescan.rescan_unlinked_async()
    socket
  end

  defp after_save(socket, :download_client, _changed?),
    do: assign(socket, detected_download_client: nil, download_client_detect_status: nil)

  defp after_save(socket, :usenet_download_client, _changed?), do: assign(socket, detected_usenet_client: nil)
  defp after_save(socket, _subject, _changed?), do: socket

  defp connection_name(:tmdb), do: "TMDB"
  defp connection_name(:prowlarr), do: "Prowlarr"
  defp connection_name(:download_client), do: "Torrent client"
  defp connection_name(:usenet_download_client), do: "Usenet client"

  defp parse_int(raw) when is_integer(raw), do: raw

  defp parse_int(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> n
      _ -> nil
    end
  end
```

`String.to_existing_atom/1` on `key` is safe: the `@allowed` map in `AutoGrabSettings` refuses anything not its own, and the atoms exist because that module names them. In `render/1` add `phx-window-keydown={@editing && "cancel_edit"} phx-key="Escape"` on the page root div. In `section_content("acquisition")` and `("tmdb")` build rows:

```elixir
  defp connection_row(socket_assigns, id, detected \\ nil) do
    ConnectionState.build(Map.fetch!(socket_assigns.connections, id), socket_assigns.config, detected)
  end
```

and pass `rows: %{prowlarr: connection_row(assigns, :prowlarr), download_client: connection_row(assigns, :download_client, assigns[:detected_download_client]), usenet_download_client: connection_row(assigns, :usenet_download_client, assigns[:detected_usenet_client])}`, `editing: @editing`, `prowlarr_configured: Capabilities.configured?(:prowlarr)`, `prowlarr_ready: Capabilities.prowlarr_ready?()`, `auto_grab: @auto_grab`, `planning_mode`, `download_client_detecting`, `config`. TMDB gets `row: connection_row(assigns, :tmdb)` and `editing: @editing == :tmdb`. `handle_info` for `{:download_client_detect_result, ...}` is unchanged (it fills `detected_*`).

- [ ] **Step 4: Compile** → clean apart from the section modules, which D5/D6 rewrite.

### Task D5: the Acquisition section on the kit

**Files:** `lib/media_centaur_web/live/settings_live/acquisition_section.ex` (rewrite)

- [ ] **Step 1: Rewrite**

```elixir
defmodule MediaCentaurWeb.SettingsLive.AcquisitionSection do
  @moduledoc """
  The Acquisition section of the Settings page (UIDR-041): five cards.
  Search holds the Prowlarr connection row; Download clients the torrent
  and usenet rows with Detect from Prowlarr on the card; Download button
  and Auto-acquisition are gated on Prowlarr's readiness and say so while
  they wait; Release tracking is one stepper. Each row is a
  `ConnectionState` built by `SettingsLive`, which owns `editing` and
  hosts every event this module names. `integration_row/1` is public
  because the TMDB section renders the same row.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Settings.Ladder
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.SettingsLive.ConnectionState

  @refresh_hours [1, 2, 3, 4, 6, 8, 12, 24]

  attr :config, :map, required: true
  attr :editing, :atom, default: nil
  attr :rows, :map, required: true, doc: "`%{id => ConnectionState.t()}` for prowlarr, download_client, usenet_download_client."
  attr :prowlarr_configured, :boolean, required: true
  attr :prowlarr_ready, :boolean, required: true
  attr :download_client_detecting, :boolean, required: true
  attr :auto_grab, AutoGrabSettings, required: true
  attr :planning_mode, :atom, required: true, values: [:manually_select_release, :auto_select_best_release]

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.settings_card title="Search">
        <ul>
          <.integration_row
            row={@rows.prowlarr}
            name="Prowlarr"
            editing={@editing == :prowlarr}
            description="Searches your indexers and forwards each grab to a download client."
          >
            <:form>
              <.settings_field label="Address" layout={:stacked}>
                <.settings_input name="prowlarr_url" value={@config[:prowlarr_url]} placeholder="http://localhost:9696" mono autofocus />
              </.settings_field>
              <.settings_field label="API key" description="Prowlarr → Settings → General → Security → API Key." layout={:stacked}>
                <.settings_input type="password" name="prowlarr_api_key" autocomplete="off" mono
                  placeholder={secret_placeholder(@config[:prowlarr_api_key_configured?], "key")} />
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
            row={@rows.download_client}
            name={if @rows.download_client.state == :not_configured, do: "Torrent client", else: "qBittorrent"}
            kind="torrent"
            editing={@editing == :download_client}
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
                  <.settings_input name="download_client_url" value={@rows.download_client.prefill[:url] || @config[:download_client_url]}
                    placeholder="http://localhost:8080" mono autofocus />
                </.settings_field>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <.settings_field label="Username" layout={:stacked}>
                  <.settings_input name="download_client_username" value={@rows.download_client.prefill[:username] || @config[:download_client_username]}
                    placeholder="admin" autocomplete="off" mono />
                </.settings_field>
                <.settings_field label="Password" layout={:stacked}>
                  <.settings_input type="password" name="download_client_password" autocomplete="off" mono
                    placeholder={secret_placeholder(@config[:download_client_password_configured?], "password")} />
                </.settings_field>
              </div>
            </:form>
          </.integration_row>

          <.integration_row
            row={@rows.usenet_download_client}
            name={if @rows.usenet_download_client.state == :not_configured, do: "Usenet client", else: "SABnzbd"}
            kind="usenet"
            editing={@editing == :usenet_download_client}
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
                  <.settings_input name="usenet_download_client_url" value={@rows.usenet_download_client.prefill[:url] || @config[:usenet_download_client_url]}
                    placeholder="http://localhost:8085" mono autofocus />
                </.settings_field>
              </div>
              <.settings_field label="API key" description="SABnzbd → Config → General → API Key." layout={:stacked}>
                <.settings_input type="password" name="usenet_download_client_api_key" autocomplete="off" mono
                  placeholder={secret_placeholder(@config[:usenet_download_client_api_key_configured?], "key")} />
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
            down_value={Ladder.down(AutoGrabSettings.pack_fit_ladder(), @auto_grab.pack_min_fit)}
            up_value={Ladder.up(AutoGrabSettings.pack_fit_ladder(), @auto_grab.pack_min_fit)}
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
            down_value={Ladder.down(AutoGrabSettings.attempts_ladder(), @auto_grab.max_attempts)}
            up_value={Ladder.up(AutoGrabSettings.attempts_ladder(), @auto_grab.max_attempts)}
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

  attr :row, ConnectionState, required: true
  attr :name, :string, required: true
  attr :kind, :string, default: nil
  attr :editing, :boolean, required: true
  attr :removable, :boolean, default: false
  attr :description, :string, required: true, doc: "shown on the detail line while nothing is configured."
  slot :form, required: true

  @doc "A connection row for one integration: the readout's actions per state and the edit form with its footer."
  def integration_row(assigns) do
    assigns = assign(assigns, :id, Atom.to_string(assigns.row.id))

    ~H"""
    <.connection_row
      id={"connection-#{@id}"}
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
            <.button id={"connection-#{@id}-setup"} variant="secondary" size="xs" phx-click="edit_connection" phx-value-connection={@id} data-nav-item tabindex="0">
              Set up
            </.button>
          <% :detected -> %>
            <.button id={"connection-#{@id}-review"} variant="secondary" size="xs" phx-click="review_detected" phx-value-connection={@id} data-nav-item tabindex="0">
              Review
            </.button>
            <.button id={"connection-#{@id}-dismiss"} variant="dismiss" size="xs" phx-click="dismiss_detected" phx-value-connection={@id} data-nav-item tabindex="0">
              Dismiss
            </.button>
          <% _configured -> %>
            <.button id={"connection-#{@id}-test"} variant="neutral" size="xs" phx-click="test_connection" phx-value-connection={@id} disabled={@row.state == :pending} data-nav-item tabindex="0">
              <.icon name="hero-signal-mini" class="size-3.5" /> Test
            </.button>
            <.button id={"connection-#{@id}-edit"} variant="dismiss" size="xs" phx-click="edit_connection" phx-value-connection={@id} data-nav-item tabindex="0">
              Edit
            </.button>
        <% end %>
      </:actions>
      <:edit>
        <form id={"connection-#{@id}-form"} phx-submit="save_connection" class="space-y-4">
          <input type="hidden" name="connection" value={@id} />
          {render_slot(@form)}
          <div class="flex items-center justify-between gap-3 pt-1">
            <div>
              <.button :if={@removable} id={"connection-#{@id}-remove"} variant="destructive_inline" size="sm" type="button" phx-click="remove_client" phx-value-connection={@id} data-nav-item tabindex="0">
                Remove client
              </.button>
            </div>
            <div class="flex items-center gap-2">
              <.button id={"connection-#{@id}-cancel"} variant="dismiss" size="sm" type="button" phx-click="cancel_edit" data-nav-item tabindex="0">Cancel</.button>
              <.button type="submit" variant="neutral" size="sm" name="_action" value="test" disabled={@row.state == :pending} data-nav-item tabindex="0">
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
end
```

`integration_row/1` lives under `live/`, so MC0009 does not require a story; its states are the connection row's.

- [ ] **Step 2: Compile** → clean once D6 is done too.

### Task D6: TMDB on the same row

**Files:** `lib/media_centaur_web/live/settings_live/tmdb.ex` (rewrite)

- [ ] **Step 1: Rewrite**

```elixir
defmodule MediaCentaurWeb.SettingsLive.Tmdb do
  @moduledoc "The TMDB section of the Settings page: one card, one connection row (UIDR-041)."

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.SettingsLive.AcquisitionSection, only: [integration_row: 1]

  alias MediaCentaurWeb.SettingsLive.ConnectionState

  attr :config, :map, required: true
  attr :row, ConnectionState, required: true
  attr :editing, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.settings_card title="TMDB">
      <ul>
        <.integration_row
          row={@row}
          name="The Movie Database"
          editing={@editing}
          description="Metadata and artwork for everything in the library."
        >
          <:form>
            <.settings_field label="API key" layout={:stacked}>
              <.settings_input type="password" name="tmdb_api_key" autocomplete="off" mono autofocus
                placeholder={if @config[:tmdb_api_key_configured?], do: "Leave blank to keep the current key", else: "Enter the API key"} />
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

- [ ] **Step 2: Compile** → clean.

### Task D7: the tests, rewritten around rows and the owner

**Files:** `test/media_centaur_web/live/settings_live_acquisition_test.exs` (rewrite), `test/media_centaur_web/live/settings_live/overview_test.exs` (if it presses Test)

- [ ] **Step 1: Setup.** Keep the Config resets (add `:tmdb_api_key`). Replace the `Req.Test` stubs with the owner started under a verifier stub:

```elixir
  defmodule OkVerifier do
    @behaviour MediaCentaur.IntegrationHealth.Verifier
    @impl true
    def run(_id), do: :ok
  end

  defmodule RejectVerifier do
    @behaviour MediaCentaur.IntegrationHealth.Verifier
    @impl true
    def run(_id), do: {:error, :rejected}
  end

  setup do
    # …Config resets…
    Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)
    start_supervised!(MediaCentaur.IntegrationHealth)
    MediaCentaur.IntegrationHealth.subscribe()
    :ok
  end

  # Waits for the owner's terminal broadcast for `id`, then re-renders.
  defp await_test(view, id) do
    assert_receive {:integration_health_changed, %MediaCentaur.IntegrationHealth.Status{id: ^id, test_state: state}}
                   when state in [:ok, :error],
                   1_000

    render(view)
  end
```

- [ ] **Step 2: Cases** (each mounts with `live_async!(conn, ~p"/settings?section=acquisition")` unless noted):

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

    test "Test asks the owner to verify; the row follows and stored values are untouched", %{conn: conn} do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view |> element("#connection-prowlarr-test") |> render_click()
      html = await_test(view, :prowlarr)

      assert html =~ "Connected"
      assert Config.get(:prowlarr_url) == "http://localhost:9696"
      assert %{status: :ok} = MediaCentaur.Capabilities.load_test_result(:prowlarr)
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
      view |> element("#connection-download_client-setup") |> render_click()
      refute has_element?(view, "#connection-prowlarr-form")
      assert has_element?(view, "#connection-download_client-form")
    end

    test "Save persists, closes the form and the row reads Not tested", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      refute has_element?(view, "#connection-prowlarr-form")
      assert_receive {:integration_health_changed, %{id: :prowlarr, test_state: :unknown}}
      assert render(view) =~ "Not tested"
    end

    test "Save and test persists BEFORE verifying and closes on :ok", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "test"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      html = await_test(view, :prowlarr)
      refute html =~ "connection-prowlarr-form"
      assert html =~ "Connected"
    end

    test "a failed Save and test keeps the typed values in the open form", %{conn: conn} do
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "test"})

      await_test(view, :prowlarr)
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
      view |> element("#connection-download_client-edit") |> render_click()
      view |> element("#connection-download_client-remove") |> render_click()

      assert Config.get(:download_client_type) == nil
      assert_receive {:integration_health_changed, %{id: :download_client, configured?: false}}
      assert render(view) =~ "Not configured"
    end

    test "a blank API key on save keeps the stored usenet key", %{conn: conn} do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://localhost:8085")
      Config.update(:usenet_download_client_api_key, "keep-me")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-usenet_download_client-edit") |> render_click()

      view
      |> form("#connection-usenet_download_client-form", %{"usenet_download_client_url" => "http://localhost:8085", "usenet_download_client_api_key" => ""})
      |> render_submit(%{"_action" => "save"})

      assert MediaCentaur.Secret.expose(Config.get(:usenet_download_client_api_key)) == "keep-me"
    end

    test "Detect from Prowlarr puts each client on its row as a pending detection", %{conn: conn} do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      # Copy the stubbed /api/v1/downloadclient payload from the pre-rewrite
      # version of this file (git show HEAD~1:test/.../settings_live_acquisition_test.exs,
      # describe "detect from Prowlarr routes clients to their protocol slots").
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, detect_payload()) end)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view |> element("#detect-download-clients") |> render_click()
      render_async(view)

      assert has_element?(view, "#connection-download_client", "Detected from Prowlarr, not saved")
      assert has_element?(view, "#connection-usenet_download_client", "Detected from Prowlarr, not saved")
      assert Config.get(:download_client_url) == nil

      view |> element("#connection-download_client-review") |> render_click()
      assert has_element?(view, "#connection-download_client-form input[name=download_client_url][value='http://qbittorrent:8080']")

      view |> element("#connection-usenet_download_client-dismiss") |> render_click()
      refute has_element?(view, "#connection-usenet_download_client", "Detected from Prowlarr")
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

  describe "tmdb row" do
    test "Save and test persists the key BEFORE verifying", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=tmdb")
      view |> element("#connection-tmdb-setup") |> render_click()

      view
      |> form("#connection-tmdb-form", %{"tmdb_api_key" => "tmdb-key-123"})
      |> render_submit(%{"_action" => "test"})

      assert MediaCentaur.Secret.expose(Config.get(:tmdb_api_key)) == "tmdb-key-123"
      assert await_test(view, :tmdb) =~ "Connected"
    end
  end
```

- [ ] **Step 3: Run** `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_acquisition_test.exs` → PASS. Then the whole suite → PASS. Then look: `~/scripts/agents/page-shot --url 'http://127.0.0.1:2160/settings?section=acquisition' --selector '[data-nav-zone=grid]' --viewport 1920x1080 --wait-ms 3500 -o /tmp/acq-new.png` against the approved mockup (`docs/superpowers/specs/2026-09-13-settings-readout-kit-mockups/settings-mockup.html`, artboard 1).
- [ ] **Step 4: Tour locators.** `test/e2e/screenshot.tour.js:179-200`: `#settings-download-client` → `#connection-download_client`, `#settings-prowlarr` → `#connection-prowlarr`. No regeneration.
- [ ] **Step 5: precommit → PASS; commit** `feat(settings): acquisition and TMDB are connection rows; settings reads the connection state owner`.

### Task D8: wiki for Acquisition and TMDB

- [ ] Rewrite `Settings-Reference.md` §Acquisition and §TMDB in the reference register: one table per card (Row · Kind · Options or ladder · Default · Effect), the connection-row states table (spec D7), the edit-form fields table (D9). In `Download-Clients.md`, `Prowlarr-Integration.md` and the setup page, replace "Save, then Test connection" with "press Set up on the row, fill the form, press Save and test"; note that a test from the setup tour now counts.

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Acquisition and TMDB settings as connection rows" && cd -
```

---

## Phase E — Social on the kit (D2, D15)

### Task E1: three cards, relays as connection rows

**Files:** `lib/media_centaur_web/live/settings_live/social_section.ex`, `test/media_centaur_web/live/settings_live_social_test.exs:98-140`

- [ ] **Step 1: Tests.** Replace "lights the section's status dot" with:

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

(Use the message shape the existing test already sends for a status update.) Assert the three card titles render as `h3` text.

- [ ] **Step 2: Implement.** Three `settings_card`s. Your identity: description, the npub `code` + Copy row, `settings_disclosure label="Secret key"` around the reveal/import block unchanged. Relays:

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
    <.settings_input name="url" placeholder="wss://relay.example" mono autocomplete="off" class="min-w-0 flex-1" />
    <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">Add relay</.button>
  </form>
</.settings_card>
```

```elixir
  defp relay_state(%{state: state}) when state in [:connected, :synced], do: :ok
  defp relay_state(%{state: :connecting}), do: :pending
  defp relay_state(_absent_or_failed), do: :error
```

Sharing: `settings_card` with the two `settings_row`s. Delete `any_connected?/1` and the section `h2`; `import MediaCentaurWeb.Components.Settings.ConnectionRow`.

- [ ] **Step 3: Pass; precommit; wiki §Social (row dot replaces the header dot); commit** `feat(settings): social is three cards; relays are connection rows`.

---

## Phase F — the remaining sections adopt the kit

One task per section; each is a commit; each ends with `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/page_smoke_test.exs` green and a look at the section on the dev server. Rule: cards become `settings_card`; fields become the row kind the spec's table names; Save buttons go; tests move from `form |> render_submit` to the row's event.

### Task F1: Services, Preferences, Controls
- Services: `settings_card title="Background services"` around the four toggle rows. Preferences: `settings_card title="Display"` around the toggles and the interface-scale stepper. Controls: each binding group a `settings_card`.
- Commit `refactor(settings): services, preferences and controls on the kit`.

### Task F2: Library
- Data directory → `settings_text_row` (`name: "data_dir"`, `event: "save_data_dir"`, `mono`). Handler: `handle_event("save_data_dir", %{"name" => "data_dir", "value" => value}, socket)`; no flash when unchanged.
- Cleanup → two `settings_stepper`s, events `set_absence_ttl_days` / `set_recent_changes_days`, ladder `Ladder.range(1, 14, 1) ++ Ladder.range(21, 90, 7)`; handlers `Config.update/2` when on the ladder.
- Media directories, Excluded directories: `settings_card` wrappers; Excluded directories renders through `settings_list` (`items: @exclude_dirs`, `remove_event: "exclude_dir:remove"`, `add_event: "exclude_dir:add"`, `error: @exclude_dir_error`, `mono`), its handlers unchanged apart from reading `item` instead of the old input name.
- Tests: "typing a data directory and blurring persists it", "stepping the absence TTL persists"; the exclude-dirs test file's selectors follow the list's markup.
- Commit `refactor(settings): library on the kit`.

### Task F3: Media Import
- Extras folder names and Ignored folder names → `settings_list` in their own cards, `event_value: %{"key" => "extras_dirs"}` / `"skip_dirs"`, events `config_list_add` / `config_list_remove`:

```elixir
  @config_lists %{"extras_dirs" => :extras_dirs, "skip_dirs" => :skip_dirs}

  def handle_event("config_list_add", %{"key" => key, "item" => raw}, socket) when is_map_key(@config_lists, key) do
    item = String.trim(raw)
    config_key = @config_lists[key]
    current = Config.get(config_key) || []
    if item != "" and item not in current, do: Config.update(config_key, current ++ [item])
    {:noreply, assign(socket, config: load_config())}
  end

  def handle_event("config_list_remove", %{"key" => key, "item" => item}, socket) when is_map_key(@config_lists, key) do
    config_key = @config_lists[key]
    Config.update(config_key, List.delete(Config.get(config_key) || [], item))
    {:noreply, assign(socket, config: load_config())}
  end
```

- Auto-approve threshold → `settings_stepper`, ladder `for n <- 50..100//5, do: n / 100`, `value_label` `:erlang.float_to_binary(v, decimals: 2)`, event `set_auto_approve_threshold` (accept when within 0.001 of a rung).
- Artwork resolution → `settings_choice` (`[{"4k", "4K"}, {"1080p", "1080p"}]`, event `set_image_resolution`); the handler keeps the re-fetch trigger `save_import` ran on a resolution change (`settings_live.ex:1030-1060`). Delete `save_import`.
- Tests at `settings_live_test.exs:383-447` move to the new events; the re-fetch assertions stay.
- Commit `refactor(settings): media import on the kit; folder names are lists`.

### Task F4: Playback
- mpv path and IPC socket directory → `settings_text_row` (`mono`, `label_suffix` holding `path_status`), events `set_mpv_path` / `set_mpv_socket_dir`; timeout → `settings_stepper` over `Ladder.range(100, 5000, 100)`, event `set_mpv_socket_timeout_ms`. Delete `save_playback`.
- Commit `refactor(settings): playback on the kit`.

### Task F5: Language
- "Languages you understand": `settings_card` around the existing add form and ordered chips. "Audio & subtitles": `settings_select_row` per policy select (`language.ex:136-242`), event `set_language_policy`; the handler merges the one changed key into the draft and persists through the existing `LanguagePolicy` write. Delete the Save.
- `settings_live_test.exs:306` becomes one `render_change` per select.
- Commit `refactor(settings): language policy selects save on change`.

### Task F6: Maintenance and Danger Zone
- Maintenance: `settings_card`s per existing group with an action row per repair (label + description left, the button right). Danger: `settings_card class="border border-error/20" title="Danger zone"` with the action row and the triangle beside the label.
- Commit `refactor(settings): maintenance and danger zone on the kit`.

### Task F7: System
- Service, Health Check, Guide and Updates cards → `settings_card` (title, description = today's subtitle, `:action` = today's right-hand control). Updates: the interval input → `settings_stepper` over `[15, 30, 60, 120, 240, 720, 1440]` minutes, floored by `Config.update_check_interval_floor_minutes/0`, event `set_update_check_interval`. Status lists and identity block unchanged.
- `settings_live_update_automation_test.exs` interval cases move to the stepper.
- Commit `refactor(settings): system on the kit`.

### Task F8: retire what nothing calls
- Delete `settings_card_header/1`, `status_dot/1`, `connection_status/1` from the kit; `grep -rn "settings_card_header\|status_dot\|connection_status" lib/ storybook/` returns nothing. `~/scripts/agents/agent-mix precommit` → PASS.
- Commit `chore(settings): retire the pre-kit header and status helpers`.

### Task F9: wiki for the remaining sections
- `Settings-Reference.md` §System, §Library, §Media Import, §Playback, §Language in the reference register.

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Settings reference on the readout kit" && cd -
```

---

## Phase G — closure

### Task G1: terms, docs, skill
- `docs/GLOSSARY.md`: rows for **Connection row**, **Connection state owner**, **Readout state / Edit state**, **Save on the act**, **Gated card**, **Settings kit**.
- `.claude/skills/user-interface/SKILL.md`: the "Non-toggle settings controls" section becomes "Settings kit" (row kinds, connection row, `/storybook/settings/*`); the inventory gains the kit; the `settings_choice`-from-git sentence goes.
- `docs/storybook.md`: the settings area in the triage table. `docs/architecture.md`: IntegrationHealth as the connection state owner, if it lists it.
- `campaigns/settings-readout-kit.md`: reconcile, then retire the file and its README entry (ADR-042).
- Commit `docs: settings kit terms, skill and storybook notes`.

### Task G2: owner look
Open `/settings?section=acquisition`, `?section=social`, `?section=import` on the dev server for the owner. Do not screenshot when their browser is open.

---

## Self-review

**Spec coverage.** D1 → B3. D2 → B2 + F. D3 → B1/B2 + D5/F. D4 → D4/D5, F2–F7. D5 → B1/B2/D2. D6–D8 → D1/D2/D5. D9 → D5 footer + D4 `save_connection` + `handle_info` (form stays open on `:error`). D10 → D4 `edit_connection`. D11 → D5 `description`, Set up. D12 → D3/D4/D5. D13 → D5 card action, D4 `review_detected`/`dismiss_detected`. D14 → D6. D15 → E1. D16–D19, D21 → D5. D20 → Phase A. D22 → C1. D23–D25 → C2. D26 → D1/D4. D27 → D4. D28 → D4/D5 ids. D29 → A1 + B2 (Ladder). D30 → B2 text row. D31 → B2 `settings_input`. D32 → B2 `settings_list` + F2/F3. D33 → B1. Wiki/tour → A7, D7, D8, E1, F9.

**Type consistency.** `ConnectionState.build/3` returns `%ConnectionState{id, state, state_label, tested_at, address, credential, prefill}`; `integration_row/1` reads exactly those, and derives its DOM id from `row.id`. `connection_row/1`'s `values:` includes `:pending` and `:detected`, which `ConnectionState` produces. `settings_choice/1` and `settings_stepper/1` push `choice`; `set_auto_grab` reads `key` + `choice` and hands both to `AutoGrabSettings.put/2`. `save_connection` reads `connection` from the hidden input and `_action` from the submit button. `IntegrationHealth.verify/1` accepts the four ids after C1. `Settings` exports `Ladder`; `AutoGrabSettings` exposes its ladders as lists.

**Placeholders.** The F tasks give rows, events, ladders and handler shapes rather than full templates; the templates are one component call per row against the contracts defined in full in B1/B2/D2. The detect-stub payload in D7 is copied from the pre-rewrite test (named), not invented.
