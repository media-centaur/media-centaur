# Controls page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Settings → Controls subpage that shows every keyboard and gamepad binding (grouped by category) and lets the user rebind, clear, and reset them — functioning as both cheat sheet and customisation UI. See `docs/superpowers/specs/2026-04-20-controls-page-design.md`.

**Architecture:** New thin facade `MediaCentarr.Controls` over `Settings.Entry` (three rows: `controls.keyboard`, `controls.gamepad`, `controls.glyph_style`). A compile-time catalog describes all bindings. LiveView section renders the UI. A new JS bridge module handles one-shot capture and hot-swaps the input system's key/button maps on change. The backtick console hotkey moves from hardcoded to catalog-driven.

**Tech Stack:** Elixir/Phoenix, LiveView, Ecto, daisyUI + Tailwind, vanilla JS (`bun test`).

---

## File Structure

**New files:**
- `lib/media_centarr/controls.ex` — facade module (public API)
- `lib/media_centarr/controls/binding.ex` — `%Binding{}` struct
- `lib/media_centarr/controls/catalog.ex` — compile-time list of all bindings + uniqueness assertion
- `lib/media_centarr/controls/store.ex` — read/write `Settings.Entry` rows, resolve defaults
- `lib/media_centarr_web/live/settings_live/controls_logic.ex` — pure helpers: view grouping, glyph display, conflict detection
- `lib/media_centarr_web/live/settings_live/controls.ex` — LiveView section renderer (function component)
- `assets/css/controls.css` — scoped styles for keycap / gamepad glyphs / listening state
- `assets/js/input/controls_bridge.js` — one-shot capture + hot-swap
- `assets/js/input/__tests__/controls_bridge.test.js`
- `test/media_centarr/controls_test.exs`
- `test/media_centarr/controls/catalog_test.exs`
- `test/media_centarr_web/live/settings_live/controls_logic_test.exs`
- `test/media_centarr_web/live/settings_live/controls_test.exs`

**Modified files:**
- `lib/media_centarr/topics.ex` — add `controls_updates/0`
- `lib/media_centarr_web/live/settings_live.ex` — add `"controls"` to `@sections`; add `section_content/1` clause delegating to `SettingsLive.Controls.render/1`
- `lib/media_centarr_web/components/layouts.ex` — pass bindings JSON into `#input-system` as `data-input-bindings`
- `assets/css/app.css` — `@import "./controls.css"` + keycap custom props on `[data-theme="dark"]`
- `assets/js/input/index.js` — read `data-input-bindings` from the hook element, build `keyMap`/`buttonMap`, pass to sources and orchestrator; listen for `phx:controls:updated` to rebuild
- `assets/js/input/__tests__/index.test.js` — extend for bindings load + updated event
- `assets/js/app.js` — backtick listener reads binding from `data-global-bindings`, listens for `phx:controls:updated`
- `assets/js/hooks/console.test.js` — update for attr-driven binding

**Wiki (separate repo `../media-centarr.wiki/`):**
- `Keyboard-and-Gamepad.md`
- `Keyboard-Shortcuts.md`

---

## Task 1: Add `controls_updates/0` topic

**Files:**
- Modify: `lib/media_centarr/topics.ex`

- [ ] **Step 1: Check existing topics**

Open `lib/media_centarr/topics.ex` to confirm the module's one-function-per-topic convention.

- [ ] **Step 2: Add the function**

Edit `lib/media_centarr/topics.ex` — add after `self_update_progress`:

```elixir
  def controls_updates, do: "controls:updates"
```

- [ ] **Step 3: Verify compiles**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`
Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
jj desc -m "feat(controls): add controls_updates pubsub topic"
```

(No test — this module is trivial constants; coverage comes from the modules that subscribe.)

---

## Task 2: `Binding` struct

**Files:**
- Create: `lib/media_centarr/controls/binding.ex`
- Create: `test/media_centarr/controls/binding_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr/controls/binding_test.exs`:

```elixir
defmodule MediaCentarr.Controls.BindingTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Controls.Binding

  test "struct requires id, category, name, scope" do
    binding = %Binding{
      id: :navigate_up,
      category: :navigation,
      name: "Move up",
      description: "Focus the item above",
      default_key: "ArrowUp",
      default_button: 12,
      scope: :input_system
    }

    assert binding.id == :navigate_up
    assert binding.category == :navigation
    assert binding.scope == :input_system
  end

  test "default_key and default_button may be nil (unbound default)" do
    binding = %Binding{
      id: :fake,
      category: :system,
      name: "Fake",
      description: "No defaults",
      default_key: nil,
      default_button: nil,
      scope: :global
    }

    assert binding.default_key == nil
    assert binding.default_button == nil
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr/controls/binding_test.exs`
Expected: `MediaCentarr.Controls.Binding is not available`.

- [ ] **Step 3: Implement**

`lib/media_centarr/controls/binding.ex`:

```elixir
defmodule MediaCentarr.Controls.Binding do
  @moduledoc """
  One entry in the controls catalog.

  The catalog lists every action the app responds to. Each binding carries
  its category, display metadata, and default keyboard/gamepad values.
  Unbound defaults are represented as `nil`.
  """

  @type category :: :navigation | :zones | :playback | :system
  @type scope :: :input_system | :global

  @type t :: %__MODULE__{
          id: atom(),
          category: category(),
          name: String.t(),
          description: String.t(),
          default_key: String.t() | nil,
          default_button: non_neg_integer() | nil,
          scope: scope()
        }

  defstruct [
    :id,
    :category,
    :name,
    :description,
    :default_key,
    :default_button,
    :scope
  ]
end
```

- [ ] **Step 4: Run test — expect pass**

Run: `mix test test/media_centarr/controls/binding_test.exs`
Expected: 2 tests passing.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): Binding struct for catalog entries"
```

---

## Task 3: `Catalog` with uniqueness invariant

**Files:**
- Create: `lib/media_centarr/controls/catalog.ex`
- Create: `test/media_centarr/controls/catalog_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr/controls/catalog_test.exs`:

```elixir
defmodule MediaCentarr.Controls.CatalogTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Controls.Catalog

  test "all/0 returns 11 bindings" do
    assert length(Catalog.all()) == 11
  end

  test "all binding ids are unique" do
    ids = Enum.map(Catalog.all(), & &1.id)
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "every binding has a category in the valid set" do
    valid = [:navigation, :zones, :playback, :system]
    assert Enum.all?(Catalog.all(), &(&1.category in valid))
  end

  test "default_key values are unique (excluding nil)" do
    keys = Catalog.all() |> Enum.map(& &1.default_key) |> Enum.reject(&is_nil/1)
    assert length(keys) == length(Enum.uniq(keys)), "duplicate default_key in catalog"
  end

  test "default_button values are unique (excluding nil)" do
    buttons = Catalog.all() |> Enum.map(& &1.default_button) |> Enum.reject(&is_nil/1)
    assert length(buttons) == length(Enum.uniq(buttons)), "duplicate default_button in catalog"
  end

  test "get/1 returns a binding by id" do
    assert %{id: :navigate_up, name: "Move up"} = Catalog.get(:navigate_up)
  end

  test "get/1 returns nil for unknown id" do
    assert Catalog.get(:nope) == nil
  end

  test "by_category/1 groups correctly" do
    nav = Catalog.by_category(:navigation)
    assert Enum.all?(nav, &(&1.category == :navigation))
    assert length(nav) == 7
  end

  test "toggle_console is in :system category with scope :global" do
    binding = Catalog.get(:toggle_console)
    assert binding.category == :system
    assert binding.scope == :global
    assert binding.default_key == "`"
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr/controls/catalog_test.exs`
Expected: `MediaCentarr.Controls.Catalog is not available`.

- [ ] **Step 3: Implement**

`lib/media_centarr/controls/catalog.ex`:

```elixir
defmodule MediaCentarr.Controls.Catalog do
  @moduledoc """
  Compile-time list of every keyboard/gamepad binding the app supports.

  The catalog is the single source of truth:
  - The Settings → Controls LiveView renders rows from this list.
  - The JS input system's key and button maps are built from this list.
  - Wiki cheat-sheet pages generate tables from this list.

  Adding a new binding = one struct added here. Removing a binding =
  one struct removed and any persisted override in `Settings.Entry` under
  `controls.keyboard`/`controls.gamepad` naturally orphans (harmless).

  Uniqueness invariant: no two bindings share a default key, no two
  share a default button. Enforced at compile time.
  """

  alias MediaCentarr.Controls.Binding

  @bindings [
    %Binding{
      id: :navigate_up,
      category: :navigation,
      name: "Move up",
      description: "Focus the item above the current one",
      default_key: "ArrowUp",
      default_button: 12,
      scope: :input_system
    },
    %Binding{
      id: :navigate_down,
      category: :navigation,
      name: "Move down",
      description: "Focus the item below the current one",
      default_key: "ArrowDown",
      default_button: 13,
      scope: :input_system
    },
    %Binding{
      id: :navigate_left,
      category: :navigation,
      name: "Move left",
      description: "Focus the item to the left",
      default_key: "ArrowLeft",
      default_button: 14,
      scope: :input_system
    },
    %Binding{
      id: :navigate_right,
      category: :navigation,
      name: "Move right",
      description: "Focus the item to the right",
      default_key: "ArrowRight",
      default_button: 15,
      scope: :input_system
    },
    %Binding{
      id: :select,
      category: :navigation,
      name: "Select",
      description: "Confirm or activate the focused item",
      default_key: "Enter",
      default_button: 0,
      scope: :input_system
    },
    %Binding{
      id: :back,
      category: :navigation,
      name: "Back",
      description: "Return to the previous zone or close modals",
      default_key: "Escape",
      default_button: 1,
      scope: :input_system
    },
    %Binding{
      id: :clear,
      category: :navigation,
      name: "Clear",
      description: "Clear the current search or filter",
      default_key: "Backspace",
      default_button: 3,
      scope: :input_system
    },
    %Binding{
      id: :zone_next,
      category: :zones,
      name: "Next zone",
      description: "Cycle focus to the next navigation zone",
      default_key: "]",
      default_button: 5,
      scope: :input_system
    },
    %Binding{
      id: :zone_prev,
      category: :zones,
      name: "Previous zone",
      description: "Cycle focus to the previous navigation zone",
      default_key: "[",
      default_button: 4,
      scope: :input_system
    },
    %Binding{
      id: :play,
      category: :playback,
      name: "Play",
      description: "Start playback of the focused item",
      default_key: "p",
      default_button: 9,
      scope: :input_system
    },
    %Binding{
      id: :toggle_console,
      category: :system,
      name: "Toggle console",
      description: "Open or close the diagnostics console drawer",
      default_key: "`",
      default_button: nil,
      scope: :global
    }
  ]

  # Compile-time uniqueness assertion
  keys = @bindings |> Enum.map(& &1.default_key) |> Enum.reject(&is_nil/1)
  buttons = @bindings |> Enum.map(& &1.default_button) |> Enum.reject(&is_nil/1)

  if length(keys) != length(Enum.uniq(keys)) do
    raise "Controls.Catalog: duplicate default_key — #{inspect(keys -- Enum.uniq(keys))}"
  end

  if length(buttons) != length(Enum.uniq(buttons)) do
    raise "Controls.Catalog: duplicate default_button — #{inspect(buttons -- Enum.uniq(buttons))}"
  end

  @doc "Full list of bindings."
  @spec all() :: [Binding.t()]
  def all, do: @bindings

  @doc "Get one binding by id, or nil if unknown."
  @spec get(atom()) :: Binding.t() | nil
  def get(id) when is_atom(id), do: Enum.find(@bindings, &(&1.id == id))

  @doc "All bindings in a given category."
  @spec by_category(atom()) :: [Binding.t()]
  def by_category(category), do: Enum.filter(@bindings, &(&1.category == category))

  @doc "Ordered list of category atoms — governs UI order."
  @spec categories() :: [atom()]
  def categories, do: [:navigation, :zones, :playback, :system]
