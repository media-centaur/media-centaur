defmodule MediaCentaurWeb.Storybook.Status.IssueView do
  @moduledoc """
  Ephemeral incident issue view — opened from a Status incident row. Shows the
  incident's title, subsystem (name + glyph), severity, occurrence range, and
  its evidence (sample log lines, or a subsystem fault's probe detail), then
  hands off to the report wizard. The subsystem
  briefing stays on the drill-in this opens from — the modal is about the
  incident, not the subsystem.

  Each open variation renders a real `position: fixed` overlay, so they are
  iframed to keep them from stacking.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ErrorReports.Bucket

  def function, do: &MediaCentaurWeb.Components.IssueView.issue_view/1
  def render_source, do: :function
  def layout, do: :one_column
  def container, do: {:iframe, style: "min-height: 560px; width: 100%;"}

  def template do
    """
    <div>
      <button type="button" class="btn btn-sm btn-primary"
        phx-click={Phoenix.LiveView.JS.push("psb-assign", value: %{bucket: nil})} psb-code-hidden>
        Close
      </button>
      <.psb-variation/>
    </div>
    """
  end

  defp bucket(severity, samples) do
    %Bucket{
      fingerprint: "fp-#{severity}",
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing for 11 items",
      severity: severity,
      count: 11,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: samples
    }
  end

  defp fault do
    %Bucket{
      fingerprint: "subsystem:social:relays_unreachable",
      component: :social,
      normalized_message: "No relay reachable",
      display_title: "No relay reachable",
      severity: :error,
      count: 3,
      first_seen: ~U[2026-06-01 14:55:00Z],
      last_seen: ~U[2026-06-01 15:05:00Z],
      sample_entries: [],
      detail:
        "wss://relay.example/ — disconnected for 12 min (connection refused)\nwss://relay.other/ — disconnected for 11 min"
    }
  end

  defp samples do
    [
      %{timestamp: ~U[2026-06-01 14:02:00Z], message: "GET poster 503 (attempt 1)"},
      %{timestamp: ~U[2026-06-01 14:31:00Z], message: "GET poster 503 (attempt 2)"}
    ]
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed — in the DOM, hidden via `data-state`.",
        attributes: %{bucket: nil}
      },
      %Variation{
        id: :error_with_logs,
        description: "Error severity, with sample log lines.",
        attributes: %{bucket: bucket(:error, samples())}
      },
      %Variation{
        id: :warning_no_logs,
        description: "Warning severity, no sample log lines — the body collapses.",
        attributes: %{bucket: bucket(:warning, [])}
      },
      %Variation{
        id: :subsystem_fault,
        description: "A probe-raised fault: no log lines, the probe's detail instead.",
        attributes: %{bucket: fault()}
      }
    ]
  end
end
