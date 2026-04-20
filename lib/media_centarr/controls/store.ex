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