end
```

- [ ] **Step 4: Run test — expect pass**

Run: `mix test test/media_centarr/controls/catalog_test.exs`
Expected: 9 tests passing.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): Catalog with 11 bindings and uniqueness assertions"
```

---

## Task 4: `Store` — read/write `Settings.Entry`

**Files:**
- Create: `lib/media_centarr/controls/store.ex`
- Create: `test/media_centarr/controls/store_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr/controls/store_test.exs`:

```elixir
defmodule MediaCentarr.Controls.StoreTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Controls.Store

  describe "read_keyboard/0 and write_keyboard/1" do
    test "returns empty map when no entry" do
      assert Store.read_keyboard() == %{}
    end

    test "round-trips overrides" do
      :ok = Store.write_keyboard(%{"navigate_up" => "w", "select" => nil})
      assert Store.read_keyboard() == %{"navigate_up" => "w", "select" => nil}
    end

    test "write overwrites prior state" do
      :ok = Store.write_keyboard(%{"navigate_up" => "w"})
      :ok = Store.write_keyboard(%{"select" => " "})
      assert Store.read_keyboard() == %{"select" => " "}
    end
  end

  describe "read_gamepad/0 and write_gamepad/1" do
    test "returns empty map when no entry" do
      assert Store.read_gamepad() == %{}
    end

    test "round-trips integer button overrides" do
      :ok = Store.write_gamepad(%{"select" => 2, "back" => nil})
      assert Store.read_gamepad() == %{"select" => 2, "back" => nil}
    end
  end

  describe "read_glyph_style/0 and write_glyph_style/1" do
    test "defaults to xbox when no entry" do
      assert Store.read_glyph_style() == "xbox"
    end

    test "round-trips playstation" do
      :ok = Store.write_glyph_style("playstation")
      assert Store.read_glyph_style() == "playstation"
    end
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr/controls/store_test.exs`
Expected: module not loaded.

- [ ] **Step 3: Implement**

`lib/media_centarr/controls/store.ex`:

```elixir
defmodule MediaCentarr.Controls.Store do
  @moduledoc """
  Persists keyboard, gamepad, and glyph-style settings in `Settings.Entry` rows.

  Three keys are used:
  - `controls.keyboard` — map of binding_id_string to key_string (or nil = cleared)
  - `controls.gamepad`  — map of binding_id_string to button_index_integer (or nil = cleared)
  - `controls.glyph_style` — "xbox" | "playstation"

  Missing keys in the stored maps are interpreted by `MediaCentarr.Controls`
  as "use the catalog default" — not nil. The explicit nil semantics ("user
  cleared this slot intentionally") must therefore be preserved through
  serialization; SQLite's `:map` column does this correctly.
  """

  alias MediaCentarr.Settings

  @keyboard_key "controls.keyboard"
  @gamepad_key "controls.gamepad"
  @glyph_key "controls.glyph_style"
  @default_glyph "xbox"

  @spec read_keyboard() :: %{optional(String.t()) => String.t() | nil}
  def read_keyboard, do: read_map(@keyboard_key)

  @spec read_gamepad() :: %{optional(String.t()) => non_neg_integer() | nil}
  def read_gamepad, do: read_map(@gamepad_key)

  @spec read_glyph_style() :: String.t()
  def read_glyph_style do
    case Settings.get_by_key(@glyph_key) do
      {:ok, %{value: %{"style" => style}}} when style in ["xbox", "playstation"] -> style
      _ -> @default_glyph
    end
  end

  @spec write_keyboard(map()) :: :ok
  def write_keyboard(map) when is_map(map), do: write_map(@keyboard_key, map)

  @spec write_gamepad(map()) :: :ok
  def write_gamepad(map) when is_map(map), do: write_map(@gamepad_key, map)

  @spec write_glyph_style(String.t()) :: :ok
  def write_glyph_style(style) when style in ["xbox", "playstation"] do
    Settings.find_or_create_entry!(%{key: @glyph_key, value: %{"style" => style}})
    :ok
  end

  defp read_map(key) do
    case Settings.get_by_key(key) do
      {:ok, %{value: value}} when is_map(value) -> value
      _ -> %{}
    end
  end

  defp write_map(key, map) do
    Settings.find_or_create_entry!(%{key: key, value: map})
    :ok
  end
end
```

- [ ] **Step 4: Run test — expect pass**

