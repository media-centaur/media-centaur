defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc "Detail-page header for `/download/:pursuit_id`."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :state_axis,
        description: "Header rendered for each pursuit state",
        variations: [
          %Variation{
            id: :active,
            attributes: %{vm: header(:active, "Sample Movie")}
          },
          %Variation{
            id: :needs_decision,
            attributes: %{vm: header(:needs_decision, "Sample Show S01E03")}
          },
          %Variation{
            id: :satisfied,
            attributes: %{vm: header(:satisfied, "Public Domain Film 1923")}
          },
          %Variation{
            id: :exhausted,
            attributes: %{vm: header(:exhausted, "Movie A")}
          },
          %Variation{
            id: :cancelled,
            attributes: %{vm: header(:cancelled, "Movie B")}
          }
        ]
      },
      %Variation{
        id: :with_cancel_button,
        description: "Active pursuit with the Cancel button bound to `on_cancel`",
        attributes: %{
          vm: header(:active, "Sample Movie"),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :no_criteria,
        description: "Header with no criteria (manual grab without quality bounds)",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-no-crit",
            title: "Manual Pick",
            state: :active,
            origin: :manual,
            attempt_count: 1,
            tried_count: 0,
            criteria_summary: nil,
            inserted_at: ~U[2026-05-07 10:00:00Z]
          }
        }
      }
    ]
  end

  defp header(state, title) do
    %PursuitHeader{
      id: "story-#{state}",
      title: title,
      state: state,
      origin: :auto,
      attempt_count: attempts_for(state),
      tried_count: tried_for(state),
      criteria_summary: "max_quality: 2160p, min_quality: 1080p",
      inserted_at: ~U[2026-05-07 10:00:00Z]
    }
  end

  defp attempts_for(:active), do: 1
  defp attempts_for(:needs_decision), do: 2
  defp attempts_for(:satisfied), do: 1
  defp attempts_for(:exhausted), do: 4
  defp attempts_for(:cancelled), do: 1

  defp tried_for(:active), do: 0
  defp tried_for(:needs_decision), do: 1
  defp tried_for(:satisfied), do: 1
  defp tried_for(:exhausted), do: 4
  defp tried_for(:cancelled), do: 1
end
