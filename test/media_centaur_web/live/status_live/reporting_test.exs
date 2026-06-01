defmodule MediaCentaurWeb.StatusLive.ReportingTest do
  @moduledoc """
  Reporting flow on /status. Submission goes through
  `ErrorReports.submit_report/2`; with no token configured (the default in
  dev/test) it falls back to presenting the redacted bundle for the user to
  copy — never the old `window.open` GitHub-URL path.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defp seed_bucket(fingerprint) do
    bucket = %MediaCentaur.ErrorReports.Bucket{
      fingerprint: fingerprint,
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing for 11 items",
      severity: :error,
      count: 11,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: [%{timestamp: ~U[2026-06-01 14:02:00Z], message: "TMDB image 503"}]
    }

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.error_reports(),
      {:buckets_changed, [bucket]}
    )

    bucket
  end

  test "confirming a report submits via submit_report and shows the copy-fallback (no token)",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    bucket = seed_bucket("fp-pipeline-error")
    render(view)

    render_click(view, "open_error_report_modal", %{})
    html = render_click(view, "report_confirm", %{"fingerprint" => bucket.fingerprint})

    # The redacted bundle is presented inline for copying — the report title
    # (drawn from the bucket) appears in the rendered fallback.
    assert html =~ "Image downloads failing for 11 items"
    # Fallback path renders a copyable region, not a "open GitHub" success.
    assert has_element?(view, "[data-testid=report-fallback]")
  end
end