Run: `mix test test/media_centarr/controls/store_test.exs`
Expected: 7 tests passing.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): Store persists keyboard/gamepad/glyph entries"
```

---

## Task 5: `Controls` facade with conflict/swap logic

**Files:**
- Create: `lib/media_centarr/controls.ex`
- Create: `test/media_centarr/controls_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr/controls_test.exs`:

```elixir
defmodule MediaCentarr.ControlsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Controls

  describe "get/0" do
    test "returns all catalog defaults when no overrides" do
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:navigate_up].button == 12
      assert resolved[:select].key == "Enter"
      assert resolved[:toggle_console].key == "`"
      assert resolved[:toggle_console].button == nil
    end

    test "explicit nil override is preserved (user cleared the slot)" do
      :ok = Controls.clear(:back, :keyboard)
      assert Controls.get()[:back].key == nil
    end

    test "user override beats default" do
      {:ok, _} = Controls.put(:select, :keyboard, " ")
      assert Controls.get()[:select].key == " "
    end
  end

  describe "put/3 without conflict" do
    test "sets a keyboard value" do
      assert {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      assert Controls.get()[:navigate_up].key == "w"
    end

    test "sets a gamepad button" do
      assert {:ok, _} = Controls.put(:select, :gamepad, 2)
      assert Controls.get()[:select].button == 2
    end
  end

  describe "put/3 with conflict — auto-swap" do
    test "displaced binding receives the previous resolved value" do
      # Initial: navigate_up=ArrowUp, navigate_down=ArrowDown
      # User rebinds navigate_down to ArrowUp
      assert {:ok, _} = Controls.put(:navigate_down, :keyboard, "ArrowUp")
      resolved = Controls.get()
      assert resolved[:navigate_down].key == "ArrowUp"
      # navigate_up (displaced) receives previous value of navigate_down, which was ArrowDown
      assert resolved[:navigate_up].key == "ArrowDown"
    end

    test "swap handles displaced binding when rebound value was previously overridden" do
      {:ok, _} = Controls.put(:select, :keyboard, "s")
      # select=s, back=Escape. Rebind back to s.
      {:ok, _} = Controls.put(:back, :keyboard, "s")
      resolved = Controls.get()
      assert resolved[:back].key == "s"
      # select (displaced) gets back's previous value (Escape)
      assert resolved[:select].key == "Escape"
    end

    test "keyboard and gamepad are separate namespaces — no cross-kind conflicts" do
      # button index 0 is select's default on gamepad
      # "0" is not currently used as a keyboard default
      {:ok, _} = Controls.put(:select, :keyboard, "0")
      resolved = Controls.get()
      assert resolved[:select].key == "0"
      assert resolved[:select].button == 0
    end
  end

  describe "clear/2" do
    test "sets slot to nil without swap" do
      :ok = Controls.clear(:back, :keyboard)
      resolved = Controls.get()
      assert resolved[:back].key == nil
      # No other binding was disturbed
      assert resolved[:select].key == "Enter"
    end
  end

  describe "reset_category/1" do
    test "removes only the overrides in that category" do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:play, :keyboard, "x")
      :ok = Controls.reset_category(:navigation)
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:play].key == "x"
    end
  end

  describe "reset_all/0" do
    test "removes every override, keyboard and gamepad" do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:select, :gamepad, 2)
      :ok = Controls.reset_all()
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:select].button == 0
    end
  end

  describe "subscribe/0 and broadcast" do
    test "put/3 broadcasts :controls_changed with resolved map" do
      :ok = Controls.subscribe()
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "w"
    end

    test "clear/2 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.clear(:back, :keyboard)
      assert_receive {:controls_changed, map}
      assert map[:back].key == nil
    end

    test "reset_all/0 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.reset_all()
      assert_receive {:controls_changed, _}
    end
  end

  describe "glyph_style" do
    test "defaults to xbox" do
      assert Controls.glyph_style() == "xbox"
    end

    test "round-trips playstation" do
      :ok = Controls.set_glyph_style("playstation")
      assert Controls.glyph_style() == "playstation"
    end

    test "set_glyph_style/1 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.set_glyph_style("playstation")
      assert_receive {:controls_changed, _}
    end
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr/controls_test.exs`
Expected: module not loaded.

- [ ] **Step 3: Implement**

`lib/media_centarr/controls.ex`:

```elixir
defmodule MediaCentarr.Controls do
  use Boundary,
    deps: [MediaCentarr.Settings],
    exports: [Binding, Catalog]

  @moduledoc """
  Facade for keyboard/gamepad binding configuration.

  Every binding is declared at compile time in `Controls.Catalog`. User
  overrides live in three `Settings.Entry` rows (see `Controls.Store`).
  `get/0` resolves the full map by overlaying overrides on catalog defaults.

  Writes go through `put/3` or `clear/2`, which handle conflict detection
  and (for put) auto-swap. Every successful write broadcasts
  `{:controls_changed, resolved_map}` on the `controls:updates` topic.
  """

  alias MediaCentarr.Controls.{Binding, Catalog, Store}
  alias MediaCentarr.Topics

  @type kind :: :keyboard | :gamepad
  @type resolved :: %{atom() => %{key: String.t() | nil, button: non_neg_integer() | nil}}

  @doc "Subscribe to controls change broadcasts."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.controls_updates())

  @doc """
  Returns a map keyed by binding id, each value `%{key: ..., button: ...}`.
  `key` and `button` may be `nil` if the user cleared the slot.
  """
  @spec get() :: resolved()
  def get do
    keyboard_overrides = Store.read_keyboard()
    gamepad_overrides = Store.read_gamepad()

    Catalog.all()
    |> Enum.map(fn %Binding{} = b ->
      {b.id,
       %{
         key: resolve(keyboard_overrides, Atom.to_string(b.id), b.default_key),
         button: resolve(gamepad_overrides, Atom.to_string(b.id), b.default_button)
       }}
    end)
    |> Map.new()
  end

  @doc "Returns the current glyph style (\"xbox\" or \"playstation\")."
  @spec glyph_style() :: String.t()
  def glyph_style, do: Store.read_glyph_style()

  @doc "Set the glyph style and broadcast."
  @spec set_glyph_style(String.t()) :: :ok
  def set_glyph_style(style) when style in ["xbox", "playstation"] do
    :ok = Store.write_glyph_style(style)
    broadcast()
    :ok
  end

  @doc """
  Bind an action to a key or button. If the value is already bound to
  another action (within the same kind), perform an auto-swap: the
  displaced action receives the *currently-resolved* value of the action
  being rebound (its override if any, otherwise the catalog default).
  """
  @spec put(atom(), kind(), String.t() | non_neg_integer()) ::
          {:ok, resolved()} | {:error, term()}
  def put(id, :keyboard, value) when is_atom(id) and is_binary(value) do
    do_put(id, :keyboard, value, &Store.read_keyboard/0, &Store.write_keyboard/1, & &1.key)
  end

  def put(id, :gamepad, value) when is_atom(id) and is_integer(value) and value >= 0 do
    do_put(id, :gamepad, value, &Store.read_gamepad/0, &Store.write_gamepad/1, & &1.button)
  end

  @doc "Clear a slot — user-intentional un-binding. Does not swap."
  @spec clear(atom(), kind()) :: :ok | {:error, :unknown_id}
  def clear(id, :keyboard), do: do_clear(id, &Store.read_keyboard/0, &Store.write_keyboard/1)
  def clear(id, :gamepad), do: do_clear(id, &Store.read_gamepad/0, &Store.write_gamepad/1)

  @doc "Remove every user override in a category; fall back to catalog defaults."
  @spec reset_category(atom()) :: :ok
  def reset_category(category) do
    ids = Catalog.by_category(category) |> Enum.map(&Atom.to_string(&1.id))

    :ok = Store.write_keyboard(Map.drop(Store.read_keyboard(), ids))
    :ok = Store.write_gamepad(Map.drop(Store.read_gamepad(), ids))
    broadcast()
    :ok
  end

  @doc "Remove every user override."
  @spec reset_all() :: :ok
  def reset_all do
    :ok = Store.write_keyboard(%{})
    :ok = Store.write_gamepad(%{})
    broadcast()
    :ok
  end

  # --- private ---

  defp do_put(id, kind, value, reader, writer, extractor) do
    case Catalog.get(id) do
      nil ->
        {:error, :unknown_id}

      %Binding{} ->
        overrides = reader.()
        resolved_now = get()
        id_str = Atom.to_string(id)

        # Find the conflicting binding (if any) — different id, same resolved value.
        conflict =
          Enum.find(resolved_now, fn {other_id, slot} ->
            other_id != id and extractor.(slot) == value
          end)

        previous_value = extractor.(resolved_now[id])

        new_overrides =
          overrides
          |> Map.put(id_str, value)
          |> maybe_swap(conflict, previous_value)

        :ok = writer.(new_overrides)
        broadcast()
        {:ok, get()}
    end
  end

  defp maybe_swap(overrides, nil, _previous), do: overrides

  defp maybe_swap(overrides, {displaced_id, _slot}, previous_value) do
    Map.put(overrides, Atom.to_string(displaced_id), previous_value)
  end

  defp do_clear(id, reader, writer) do
    case Catalog.get(id) do
      nil ->
        {:error, :unknown_id}

      _ ->
        new = Map.put(reader.(), Atom.to_string(id), nil)
        :ok = writer.(new)
        broadcast()
        :ok
    end
  end

  defp resolve(overrides, id_str, default) do
    # Map.get/3 returns default only when the key is absent. An explicit
    # nil value (user-cleared) is preserved as-is.
    case Map.fetch(overrides, id_str) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.controls_updates(),
      {:controls_changed, get()}
    )
  end
