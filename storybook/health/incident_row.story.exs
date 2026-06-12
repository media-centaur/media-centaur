defmodule MediaCentaurWeb.Storybook.Health.IncidentRow do
  @moduledoc """
  Story for the `<.incident_row>` component — one incident in the drill-in's
  Issues section. Severity is the only color. The row body is a button that
  opens the issue view (`on_select`); the X dismisses. Reporting moved off the
  row into the issue view.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ErrorReports.Bucket

  def function, do: &MediaCentaurWeb.HealthComponents.incident_row/1

  defp bucket(severity) do
    %Bucket{
      fingerprint: "fp-#{severity}",
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing for 11 items",
      headline: "Image downloads failing for 11 items",
      severity: severity,
      count: 11,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: []
    }
  end

  # The row shows the derived headline, never the raw normalized message —
  # this fixture pins the crash-report case from the title-grammar work.
  defp crash_bucket do
    message =
      "GenServer MediaCentaur.Pipeline.Image.RetryScheduler terminating " <>
        "** (Exqlite.Error) no such column: p0.media_dir " <>
        "(ecto_sql 3.13.5) lib/ecto/adapters/sql.ex: Ecto.Adapters.SQL.raise_sql_call_error/1"

    %Bucket{
      fingerprint: "fp-crash",
      component: :system,
      normalized_message: message,
      display_title: "[System] #{message}",
      headline: "Pipeline.Image.RetryScheduler crashed — Exqlite.Error: no such column: p0.media_dir",
      severity: :error,
      count: 9,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: []
    }
  end

  def variations do
    [
      %Variation{id: :error, attributes: %{bucket: bucket(:error)}},
      %Variation{id: :warning, attributes: %{bucket: bucket(:warning)}},
      %Variation{
        id: :crash_report,
        description: "OTP crash bucket — headline grammar, not the raw exception text",
        attributes: %{bucket: crash_bucket()}
      }
    ]
  end
end
