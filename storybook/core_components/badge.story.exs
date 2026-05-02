defmodule MediaCentarrWeb.Storybook.CoreComponents.Badge do
  @moduledoc """
  Story for the `<.badge>` component — UIDR-002 codified as typed variants.

  Covers the variant matrix, size axis, and real-world examples. Keep in sync
  with the recipes in the `user-interface` skill.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.badge/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :variants,
        description: "All variants at default (sm) size",
        variations:
          for variant <- ~w(metric type info success warning error ghost primary soft_primary) do
            %Variation{
              id: String.to_atom(variant),
              attributes: %{variant: variant},
              slots: [label_for(variant)]
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Size axis (xs / sm / md) on the success variant",
        variations:
          for size <- ~w(xs sm md) do
            %Variation{
              id: String.to_atom("success_" <> size),
              attributes: %{variant: "success", size: size},
              slots: ["Completed"]
            }
          end
      },
      %VariationGroup{
        id: :type_classification,
        description: "Type classification — outline, no color ([UIDR-002] #3)",
        variations:
          for label <- ~w(Movie TV Extra) do
            %Variation{
              id: String.to_atom("type_" <> String.downcase(label)),
              attributes: %{variant: "type"},
              slots: [label]
            }
          end
      },
      %VariationGroup{
        id: :state_chips,
        description: "Acquisition / pipeline state chips — solid semantic fill",
        variations: [
          %Variation{
            id: :downloading,
            attributes: %{variant: "info"},
            slots: ["Downloading"]
          },
          %Variation{
            id: :completed,
            attributes: %{variant: "success"},
            slots: ["Completed"]
          },
          %Variation{
            id: :paused,
            attributes: %{variant: "warning"},
            slots: ["Paused"]
          },
          %Variation{
            id: :failed,
            attributes: %{variant: "error"},
            slots: ["Failed"]
          },
          %Variation{
            id: :queued,
            attributes: %{variant: "ghost"},
            slots: ["Queued"]
          }
        ]
      },
      %VariationGroup{
        id: :metric_counts,
        description: "Metric badges — solid neutral, used for counts",
        variations: [
          %Variation{
            id: :tab_count,
            attributes: %{},
            slots: ["12"]
          },
          %Variation{
            id: :error_bucket_count,
            attributes: %{variant: "ghost"},
            slots: ["×3"]
          }
        ]
      }
    ]
  end

  defp label_for("metric"), do: "12"
  defp label_for("type"), do: "Movie"
  defp label_for("info"), do: "Downloading"
  defp label_for("success"), do: "Completed"
  defp label_for("warning"), do: "Paused"
  defp label_for("error"), do: "Failed"
  defp label_for("ghost"), do: "Queued"
  defp label_for("primary"), do: "Today"
  defp label_for("soft_primary"), do: "2×"
end
