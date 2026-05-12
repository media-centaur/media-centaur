defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitGroup do
  @moduledoc """
  Collapsible group row for N pursuits of the same show in the same
  state. Header shows the show name, count, and a severity-colored verb;
  expanded body lists the per-episode compact `PursuitRow`s underneath.

  Used in the Active Pursuits and History zones on the Downloads page
  when multiple episodes of a TV show share a pursuit state (e.g. 7
  episodes of Sample Game May Weep all searching).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{CurrentAction, PursuitRow}

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitGroup.pursuit_group/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :collapsed_two_episodes,
        description: "Smallest group — exactly 2 episodes in the same state.",
        attributes: %{
          title: "Sample Show",
          state: :active,
          count: 2,
          verb: "Searching",
          severity: :info,
          vms: [
            row(season: 1, episode: 1, attempt: 3),
            row(season: 1, episode: 2, attempt: 3)
          ],
          expanded?: false
        }
      },
      %Variation{
        id: :expanded_seven_episodes,
        description:
          "Larger group expanded — the case the user hit. Header shows count and verb; per-episode compact rows render below.",
        attributes: %{
          title: "Sample Show",
          state: :active,
          count: 7,
          verb: "Searching",
          severity: :info,
          vms:
            for episode <- 2..8 do
              row(season: 2, episode: episode, attempt: 4)
            end,
          expanded?: true
        }
      },
      %Variation{
        id: :collapsed_decision_needed,
        description: "Same-show pursuits all awaiting user decision — warning severity.",
        attributes: %{
          title: "Sample Show",
          state: :needs_decision,
          count: 3,
          verb: "Decision needed",
          severity: :warning,
          vms: [
            row(season: 1, episode: 4, verb: "Decision needed", severity: :warning),
            row(season: 1, episode: 5, verb: "Decision needed", severity: :warning),
            row(season: 1, episode: 6, verb: "Decision needed", severity: :warning)
          ],
          expanded?: false
        }
      },
      %Variation{
        id: :expanded_exhausted_history,
        description: "Group of failed pursuits in the History zone, expanded.",
        attributes: %{
          title: "Sample Show",
          state: :exhausted,
          count: 4,
          verb: "Gave up",
          severity: :error,
          vms:
            for episode <- 1..4 do
              row(season: 3, episode: episode, verb: "Gave up", severity: :error)
            end,
          expanded?: true
        }
      }
    ]
  end

  defp row(opts) do
    season = Keyword.get(opts, :season)
    episode = Keyword.get(opts, :episode)
    verb = Keyword.get(opts, :verb, "Searching")
    severity = Keyword.get(opts, :severity, :info)
    attempt = Keyword.get(opts, :attempt, 1)

    %PursuitRow{
      id: "story-#{season}-#{episode}-#{verb}",
      title: "Sample Show",
      state: state_for_severity(severity),
      season_number: season,
      episode_number: episode,
      status: %CurrentAction{
        verb: verb,
        description: description_for(verb, attempt),
        severity: severity
      }
    }
  end

  defp state_for_severity(:info), do: :active
  defp state_for_severity(:warning), do: :needs_decision
  defp state_for_severity(:error), do: :exhausted
  defp state_for_severity(:success), do: :satisfied

  defp description_for("Searching", attempt),
    do: "Looking for an acceptable release (attempt #{attempt})."

  defp description_for("Decision needed", _), do: "Pick a release below."
  defp description_for("Gave up", _), do: "Exhausted after 4 attempts."
  defp description_for(_, _), do: ""
end
