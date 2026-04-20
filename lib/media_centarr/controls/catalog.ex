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
