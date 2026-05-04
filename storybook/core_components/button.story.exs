defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
  @moduledoc """
  Seed story demonstrating the Media Centarr storybook philosophy.

  Covers every `<.button>` variant, each at default size; then a size matrix
  for the most common variants; then icon-only shapes. Mirrors the recipes
  documented in the `user-interface` skill — keep them in sync.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.button/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :variants,
        description: "All variants at default (md) size",
        variations:
          for variant <- ~w(primary secondary action info risky danger dismiss neutral outline) do
            %Variation{
              id: String.to_atom(variant),
              attributes: %{variant: variant},
              slots: [label_for(variant)]
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Size axis (xs / sm / md / lg) on the primary variant",
        variations:
          for size <- ~w(xs sm md lg) do
            %Variation{
              id: String.to_atom("primary_" <> size),
              attributes: %{variant: "primary", size: size},
              slots: ["Play"]
            }
          end
      },
      %VariationGroup{
        id: :hero_pair,
        description: "Standard hero CTA pair — Play + More info ([UIDR-003])",
        variations: [
          %Variation{
            id: :play,
            attributes: %{variant: "primary", size: "lg"},
            slots: ["Play"]
          },
          %Variation{
            id: :more_info,
            description:
              ~s(Hero variant — `class="text-white"` because the button sits over a backdrop image. Without it the soft-primary text reads blue, which doesn't match the home hero's actual appearance.),
            attributes: %{variant: "secondary", size: "lg", class: "text-white"},
            slots: ["More info"]
          }
        ]
      },
      %VariationGroup{
        id: :destructive,
        description: "Destructive actions — soft red, never solid `btn-error`",
        variations: [
          %Variation{
            id: :delete,
            attributes: %{variant: "danger", size: "sm"},
            slots: ["Delete"]
          },
          %Variation{
            id: :inline_trash,
            attributes: %{variant: "destructive_inline", shape: "circle", size: "sm"},
            slots: [icon_slot("hero-trash-mini")]
          }
        ]
      },
      %VariationGroup{
        id: :icon_only,
        description: "Icon-only shapes — circle and square wrappers",
        variations:
          for {variant, shape} <- [{"primary", "circle"}, {"secondary", "square"}, {"dismiss", "circle"}] do
            %Variation{
              id: String.to_atom(variant <> "_" <> shape),
              attributes: %{variant: variant, shape: shape},
              slots: [icon_slot("hero-play-solid")]
            }
          end
      },
      %Variation{
        id: :disabled,
        description: "Disabled state passes through via `:rest`",
        attributes: %{variant: "primary", disabled: true},
        slots: ["Unavailable"]
      }
    ]
  end

  defp label_for("primary"), do: "Play"
  defp label_for("secondary"), do: "More info"
  defp label_for("action"), do: "Approve"
  defp label_for("info"), do: "TMDB"
  defp label_for("risky"), do: "Rematch"
  defp label_for("danger"), do: "Delete"
  defp label_for("dismiss"), do: "Cancel"
  defp label_for("neutral"), do: "Test"
  defp label_for("outline"), do: "Status report"

  defp icon_slot(name) do
    ~s|<span class="hero-#{String.replace_prefix(name, "hero-", "")} size-4"></span>|
  end
end