end
```

- [ ] **Step 4: Run test — expect pass**

Run: `mix test test/media_centarr/controls_test.exs`
Expected: 15 tests passing.

- [ ] **Step 5: Run full test suite to catch regressions**

Run: `mix test`
Expected: all passing.

- [ ] **Step 6: Commit**

```bash
jj desc -m "feat(controls): facade with conflict/swap logic and pubsub"
```

---

## Task 6: `ControlsLogic` pure helpers

**Files:**
- Create: `lib/media_centarr_web/live/settings_live/controls_logic.ex`
- Create: `test/media_centarr_web/live/settings_live/controls_logic_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr_web/live/settings_live/controls_logic_test.exs`:

```elixir
defmodule MediaCentarrWeb.SettingsLive.ControlsLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.SettingsLive.ControlsLogic

  describe "group_for_view/1" do
    test "returns ordered list of {category, [binding_view]} tuples" do
      resolved = %{
        navigate_up: %{key: "w", button: 12},
        navigate_down: %{key: "s", button: 13},
        navigate_left: %{key: "a", button: 14},
        navigate_right: %{key: "d", button: 15},
        select: %{key: "Enter", button: 0},
        back: %{key: nil, button: 1},
        clear: %{key: "Backspace", button: 3},
        zone_next: %{key: "]", button: 5},
        zone_prev: %{key: "[", button: 4},
        play: %{key: "p", button: 9},
        toggle_console: %{key: "`", button: nil}
      }

      [{:navigation, nav}, {:zones, zones}, {:playback, play}, {:system, sys}] =
        ControlsLogic.group_for_view(resolved)

      assert length(nav) == 7
      assert length(zones) == 2
      assert length(play) == 1
      assert length(sys) == 1

      [first | _] = nav
      assert first.id == :navigate_up
      assert first.key == "w"
      assert first.button == 12
      assert first.name == "Move up"
    end
  end

  describe "display_key/1" do
    test "pretty-prints special keys" do
      assert ControlsLogic.display_key("ArrowUp") == "↑"
      assert ControlsLogic.display_key("ArrowDown") == "↓"
      assert ControlsLogic.display_key("ArrowLeft") == "←"
      assert ControlsLogic.display_key("ArrowRight") == "→"
      assert ControlsLogic.display_key("Enter") == "Enter"
      assert ControlsLogic.display_key("Escape") == "Esc"
      assert ControlsLogic.display_key("Backspace") == "Backspace"
      assert ControlsLogic.display_key(" ") == "Space"
    end

    test "uppercases single letters" do
      assert ControlsLogic.display_key("p") == "P"
    end

    test "returns key as-is for symbols" do
      assert ControlsLogic.display_key("[") == "["
      assert ControlsLogic.display_key("]") == "]"
      assert ControlsLogic.display_key("`") == "`"
    end

    test "returns nil when key is nil" do
      assert ControlsLogic.display_key(nil) == nil
    end
  end

  describe "display_button/2" do
    test "xbox labels face buttons" do
      assert ControlsLogic.display_button(0, "xbox") == "A"
      assert ControlsLogic.display_button(1, "xbox") == "B"
      assert ControlsLogic.display_button(2, "xbox") == "X"
      assert ControlsLogic.display_button(3, "xbox") == "Y"
    end

    test "playstation labels face buttons" do
      assert ControlsLogic.display_button(0, "playstation") == "✕"
      assert ControlsLogic.display_button(1, "playstation") == "○"
      assert ControlsLogic.display_button(2, "playstation") == "□"
      assert ControlsLogic.display_button(3, "playstation") == "△"
    end

    test "xbox labels shoulders" do
      assert ControlsLogic.display_button(4, "xbox") == "LB"
      assert ControlsLogic.display_button(5, "xbox") == "RB"
    end

    test "playstation labels shoulders" do
      assert ControlsLogic.display_button(4, "playstation") == "L1"
      assert ControlsLogic.display_button(5, "playstation") == "R1"
    end

    test "labels dpad consistently across styles" do
      assert ControlsLogic.display_button(12, "xbox") == "D-Pad ↑"
      assert ControlsLogic.display_button(13, "xbox") == "D-Pad ↓"
      assert ControlsLogic.display_button(14, "xbox") == "D-Pad ←"
      assert ControlsLogic.display_button(15, "xbox") == "D-Pad →"
    end

    test "labels options button per platform" do
      assert ControlsLogic.display_button(9, "xbox") == "Menu"
      assert ControlsLogic.display_button(9, "playstation") == "Options"
    end

    test "returns nil for nil" do
      assert ControlsLogic.display_button(nil, "xbox") == nil
    end

    test "returns fallback for unknown indices" do
      assert ControlsLogic.display_button(99, "xbox") == "Btn 99"
    end
  end

  describe "pending_swap/3" do
    test "returns the id that would be displaced on a conflicting put" do
      resolved = %{
        navigate_up: %{key: "ArrowUp", button: 12},
        navigate_down: %{key: "ArrowDown", button: 13}
      }

      assert ControlsLogic.pending_swap(resolved, :navigate_up, "ArrowDown", :keyboard) ==
               :navigate_down
    end

    test "returns nil when no conflict" do
      resolved = %{navigate_up: %{key: "ArrowUp", button: 12}}
      assert ControlsLogic.pending_swap(resolved, :navigate_up, "w", :keyboard) == nil
    end

    test "ignores self" do
      resolved = %{select: %{key: "Enter", button: 0}}
      assert ControlsLogic.pending_swap(resolved, :select, "Enter", :keyboard) == nil
    end
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr_web/live/settings_live/controls_logic_test.exs`
Expected: module not loaded.

- [ ] **Step 3: Implement**

`lib/media_centarr_web/live/settings_live/controls_logic.ex`:

```elixir
defmodule MediaCentarrWeb.SettingsLive.ControlsLogic do
  @moduledoc """
  Pure helpers for the Controls settings page.

  Extracted from the LiveView per ADR-030. Everything here is testable
  with `async: true` and has no side effects.
  """

  alias MediaCentarr.Controls.Catalog

  @category_labels %{
    navigation: "Navigation",
    zones: "Zones",
    playback: "Playback",
    system: "System"
  }

  @doc """
  Group a resolved bindings map (from `Controls.get/0`) into the
  display order [{category, [binding_view]}], where each binding_view
  merges catalog metadata with the resolved key/button.
  """
  def group_for_view(resolved) do
    Enum.map(Catalog.categories(), fn category ->
      views =
        Catalog.by_category(category)
        |> Enum.map(fn b ->
          slot = Map.get(resolved, b.id, %{key: nil, button: nil})

          %{
            id: b.id,
            category: category,
            name: b.name,
            description: b.description,
            key: slot.key,
            button: slot.button,
            scope: b.scope
          }
        end)

      {category, views}
    end)
  end

  @doc "Human label for a category atom."
  def category_label(category), do: Map.fetch!(@category_labels, category)

  @doc "Pretty-print a `KeyboardEvent.key` value for the keycap glyph."
  def display_key(nil), do: nil
  def display_key("ArrowUp"), do: "↑"
  def display_key("ArrowDown"), do: "↓"
  def display_key("ArrowLeft"), do: "←"
  def display_key("ArrowRight"), do: "→"
  def display_key("Escape"), do: "Esc"
  def display_key(" "), do: "Space"

  def display_key(key) when byte_size(key) == 1 do
    String.upcase(key)
  end

  def display_key(key), do: key

  @doc "Human label for a gamepad button index under the chosen glyph style."
  def display_button(nil, _), do: nil

  def display_button(0, "xbox"), do: "A"
  def display_button(1, "xbox"), do: "B"
  def display_button(2, "xbox"), do: "X"
  def display_button(3, "xbox"), do: "Y"
  def display_button(0, "playstation"), do: "✕"
  def display_button(1, "playstation"), do: "○"
  def display_button(2, "playstation"), do: "□"
  def display_button(3, "playstation"), do: "△"
  def display_button(4, "xbox"), do: "LB"
  def display_button(5, "xbox"), do: "RB"
  def display_button(4, "playstation"), do: "L1"
  def display_button(5, "playstation"), do: "R1"
  def display_button(12, _), do: "D-Pad ↑"
  def display_button(13, _), do: "D-Pad ↓"
  def display_button(14, _), do: "D-Pad ←"
  def display_button(15, _), do: "D-Pad →"
  def display_button(9, "xbox"), do: "Menu"
  def display_button(9, "playstation"), do: "Options"
  def display_button(n, _) when is_integer(n), do: "Btn #{n}"

  @doc """
  If putting `value` on `id` (for `kind`) would conflict with an existing
  binding, return the id of the one that would be displaced. Otherwise nil.
  """
  def pending_swap(resolved, id, value, kind) do
    extractor = extractor_for(kind)

    Enum.find_value(resolved, fn {other_id, slot} ->
      cond do
        other_id == id -> nil
        extractor.(slot) == value -> other_id
        true -> nil
      end
    end)
  end

  defp extractor_for(:keyboard), do: & &1.key
  defp extractor_for(:gamepad), do: & &1.button
end
```

- [ ] **Step 4: Run test — expect pass**

Run: `mix test test/media_centarr_web/live/settings_live/controls_logic_test.exs`
Expected: 23 tests passing.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): ControlsLogic pure helpers for view grouping and display"
```

---

## Task 7: `SettingsLive.Controls` section component

**Files:**
- Create: `lib/media_centarr_web/live/settings_live/controls.ex`
- Create: `test/media_centarr_web/live/settings_live/controls_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centarr_web/live/settings_live/controls_test.exs`:

```elixir
defmodule MediaCentarrWeb.SettingsLive.ControlsTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Controls

  describe "mount" do
    test "renders all bindings grouped by category", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")
      rendered = render(view)

      assert rendered =~ "Controls"
      assert rendered =~ "Navigation"
      assert rendered =~ "Zones"
      assert rendered =~ "Playback"
      assert rendered =~ "System"
      assert rendered =~ "Move up"
      assert rendered =~ "Toggle console"
    end
  end

  describe "remap flow" do
    test "clicking remap enters listening state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      html =
        view
        |> element(~s|button[phx-click="controls:listen"][phx-value-id="navigate_up"][phx-value-kind="keyboard"]|)
        |> render_click()

      assert html =~ "data-listening=\"true\""
    end

    test "controls:bind event persists and broadcasts", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> render_hook("controls:bind", %{"id" => "play", "kind" => "keyboard", "value" => "k"})

      assert_receive {:controls_changed, map}
      assert map[:play].key == "k"
    end

    test "controls:cancel leaves state unchanged", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:listen"][phx-value-id="navigate_up"][phx-value-kind="keyboard"]|)
      |> render_click()

      rendered =
        view
        |> render_hook("controls:cancel", %{})

      refute rendered =~ "data-listening=\"true\""
    end
  end

  describe "clear and reset" do
    test "clicking clear unsets the binding", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:clear"][phx-value-id="back"][phx-value-kind="keyboard"]|)
      |> render_click()

      assert_receive {:controls_changed, map}
      assert map[:back].key == nil
    end

    test "reset_all button restores defaults", %{conn: conn} do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      :ok = Controls.subscribe()
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:reset_all"]|)
      |> render_click()

      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "ArrowUp"
    end

    test "reset_category button restores that category only", %{conn: conn} do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:play, :keyboard, "k")
      :ok = Controls.subscribe()
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:reset_category"][phx-value-category="navigation"]|)
      |> render_click()

      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "ArrowUp"
      assert map[:play].key == "k"
    end
  end

  describe "glyph style toggle" do
    test "switches between xbox and playstation", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:set_glyph"][phx-value-style="playstation"]|)
      |> render_click()

      assert_receive {:controls_changed, _}
      assert Controls.glyph_style() == "playstation"
    end
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/media_centarr_web/live/settings_live/controls_test.exs`
Expected: route `/settings?section=controls` renders default content (section not found), tests fail assertions.

