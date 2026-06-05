defmodule MediaCentaurWeb.StatusLive.ReportingTest do
  @moduledoc """
  Reporting flow on /status. Submission is browser-side: `ErrorReports.finalize_report/1`
  returns the redacted report text plus a prefilled public GitHub new-issue URL, and the
  modal offers Copy + Open-issue affordances so the user posts the issue under their own
  GitHub account. No network call in the submission path.
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

  test "3-step consent flow finalizes the report and shows the GitHub-post result",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    bucket = seed_bucket("fp-pipeline-error")
    render(view)

    # Open the modal anchored to the seeded bucket fingerprint.
    render_click(view, "open_error_report_modal", %{"fingerprint" => bucket.fingerprint})
    assert has_element?(view, "[data-testid='consent-step-1']")

    # Step 1 → enter a narrative via the phx-change form (covers paste + keystrokes).
    view
    |> element("#error-report-modal [data-testid=consent-step-1] form")
    |> render_change(%{"value" => "froze on play"})

    # Advance to step 2.
    view |> element("#error-report-modal button", "Next") |> render_click()
    assert has_element?(view, "[data-testid='consent-step-2']")

    # Advance to step 3.
    view |> element("#error-report-modal button", "Next") |> render_click()
    assert has_element?(view, "[data-testid='consent-step-3']")

    # Tick the consent checkbox.
    view
    |> element("#error-report-modal [data-testid=consent-step-3] input[type=checkbox]")
    |> render_click()

    # Send the report.
    view |> element("#error-report-modal button", "Review & post to GitHub") |> render_click()

    assert has_element?(view, "[data-testid=report-fallback]")

    html = render(view)
    assert html =~ "issues/new"

    # The prefilled issue URL carries the report title drawn from the bucket
    # (the title is the GitHub issue title field, URL-encoded in the link).
    assert html =~ "Image+downloads+failing+for+11+items"

    # Narrative was entered, so the "What happened" section is present in the bundle.
    assert html =~ "What happened"
  end

  test "generic 'Report a problem' opens the modal and files a user report", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")

    view |> element("[data-testid=report-a-problem]") |> render_click()
    assert has_element?(view, "[data-testid=report-modal]")

    # LiveComponent events carry phx-target={@myself} — drive by clicking elements.
    view
    |> element("#error-report-modal [data-testid=consent-step-1] form")
    |> render_change(%{"value" => "home page is blank"})

    view |> element("#error-report-modal button", "Next") |> render_click()
    view |> element("#error-report-modal button", "Next") |> render_click()

    view
    |> element("#error-report-modal [phx-click='toggle_consent']")
    |> render_click()

    view |> element("#error-report-modal button", "Review & post to GitHub") |> render_click()
    html = render(view)

    assert html =~ "Post this report to GitHub"
    assert Enum.any?(MediaCentaur.ErrorReports.list_incidents(), &(&1.origin == :user))
  end
end
