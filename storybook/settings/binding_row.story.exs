defmodule MediaCentaurWeb.Storybook.Settings.BindingRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.BindingRow.binding_row/1
  def render_source, do: :function

  @row %{
    id: :navigate_up,
    name: "Move up",
    description: "Focus the item above the current one",
    key_glyph: "↑",
    button_glyph: "D-Pad ↑",
    listen_event: "controls:listen",
    unbind_event: "controls:unbind"
  }

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. The two slots drop beneath the text block, left-aligned.
  @narrow ~s|<div class="w-[21rem] glass-surface rounded-xl p-5"><.psb-variation/></div>|

  def variations do
    [
      %Variation{
        id: :bound,
        description: "Both slots bound: two keycaps, each with a live Unbind.",
        attributes: @row
      },
      %Variation{
        id: :wide_glyphs,
        description: "The widest glyphs the catalog ships keep the keycaps one width.",
        attributes: %{
          @row
          | id: :clear,
            name: "Clear",
            description: "Clear the current search or filter",
            key_glyph: "Backspace",
            button_glyph: "Options"
        }
      },
      %Variation{
        id: :unbound_key,
        description: "An unbound slot: a dashed keycap and an inert Unbind that keeps its place.",
        attributes: %{@row | key_glyph: nil}
      },
      %Variation{
        id: :listening_key,
        description: "Listening for a key: the keycap pulses and the row says what to press.",
        attributes: Map.put(@row, :listening, :keyboard)
      },
      %Variation{
        id: :listening_pad,
        description: "Listening for a gamepad button.",
        attributes: Map.put(@row, :listening, :gamepad)
      },
      %Variation{
        id: :key_only,
        description:
          "On a remote player (the TV app): the Key slot alone, since the page starts no gamepad source.",
        attributes: Map.put(@row, :gamepad, false)
      },
      %Variation{
        id: :narrow,
        description: "A narrow card: the slots drop beneath the words.",
        template: @narrow,
        attributes: @row
      }
    ]
  end
end