- [ ] **Step 3: Implement the section component**

`lib/media_centarr_web/live/settings_live/controls.ex`:

```elixir
defmodule MediaCentarrWeb.SettingsLive.Controls do
  @moduledoc """
  The Controls section of the Settings page.

  Renders the full binding table grouped by category. The parent
  `SettingsLive` delegates to `render/1` and hosts the event handlers
  that call into `MediaCentarr.Controls`.
  """

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.SettingsLive.ControlsLogic

  attr :bindings, :map, required: true
  attr :glyph_style, :string, required: true
  attr :listening, :any, required: true, doc: "{kind, id} tuple or nil"

  def render(assigns) do
    assigns = assign(assigns, :groups, ControlsLogic.group_for_view(assigns.bindings))

    ~H"""
    <div data-page="controls" class="controls-page max-w-4xl">
      <div class="flex items-end justify-between mb-2">
        <div>
          <h2 class="text-2xl font-semibold">Controls</h2>
          <p class="text-base-content/60 mt-1">Customize keyboard and gamepad bindings.</p>
        </div>
        <button phx-click="controls:reset_all" class="btn btn-sm btn-ghost">
          Reset all to defaults
        </button>
      </div>

      <div class="flex items-center gap-2 mb-6">
        <span class="text-xs uppercase tracking-wide text-base-content/60">Glyphs:</span>
        <div class="join">
          <button
            phx-click="controls:set_glyph"
            phx-value-style="xbox"
            class={"join-item btn btn-xs " <> if(@glyph_style == "xbox", do: "btn-primary", else: "btn-ghost")}>
            Xbox
          </button>
          <button
            phx-click="controls:set_glyph"
            phx-value-style="playstation"
            class={"join-item btn btn-xs " <> if(@glyph_style == "playstation", do: "btn-primary", else: "btn-ghost")}>
            PlayStation
          </button>
        </div>
      </div>

      <div class="h-px bg-base-300 mb-6"></div>

      <div :for={{category, views} <- @groups} class="controls-category mb-8">
        <div class="flex items-baseline justify-between mb-3 pb-2 border-b border-dashed border-base-300">
          <h3 class="text-lg font-semibold">
            {ControlsLogic.category_label(category)}
            <span class="text-xs text-base-content/60 ml-2 uppercase tracking-wide">
              {length(views)} bindings
            </span>
          </h3>
          <button
            phx-click="controls:reset_category"
            phx-value-category={Atom.to_string(category)}
            class="text-xs text-base-content/60 hover:text-primary">
            Reset {ControlsLogic.category_label(category)}
          </button>
        </div>

        <div class="flex flex-col gap-2">
          <div
            :for={view <- views}
            class="controls-row"
            data-listening={listening?(@listening, view.id)}>

            <div class="controls-row-label">
              <div class="font-semibold">{view.name}</div>
              <div class="text-sm text-base-content/60">{view.description}</div>
            </div>

            <div class="controls-row-slots">
              <.slot_view
                kind={:keyboard}
                id={view.id}
                glyph={ControlsLogic.display_key(view.key)}
                listening={listening_slot?(@listening, view.id, :keyboard)} />

              <span class="controls-row-sep">·</span>

              <.slot_view
                kind={:gamepad}
                id={view.id}
                glyph={ControlsLogic.display_button(view.button, @glyph_style)}
                listening={listening_slot?(@listening, view.id, :gamepad)}
                gamepad_available={@gamepad_available || false} />
            </div>

            <div class="controls-row-actions">
              <button
                phx-click="controls:listen"
                phx-value-id={Atom.to_string(view.id)}
                phx-value-kind="keyboard"
                class="controls-icon-btn"
                title="Remap key">
                <.icon name="hero-pencil" class="w-4 h-4" />
              </button>
              <button
                phx-click="controls:clear"
                phx-value-id={Atom.to_string(view.id)}
                phx-value-kind="keyboard"
                class="controls-icon-btn danger"
                title="Clear key">
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>

            <div :if={listening?(@listening, view.id)} class="controls-listen-hint">
              Press any key to bind {view.name}
              <span class="text-base-content/60 ml-3">Esc to cancel</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :id, :atom, required: true
  attr :glyph, :string, default: nil
  attr :listening, :boolean, default: false
  attr :gamepad_available, :boolean, default: true

  defp slot_view(assigns) do
    ~H"""
    <div class={"controls-slot controls-slot-#{@kind}"}>
      <span class="controls-slot-label">{if @kind == :keyboard, do: "Key", else: "Pad"}</span>
      <span class={"controls-keycap " <>
        if(@listening, do: "listening ", else: "") <>
        if(is_nil(@glyph), do: "empty", else: "")}>
        {cond do
          @listening -> "press…"
          is_nil(@glyph) -> "unset"
          true -> @glyph
        end}
      </span>
    </div>
    """
  end

  defp listening?(nil, _), do: false
  defp listening?({_kind, id}, id), do: true
  defp listening?(_, _), do: false

  defp listening_slot?(nil, _, _), do: false
  defp listening_slot?({kind, id}, id, kind), do: true
  defp listening_slot?(_, _, _), do: false
end
```

- [ ] **Step 4: Wire into `SettingsLive`**

Edit `lib/media_centarr_web/live/settings_live.ex`:

1. Add to alias list near the top:

```elixir
alias MediaCentarr.Controls
alias MediaCentarrWeb.SettingsLive.Controls, as: ControlsSection
```

2. Add `"controls"` to `@sections` — insert between `preferences` and `library`:

```elixir
@sections [
  %{id: "system", label: "System", group: :system},
  %{id: "services", label: "Services", group: :general},
  %{id: "preferences", label: "Preferences", group: :general},
  %{id: "controls", label: "Controls", group: :general},
  %{id: "library", label: "Library", group: :media},
  # ... rest unchanged
]
```

3. In `mount/3` after the existing `connected?(socket)` block, add:

```elixir
if connected?(socket), do: Controls.subscribe()
```

4. In the mount `assign` pipeline, add:

```elixir
|> assign(bindings: Controls.get())
|> assign(glyph_style: Controls.glyph_style())
|> assign(listening: nil)
```

