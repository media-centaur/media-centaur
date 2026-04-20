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
        |> Enum.map(fn binding ->
          slot = Map.get(resolved, binding.id, %{key: nil, button: nil})

          %{
            id: binding.id,
            category: category,
            name: binding.name,
            description: binding.description,
            key: slot.key,
            button: slot.button,
            scope: binding.scope
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
