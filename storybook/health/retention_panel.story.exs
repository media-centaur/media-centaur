defmodule MediaCentaurWeb.Storybook.Health.RetentionPanel do
  @moduledoc """
  Story for the `<.retention_panel>` component — the "Data retention"
  section of a Status-page subsystem drill-in. Neutral text throughout:
  retention is plumbing, not a health signal. Covers a swept policy with
  stats, a not-yet-swept policy, an external continuous pruner, and a
  kept-forever declaration.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Retention.PolicyStatus

  def function, do: &MediaCentaurWeb.RetentionPanel.retention_panel/1

  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :narrow_rail,
        description: "Rail-width container — the summary drops below the label instead of crushing it",
        template: ~s|<div class="w-[300px]"><.psb-variation/></div>|,
        attributes: %{
          policies: [
            %PolicyStatus{
              key: :update_staging,
              subsystem: :self_update,
              label: "Update staging files",
              description: "Removed 2 days after an interrupted update.",
              mode: :sweep,
              last_ran_at: ~U[2026-06-12 04:33:00Z],
              pruned_last_run: 41,
              pruned_total: 88
            }
          ]
        }
      },
      %Variation{
        id: :swept_with_stats,
        description: "Sweep policies with recorded runs",
        attributes: %{
          policies: [
            %PolicyStatus{
              key: :diagnostic_events,
              subsystem: :system,
              label: "Diagnostic events",
              description: "Diagnostic log events older than 30 days are deleted.",
              mode: :sweep,
              last_ran_at: ~U[2026-06-11 04:33:00Z],
              pruned_last_run: 1204,
              pruned_total: 38_112
            },
            %PolicyStatus{
              key: :resolved_incidents,
              subsystem: :system,
              label: "Resolved incidents",
              description:
                "Incidents resolved more than 90 days ago are deleted. " <>
                  "Open and acknowledged incidents are kept indefinitely.",
              mode: :sweep,
              last_ran_at: ~U[2026-06-11 04:33:00Z],
              pruned_last_run: 0,
              pruned_total: 14
            }
          ]
        }
      },
      %Variation{
        id: :mixed_modes,
        description: "Not-yet-swept, external/continuous, and kept-forever policies",
        attributes: %{
          policies: [
            %PolicyStatus{
              key: :pursuit_events,
              subsystem: :acquisition,
              label: "Pursuit activity log",
              description:
                "Per-pursuit activity events older than 90 days are deleted. " <>
                  "The pursuits themselves are kept.",
              mode: :sweep,
              last_ran_at: nil
            },
            %PolicyStatus{
              key: :oban_jobs,
              subsystem: :system,
              label: "Background jobs",
              description:
                "Finished background jobs (completed, cancelled, or discarded) " <>
                  "are deleted after 7 days, continuously.",
              mode: :external,
              last_ran_at: nil
            },
            %PolicyStatus{
              key: :watch_history,
              subsystem: :playback,
              label: "Watch history",
              description:
                "Kept forever by design — history outlives deleted titles. " <>
                  "Individual entries can be removed from the history page.",
              mode: :forever
            }
          ]
        }
      }
    ]
  end
end