5. Add a new `section_content/1` clause before the system clause (order doesn't matter functionally):

```elixir
defp section_content(%{active_section: "controls"} = assigns) do
  ~H"""
  <ControlsSection.render bindings={@bindings} glyph_style={@glyph_style} listening={@listening} />
  """
end
```

6. Add `handle_info` clause for broadcasts:

```elixir
@impl true
def handle_info({:controls_changed, map}, socket) do
  {:noreply,
   socket
   |> assign(bindings: map)
   |> assign(glyph_style: Controls.glyph_style())
   |> assign(listening: nil)
   |> push_event("controls:updated", %{
     keyboard: keyboard_for_client(map),
     gamepad: gamepad_for_client(map)
   })}
end
```

7. Add `handle_event` clauses:

```elixir
def handle_event("controls:listen", %{"id" => id, "kind" => kind}, socket) do
  {:noreply,
   socket
   |> assign(listening: {String.to_atom(kind), String.to_existing_atom(id)})
   |> push_event("controls:listen", %{kind: kind})}
end

def handle_event("controls:cancel", _params, socket) do
  {:noreply, assign(socket, listening: nil)}
end

def handle_event(
      "controls:bind",
      %{"id" => id, "kind" => kind, "value" => value},
      socket
    ) do
  id_atom = String.to_existing_atom(id)
  kind_atom = String.to_atom(kind)
  normalized = normalize_bind_value(kind_atom, value)

  case Controls.put(id_atom, kind_atom, normalized) do
    {:ok, _} -> {:noreply, socket}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to bind key")}
  end
end

def handle_event("controls:clear", %{"id" => id, "kind" => kind}, socket) do
  :ok = Controls.clear(String.to_existing_atom(id), String.to_atom(kind))
  {:noreply, socket}
end

def handle_event("controls:reset_all", _params, socket) do
  :ok = Controls.reset_all()
  {:noreply, socket}
end

def handle_event("controls:reset_category", %{"category" => cat}, socket) do
  :ok = Controls.reset_category(String.to_existing_atom(cat))
  {:noreply, socket}
end

def handle_event("controls:set_glyph", %{"style" => style}, socket) do
  :ok = Controls.set_glyph_style(style)
  {:noreply, socket}
end

defp normalize_bind_value(:keyboard, value) when is_binary(value), do: value
defp normalize_bind_value(:gamepad, value) when is_integer(value), do: value
defp normalize_bind_value(:gamepad, value) when is_binary(value), do: String.to_integer(value)

defp keyboard_for_client(map) do
  map
  |> Enum.flat_map(fn {id, %{key: k}} -> if k, do: [{k, id}], else: [] end)
  |> Map.new()
end

defp gamepad_for_client(map) do
  map
  |> Enum.flat_map(fn {id, %{button: b}} -> if b, do: [{b, id}], else: [] end)
  |> Map.new()
end
```

- [ ] **Step 5: Run tests — expect pass**

Run: `mix test test/media_centarr_web/live/settings_live/controls_test.exs`
Expected: 7 tests passing.

- [ ] **Step 6: Commit**

```bash
jj desc -m "feat(controls): Settings > Controls page rendering and event handlers"
```

---

## Task 8: Scoped CSS — keycap, gamepad glyph, listening state

**Files:**
- Create: `assets/css/controls.css`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Create `assets/css/controls.css`**

```css
/*
 * Controls page — scoped styles for keycap glyphs, gamepad glyphs, and
 * listening state. Only applies within [data-page="controls"].
 *
 * Color values use daisyUI tokens (base-100, base-300, primary) so they
 * adapt to any dark theme. Keycap-specific look is parameterized by
 * three custom props defined globally under [data-theme].
 */

:root {
  --keycap-top: oklch(34% 0.018 264);
  --keycap-face: oklch(27% 0.019 264);
  --keycap-edge: oklch(15% 0.013 264);
  --keycap-glow: oklch(62% 0.16 250);
}

[data-page="controls"] .controls-row {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 1rem;
  align-items: center;
  padding: 0.75rem 0.875rem;
  border-radius: 0.625rem;
  background: oklch(from var(--color-base-100) l a b / 1);
  border: 1px solid transparent;
  transition: border-color 0.15s ease, background 0.15s ease;
}

[data-page="controls"] .controls-row:hover {
  border-color: oklch(from var(--color-base-300) l a b / 1);
  background: oklch(from var(--color-base-200) l a b / 1);
}

[data-page="controls"] .controls-row[data-listening="true"] {
  border-color: var(--keycap-glow);
}

[data-page="controls"] .controls-row-slots {
  display: flex;
  gap: 1rem;
  align-items: center;
}

[data-page="controls"] .controls-slot {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}

[data-page="controls"] .controls-slot-label {
  color: oklch(from var(--color-base-content) l a b / 0.6);
  font-size: 0.6875rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
}

[data-page="controls"] .controls-row-sep {
  color: oklch(from var(--color-base-300) l a b / 1);
  font-size: 0.6875rem;
  letter-spacing: 0.15em;
}

[data-page="controls"] .controls-keycap {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 2.75rem;
  height: 2.5rem;
  padding: 0 0.75rem;
  border-radius: 0.4375rem;
  background: linear-gradient(180deg, var(--keycap-top) 0%, var(--keycap-face) 100%);
  border: 1px solid var(--keycap-edge);
  box-shadow: 0 2px 0 var(--keycap-edge), 0 6px 12px rgba(0, 0, 0, 0.5);
  font: 600 0.8125rem/1 "SF Mono", ui-monospace, Menlo, Consolas, monospace;
  letter-spacing: 0.02em;
  color: var(--color-base-content);
}

[data-page="controls"] .controls-keycap.empty {
  background: transparent;
  box-shadow: none;
  border-style: dashed;
  color: oklch(from var(--color-base-content) l a b / 0.55);
  font-style: italic;
}

[data-page="controls"] .controls-keycap.listening {
  border-color: var(--keycap-glow);
  color: var(--keycap-glow);
  animation: controls-pulse 1.2s ease-in-out infinite;
  background: linear-gradient(180deg, var(--keycap-top) 0%, var(--keycap-face) 100%);
}

@keyframes controls-pulse {
  0%, 100% {
    box-shadow: 0 0 0 0 oklch(from var(--keycap-glow) l a b / 0.35),
                0 2px 0 var(--keycap-edge), 0 6px 12px rgba(0, 0, 0, 0.5);
  }
  50% {
    box-shadow: 0 0 0 6px oklch(from var(--keycap-glow) l a b / 0),
                0 2px 0 var(--keycap-edge), 0 6px 12px rgba(0, 0, 0, 0.5);
  }
}

[data-page="controls"] .controls-row-actions {
  display: flex;
  gap: 0.25rem;
  opacity: 0;
  transition: opacity 0.15s ease;
}

[data-page="controls"] .controls-row:hover .controls-row-actions,
[data-page="controls"] .controls-row[data-listening="true"] .controls-row-actions {
  opacity: 1;
}

[data-page="controls"] .controls-icon-btn {
  width: 1.75rem;
  height: 1.75rem;
  border-radius: 0.375rem;
  border: 1px solid oklch(from var(--color-base-300) l a b / 1);
  background: transparent;
  color: oklch(from var(--color-base-content) l a b / 0.6);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.15s ease;
}

[data-page="controls"] .controls-icon-btn:hover {
  color: var(--color-base-content);
  background: oklch(from var(--color-base-200) l a b / 1);
}

[data-page="controls"] .controls-icon-btn.danger:hover {
  color: var(--color-error);
}

[data-page="controls"] .controls-listen-hint {
  grid-column: 1 / -1;
  padding: 0.625rem 0.875rem;
  margin-top: 0.625rem;
  background: linear-gradient(90deg,
    oklch(from var(--keycap-glow) l a b / 0.08),
    transparent);
  border-left: 3px solid var(--keycap-glow);
  border-radius: 0.375rem;
  color: var(--keycap-glow);
  font-size: 0.8125rem;
}
```

- [ ] **Step 2: Import in `app.css`**

Edit `assets/css/app.css` — add near the other imports (after the `@source` lines and `@plugin` blocks):

```css
@import "./controls.css";
```

- [ ] **Step 3: Verify build**

Run: `mix assets.build`
Expected: clean build, no CSS errors.

- [ ] **Step 4: Manually verify page renders**

Start the dev server (`mix phx.server`), navigate to `/settings?section=controls`, confirm:
- All four categories render with the correct number of rows
- Hovering a row reveals pencil + X icons
- Keycap glyphs appear with the raised look shown in the mockup
- Xbox/PlayStation toggle switches labels

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): scoped CSS for keycap, gamepad glyph, and listening states"
```

---

## Task 9: JS bridge — one-shot capture + hot-swap

**Files:**
- Create: `assets/js/input/controls_bridge.js`
- Create: `assets/js/input/__tests__/controls_bridge.test.js`

- [ ] **Step 1: Write the failing test**

`assets/js/input/__tests__/controls_bridge.test.js`:

```javascript
import { describe, test, expect, beforeEach, mock } from "bun:test"
import { ControlsBridge } from "../controls_bridge.js"

function makeEvent(key) {
  return {
    key,
    preventDefault: mock(() => {}),
    stopPropagation: mock(() => {}),
  }
}

function makeWindow() {
  const listeners = new Map()
  return {
    addEventListener: mock((type, fn, opts) => {
      const list = listeners.get(type) ?? []
      list.push({ fn, opts })
      listeners.set(type, list)
    }),
    removeEventListener: mock((type, fn) => {
      const list = listeners.get(type) ?? []
      listeners.set(type, list.filter((l) => l.fn !== fn))
    }),
    dispatch(type, event) {
      const list = [...(listeners.get(type) ?? [])]
      for (const { fn, opts } of list) {
        fn(event)
        if (opts?.once) {
          this.removeEventListener(type, fn)
        }
      }
    },
  }
}

describe("ControlsBridge", () => {
  let bridge, window, pushEvent

  beforeEach(() => {
    window = makeWindow()
    pushEvent = mock(() => {})
    bridge = new ControlsBridge({ window, pushEvent })
  })

  test("listenKeyboard installs one-shot capture keydown listener", () => {
    bridge.listenKeyboard()
    expect(window.addEventListener).toHaveBeenCalledWith(
      "keydown",
      expect.any(Function),
      expect.objectContaining({ capture: true, once: true })
    )
  })

  test("keyboard capture pushes controls:bind with event.key and id/kind", () => {
    bridge.listenKeyboard({ id: "select" })
    const event = makeEvent("F2")
    window.dispatch("keydown", event)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(event.stopPropagation).toHaveBeenCalled()
    expect(pushEvent).toHaveBeenCalledWith("controls:bind", {
      id: "select",
      kind: "keyboard",
      value: "F2",
    })
  })

  test("Escape during listen pushes controls:cancel and not controls:bind", () => {
    bridge.listenKeyboard({ id: "select" })
    const event = makeEvent("Escape")
    window.dispatch("keydown", event)

    expect(pushEvent).toHaveBeenCalledWith("controls:cancel", {})
    const bindCalls = pushEvent.mock.calls.filter((c) => c[0] === "controls:bind")
    expect(bindCalls.length).toBe(0)
  })

  test("updateMaps emits a window event for the input system to consume", () => {
    const listener = mock(() => {})
    window.addEventListener("input:rebindMaps", listener)
    bridge.updateMaps({ keyboard: { w: "navigate_up" }, gamepad: { 0: "select" } })

    expect(listener).toHaveBeenCalled()
    const payload = listener.mock.calls[0][0]
    expect(payload.detail).toEqual({
      keyboard: { w: "navigate_up" },
      gamepad: { 0: "select" },
    })
  })
})
```

- [ ] **Step 2: Run test — expect failure**

Run: `bun test assets/js/input/__tests__/controls_bridge.test.js`
Expected: module not found.

- [ ] **Step 3: Implement**

`assets/js/input/controls_bridge.js`:

```javascript
/**
 * ControlsBridge — connects the Controls LiveView to the input system.
 *
 * Two jobs:
 *   1. One-shot capture — when the LiveView enters listening state, install
 *      a capture-phase keydown (or gamepad button) listener that fires
 *      exactly once, then pushes the captured value back as "controls:bind".
 *   2. Hot-swap — on `phx:controls:updated` from the server, dispatch a
 *      DOM event that the input system (orchestrator/sources) listens for
 *      to rebuild its key/button maps without a page reload.
 *
 * The bridge is instantiated inside the LiveView hook's mounted() and its
 * methods are invoked from LiveView handleEvent callbacks.
 */

