defmodule MediaCentaurWeb.StatusLive.IssueViewTest do
  @moduledoc """
  The ephemeral issue view on /status: clicking an incident row opens a modal
  describing the incident, which closes casually (Escape / backdrop) and hands
  off to the persistent report wizard via "Report this".
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

  defp open_issue_view(conn, fingerprint) do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    seed_bucket(fingerprint)
    render(view)
    view |> element("#incident-#{fingerprint} button[phx-click=select_incident]") |> render_click()
    view
  end

  test "clicking an incident opens the issue view with description and log lines",
       %{conn: conn} do
    view = open_issue_view(conn, "fp-pipeline-error")

    assert has_element?(view, "#issue-view[data-state=open]")
    html = render(view)
    # Subsystem plain-language description (from HealthBoard).
    assert html =~ "Turns raw files into library entries"
    # The sample log line is surfaced in the issue view.
    assert html =~ "TMDB image 503"
  end

  test "Report this hands off from the issue view to the persistent report wizard",
       %{conn: conn} do
    view = open_issue_view(conn, "fp-pipeline-error")

    view |> element("#issue-view button", "Report this") |> render_click()

    refute has_element?(view, "#issue-view[data-state=open]")
    assert has_element?(view, "[data-testid=report-modal]")
    assert has_element?(view, "[data-testid=consent-step-1]")
  end

  test "Escape closes the issue view (ephemeral)", %{conn: conn} do
    view = open_issue_view(conn, "fp-pipeline-error")
    assert has_element?(view, "#issue-view[data-state=open]")

    view |> element("#issue-view") |> render_keydown(%{"key" => "Escape"})

    assert has_element?(view, "#issue-view[data-state=closed]")
  end

  test "backdrop click closes the issue view (ephemeral)", %{conn: conn} do
    view = open_issue_view(conn, "fp-pipeline-error")
    assert has_element?(view, "#issue-view[data-state=open]")

    view |> element("#issue-view") |> render_click()

    assert has_element?(view, "#issue-view[data-state=closed]")
  end
end
