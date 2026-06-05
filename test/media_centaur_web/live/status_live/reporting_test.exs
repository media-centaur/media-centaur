defmodule MediaCentaurWeb.StatusLive.ReportingTest do
  @moduledoc """
  Reporting flow on /status. Submission goes through
  `ErrorReports.submit_payload/2`; with no token configured (the default in
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

  test "3-step consent flow submits via submit_payload and shows the copy-fallback (no token)",
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
    view |> element("#error-report-modal button", "Send to the developer") |> render_click()

    # No token → fallback textarea appears.
    assert has_element?(view, "[data-testid=report-fallback]")

    # Fallback bundle includes the report title drawn from the bucket.
    html = render(view)
    assert html =~ "Image downloads failing for 11 items"

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

    view |> element("#error-report-modal button", "Send to the developer") |> render_click()
    html = render(view)

    assert html =~ "Report sent" or html =~ "Copy this report"
    assert Enum.any?(MediaCentaur.ErrorReports.list_incidents(), &(&1.origin == :user))
  end
end