export class ControlsBridge {
  /**
   * @param {Object} config
   * @param {Object} config.window - Window (or test double) with addEventListener
   * @param {Function} config.pushEvent - (eventName, payload) => void — LiveView hook's pushEvent
   */
  constructor(config) {
    this._window = config.window
    this._pushEvent = config.pushEvent
  }

  /**
   * Begin listening for the next keyboard event. Escape cancels.
   * @param {{id: string}} ctx
   */
  listenKeyboard(ctx = {}) {
    const handler = (event) => {
      event.preventDefault()
      event.stopPropagation()

      if (event.key === "Escape") {
        this._pushEvent("controls:cancel", {})
        return
      }

      this._pushEvent("controls:bind", {
        id: ctx.id,
        kind: "keyboard",
        value: event.key,
      })
    }

    this._window.addEventListener("keydown", handler, { capture: true, once: true })
  }

  /**
   * Begin listening for the next gamepad button edge. External polling
   * from the existing GamepadSource emits a custom event that we listen
   * to — avoiding duplicate polling loops.
   *
   * @param {{id: string}} ctx
   */
  listenGamepad(ctx = {}) {
    const handler = (event) => {
      const button = event.detail?.button
      this._pushEvent("controls:bind", {
        id: ctx.id,
        kind: "gamepad",
        value: button,
      })
    }

    this._window.addEventListener("input:gamepadCapture", handler, { once: true })
  }

  /**
   * Dispatch a DOM event that the input system's orchestrator listens for
   * to rebuild its key and button maps.
   *
   * @param {{keyboard: Object<string, string>, gamepad: Object<number, string>}} maps
   */
  updateMaps(maps) {
    this._window.dispatchEvent(new CustomEvent("input:rebindMaps", { detail: maps }))
  }
}
```

- [ ] **Step 4: Run test — expect pass**

Run: `bun test assets/js/input/__tests__/controls_bridge.test.js`
Expected: 4 tests passing.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(controls): JS bridge for one-shot capture and hot-swap"
```

---

## Task 10: Wire bindings into `createInputHook` and layout

**Files:**
- Modify: `assets/js/input/index.js`
- Modify: `lib/media_centarr_web/components/layouts.ex`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Update `layouts.ex` to inject bindings**

Edit `lib/media_centarr_web/components/layouts.ex` at line 36 (the `#input-system` div):

Find:

```elixir
<div id="input-system" class="flex min-h-screen" phx-hook="InputSystem">
```

Replace with:

```elixir
<div
  id="input-system"
  class="flex min-h-screen"
  phx-hook="InputSystem"
  data-input-bindings={Jason.encode!(input_bindings())}
  data-global-bindings={Jason.encode!(global_bindings())}>
```

Add these helpers at the bottom of the module (inside `defmodule MediaCentarrWeb.Layouts do`):

```elixir
defp input_bindings do
  resolved = MediaCentarr.Controls.get()
  catalog = MediaCentarr.Controls.Catalog.all()
  input_scope_ids = for b <- catalog, b.scope == :input_system, do: b.id

  %{
    keyboard:
      Enum.reduce(input_scope_ids, %{}, fn id, acc ->
        case resolved[id].key do
          nil -> acc
          key -> Map.put(acc, key, Atom.to_string(id))
        end
      end),
    gamepad:
      Enum.reduce(input_scope_ids, %{}, fn id, acc ->
        case resolved[id].button do
          nil -> acc
          btn -> Map.put(acc, Integer.to_string(btn), Atom.to_string(id))
        end
      end)
  }
end

defp global_bindings do
  resolved = MediaCentarr.Controls.get()
  catalog = MediaCentarr.Controls.Catalog.all()
  global_scope_ids = for b <- catalog, b.scope == :global, do: b.id

  Enum.reduce(global_scope_ids, %{}, fn id, acc ->
    case resolved[id].key do
      nil -> acc
      key -> Map.put(acc, Atom.to_string(id), key)
    end
  end)
end
```

- [ ] **Step 2: Update `assets/js/input/index.js` to consume bindings**

Replace the entire contents with:

```javascript
/**
 * App entry point — imports the framework core and app config,
 * creates the LiveView hook for the input system.
 *
 * Reads `data-input-bindings` from the hook element at mount, builds
 * key and button maps, and listens for `input:rebindMaps` events to
 * hot-swap maps without a full remount.
 */

import { Orchestrator, createDomReader, createDomWriter, KeyboardSource, GamepadSource } from "./core/index.js"
import { Action } from "./core/actions.js"
import { inputConfig } from "./config.js"
import { ControlsBridge } from "./controls_bridge.js"

const BROWSER_GLOBALS = {
  get document() { return document },
  get sessionStorage() { return sessionStorage },
  get requestAnimationFrame() { return requestAnimationFrame.bind(window) },
  get cancelAnimationFrame() { return cancelAnimationFrame.bind(window) },
  get getGamepads() { return navigator.getGamepads?.bind(navigator) ?? (() => []) },
}

function actionForId(idStr) {
  switch (idStr) {
    case "navigate_up": return Action.NAVIGATE_UP
    case "navigate_down": return Action.NAVIGATE_DOWN
    case "navigate_left": return Action.NAVIGATE_LEFT
    case "navigate_right": return Action.NAVIGATE_RIGHT
    case "select": return Action.SELECT
    case "back": return Action.BACK
    case "clear": return Action.CLEAR
    case "play": return Action.PLAY
    case "zone_next": return Action.ZONE_NEXT
    case "zone_prev": return Action.ZONE_PREV
    default: return null
  }
}

function buildKeyMap(keyboardBindings) {
  const keyMap = {}
  for (const [key, idStr] of Object.entries(keyboardBindings ?? {})) {
    const action = actionForId(idStr)
    if (action) keyMap[key] = action
  }
  return keyMap
}

function buildButtonMap(gamepadBindings) {
  const buttonMap = {}
  for (const [btnStr, idStr] of Object.entries(gamepadBindings ?? {})) {
    const action = actionForId(idStr)
    if (action) buttonMap[Number(btnStr)] = action
  }
  return buttonMap
}

function readBindings(el) {
  try {
    return JSON.parse(el.dataset.inputBindings ?? "{}")
  } catch {
    return {}
  }
}

export function createInputHook() {
  let orchestrator = null
  let keyboardSource = null
  let gamepadSource = null

  const rebind = (maps) => {
    if (keyboardSource) keyboardSource._keyMap = buildKeyMap(maps.keyboard)
    if (gamepadSource) gamepadSource._buttonMap = buildButtonMap(maps.gamepad)
  }

  const handleRebind = (event) => rebind(event.detail)

  return {
    mounted() {
      const bindings = readBindings(this.el)
      const keyMap = buildKeyMap(bindings.keyboard)
      const buttonMap = buildButtonMap(bindings.gamepad)

      const reader = createDomReader(inputConfig)
      const writer = createDomWriter(inputConfig)

      orchestrator = new Orchestrator({
        reader,
        writer,
        globals: BROWSER_GLOBALS,
        sources: [
          (callbacks, globals) => {
            keyboardSource = new KeyboardSource({
              document: globals.document,
              keyMap,
              ...callbacks,
            })
            return keyboardSource
          },
          (callbacks, globals) => {
            gamepadSource = new GamepadSource({
              getGamepads: globals.getGamepads,
              requestAnimationFrame: globals.requestAnimationFrame,
              cancelAnimationFrame: globals.cancelAnimationFrame,
              addEventListener: window.addEventListener.bind(window),
              removeEventListener: window.removeEventListener.bind(window),
              onControllerChanged: (type) => writer.setControllerType(type),
              buttonMap,
              ...callbacks,
            })
            return gamepadSource
          },
        ],
        ...inputConfig,
      })
      orchestrator.start(this)

      this.bridge = new ControlsBridge({
        window,
        pushEvent: (ev, payload) => this.pushEvent(ev, payload),
      })

      this.handleEvent("controls:listen", ({ kind, id }) => {
        if (kind === "keyboard") this.bridge.listenKeyboard({ id })
        if (kind === "gamepad") this.bridge.listenGamepad({ id })
      })

      this.handleEvent("controls:updated", (maps) => this.bridge.updateMaps(maps))

      window.addEventListener("input:rebindMaps", handleRebind)
    },

    updated() {
      orchestrator?.onViewChanged()
    },

    destroyed() {
      window.removeEventListener("input:rebindMaps", handleRebind)
      orchestrator?.destroy()
      orchestrator = null
      keyboardSource = null
      gamepadSource = null
    },
  }
}
```

- [ ] **Step 3: Add `buttonMap` support to `GamepadSource`**

Check if `GamepadSource` already accepts `buttonMap` — if not, add it symmetrically to how `KeyboardSource` accepts `keyMap`.

Run: `grep -n 'buttonMap\|_buttonMap' assets/js/input/core/gamepad.js`

If no match, edit `assets/js/input/core/gamepad.js` — in constructor store `this._buttonMap = config.buttonMap ?? DEFAULT_BUTTON_MAP` and use it in the edge-detect dispatch. (Details depend on the existing constructor; the change mirrors `KeyboardSource`.)

- [ ] **Step 4: Update `assets/js/app.js` backtick listener**

Find lines ~74-90 (the backtick listener) and change it to read from `data-global-bindings`:

```javascript
// Global bindings (backtick, etc.). Reads the current binding from the
// root layout's data-global-bindings attr and listens for updates.
let globalBindings = parseGlobalBindings()

function parseGlobalBindings() {
  try {
    return JSON.parse(document.getElementById("input-system")?.dataset?.globalBindings ?? "{}")
  } catch {
    return {}
  }
}

document.addEventListener(
  "keydown",
  (event) => {
    const tag = event.target?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA") return
    if (event.target?.closest?.("[data-captures-keys]")) return

    const consoleKey = globalBindings.toggle_console
    if (consoleKey && event.key === consoleKey) {
      event.preventDefault()
      event.stopPropagation()
      const live = document.querySelector("#console-live")
      if (live) live.dispatchEvent(new CustomEvent("toggle-console", { bubbles: true }))
    }
  },
  { capture: true }
)

window.addEventListener("input:rebindMaps", () => {
  globalBindings = parseGlobalBindings()
})
```

(Adapt the dispatch target to however the existing code actually toggles the console — read the current `app.js` lines first and keep the toggle mechanism identical, only change the key source.)

- [ ] **Step 5: Run JS tests**

Run: `bun test assets/js/input/`
Expected: all passing. If `index.test.js` fails because of the new bindings plumbing, update the mock to include `dataset.inputBindings = "{}"` on the hook element.

- [ ] **Step 6: Run Elixir tests**

Run: `mix test`
Expected: all passing.

- [ ] **Step 7: Manual verification**

- Start dev server.
- Press `` ` `` — console opens (default still works).
- Visit `/settings?section=controls`, rebind `Move up` from `ArrowUp` to `w`.
- Close settings, go to a library page. `w` moves selection up; `ArrowUp` does nothing.
- Reopen settings, reset all. `ArrowUp` works again.

- [ ] **Step 8: Commit**

```bash
jj desc -m "feat(controls): runtime-configurable keyboard and gamepad bindings via layout data attrs"
```

---

## Task 11: Wiki updates

**Files (in the wiki repo `../media-centarr.wiki/`):**
- Modify: `Keyboard-and-Gamepad.md`
- Modify: `Keyboard-Shortcuts.md`

- [ ] **Step 1: Switch to the wiki repo**

```bash
cd ~/src/media-centarr/media-centarr.wiki
jj st
```

- [ ] **Step 2: Update `Keyboard-and-Gamepad.md`**

Append a new section near the top or in an appropriate spot:

```markdown
## Customizing bindings

Every keyboard key and gamepad button listed below can be customized at
**Settings → Controls**. The Controls page doubles as a cheat sheet —
every binding is visible there regardless of whether you're editing.

To rebind:

1. Open Settings → Controls
2. Hover the binding you want to change
3. Click the pencil icon on the Key (or Pad) slot
4. Press the new key (or gamepad button) you want to bind
5. If the key was already used, the two bindings swap automatically

Press Escape during listening mode to cancel. Click the X icon to clear
a binding (leave it unbound).

Gamepad glyphs (A/B/X/Y vs ✕/○/□/△) are display-only — toggle between
Xbox and PlayStation style at the top of the Controls page.
```

Also: update any claim in the existing file that suggests bindings are hardcoded.

- [ ] **Step 3: Update `Keyboard-Shortcuts.md`**

Replace any hand-maintained binding table with:

```markdown
> **The authoritative list lives in the app** at Settings → Controls.
> The defaults below are for reference only.

### Navigation
| Action | Key | Gamepad |
|---|---|---|
| Move up | ↑ | D-Pad ↑ |
| Move down | ↓ | D-Pad ↓ |
| Move left | ← | D-Pad ← |
| Move right | → | D-Pad → |
| Select | Enter | A / ✕ |
| Back | Esc | B / ○ |
| Clear | Backspace | Y / △ |

### Zones
| Action | Key | Gamepad |
|---|---|---|
| Next zone | ] | RB / R1 |
| Previous zone | [ | LB / L1 |

### Playback
| Action | Key | Gamepad |
|---|---|---|
| Play | P | Menu / Options |

### System
| Action | Key | Gamepad |
|---|---|---|
| Toggle console | ` | (unset) |
```

- [ ] **Step 4: Commit and push the wiki**

```bash
jj desc -m "wiki: document Settings > Controls and customization flow"
jj bookmark set master -r @
jj git push
```

- [ ] **Step 5: Return to app repo**

```bash
cd ~/src/media-centarr/media-centarr
```

---

## Task 12: Precommit sweep

**Files:** all changed above.

- [ ] **Step 1: Run precommit**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit
```

Expected: clean — compile (no warnings), format, credo, deps.audit, sobelow, test all passing.

- [ ] **Step 2: Fix any issues surfaced**

Common things the precommit tools may flag:

- **Credo `PredicateNaming`** — function ending in `?` must be a boolean predicate (not macro). Naming in this plan already follows the rule (`listening?/2`, `listening_slot?/3`).
- **Credo `NoAbbreviatedNames`** — all vars in this plan use full words (`bindings`, `overrides`, not `b` or `ovr`).
- **Credo `ContextSubscribeFacade`** — LiveViews use `Controls.subscribe()`, which is the facade pattern.
- **Boundary** — `MediaCentarr.Controls` declares `use Boundary, deps: [MediaCentarr.Settings], exports: [Binding, Catalog]`. If any LiveView subscribes to it, it needs `Controls` in its boundary deps. Follow compiler messages.
- **Warnings-as-errors** — fix any unused-variable / unused-alias reports.

- [ ] **Step 3: Commit any fixes**

```bash
jj desc -m "chore(controls): precommit fixes"
```

(Or squash into the task where the issue originated if it fits.)

---

## Plan Self-Review

### Spec coverage check

- ✅ Module layout — Tasks 2–7 cover `Binding`, `Catalog`, `Store`, `Controls`, `ControlsLogic`, `SettingsLive.Controls`.
- ✅ Binding catalog with 11 entries — Task 3.
- ✅ Data model & persistence (`controls.keyboard` / `controls.gamepad` / `controls.glyph_style`) — Task 4.
- ✅ Conflict detection and auto-swap — Task 5, with test for true-swap using resolved value.
- ✅ Clear without swap — Task 5.
- ✅ PubSub topic and facade subscribe — Task 1 + Task 5.
- ✅ JS integration (initial load, hot-swap, one-shot capture, global bindings) — Tasks 9 + 10.
- ✅ UI specification (page structure, row layout, listening state) — Task 7.
- ✅ Styling (scoped CSS, custom props for keycap, daisyUI tokens) — Task 8.
- ✅ Gamepad-disconnected behavior — passed through `@gamepad_available` assign to slot_view (Task 7). The actual "connected?" detection will be wired to the existing `GamepadSource.onControllerChanged` path — that plumbing already exists (see `layouts.ex` snippet) and is surfaced via JS `phx:lv:clientwrite`-style push; if the hook doesn't already surface it, add a `this.pushEvent("gamepad:connected", {connected: true/false})` in the `onControllerChanged` callback during Task 10 and hold the state in a new `assign(:gamepad_available, false)` defaulting to false.
- ✅ Testing — every task has tests.
- ✅ Wiki — Task 11.
- ✅ Rollout (backtick moves to attr-driven in the same PR) — Task 10.
- ✅ Glyph style toggle — Task 7.

### Placeholder scan

- No TBD / TODO references.
- `display_button` has a complete case coverage; the fallback `Btn #{n}` is real behavior, not a placeholder.
- `normalize_bind_value/2` handles all three real cases.

### Type consistency

- `Controls.put(id, :keyboard, value)` returns `{:ok, resolved()} | {:error, term()}`; `Controls.clear(id, kind)` returns `:ok | {:error, :unknown_id}`. LiveView handles both. Matches across tasks.
- `ControlsBridge.listenKeyboard({id})` → server `controls:bind` payload `{id, kind: "keyboard", value}` — matches `handle_event("controls:bind", %{"id" => ..., "kind" => ..., "value" => ...}, ...)`.
- Client-side `maps.keyboard` uses `{key_string: id_string}`; `maps.gamepad` uses `{button_number: id_string}` (after `readBindings` parse). `buildKeyMap` / `buildButtonMap` match.

### Scope check

Single page, one plan, ~12 tasks. Appropriate.
