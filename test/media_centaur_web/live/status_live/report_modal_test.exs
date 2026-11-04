defmodule MediaCentaurWeb.StatusLive.ReportModalTest do
  use MediaCentaurWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.Topics

  defp error_entry(id, component, message) do
    Entry.new(%{
      id: id,
      timestamp: DateTime.utc_now(),
      level: :error,
      component: component,
      message: message,
      metadata: %{}
    })
  end

  setup do
    Buckets.ingest(error_entry(1, :tmdb, "TMDB returned 429 rate limited"))
    Buckets.ingest(error_entry(2, :watcher, "permission denied on media dir"))

    # `Buckets.list_buckets/0` is a GenServer.call, so it serialises after the
    # two `ingest` casts above (FIFO) — the buckets are populated before any
    # test runs without a settle sleep. (No LiveView is mounted yet, so this
    # broadcast has no subscribers; it stands in for production wiring.)
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.error_reports(),
      {:buckets_changed, Buckets.list_buckets()}
    )

    :ok
  end

  test "open_error_report_modal event opens the modal at step 1", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")
    render_click(view, "open_error_report_modal", %{})
    assert has_element?(view, "[data-testid='report-modal']")
    assert has_element?(view, "[data-testid='consent-step-1']")
  end

  test "cancel dismisses the modal", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")
    render_click(view, "open_error_report_modal", %{})
    render_click(view, "report_cancel", %{})
    refute has_element?(view, "[data-testid='report-modal']")
  end

  describe "keyboard and gamepad" do
    test "the wizard is an input-system overlay: no key capture, every control a nav item",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status")
      render_click(view, "open_error_report_modal", %{})

      refute has_element?(view, "#error-report-modal [data-captures-keys]")
      refute has_element?(view, "#error-report-modal[data-captures-keys]")
      assert has_element?(view, "#error-report-modal [data-detail-mode='modal']")

      overlay = "#error-report-modal [data-detail-mode='modal']"
      assert has_element?(view, "#{overlay} textarea[name='value'][data-nav-item]")
      assert has_element?(view, "#{overlay} button[data-nav-item]", "No, don't send")
      assert has_element?(view, "#{overlay} button[data-nav-item]", "Next")

      view |> element("#error-report-modal button", "Next") |> render_click()
      assert has_element?(view, "#{overlay} input[name='value'][data-nav-item]")
      assert has_element?(view, "#{overlay} button[data-nav-item]", "Back")

      view |> element("#error-report-modal button", "Next") |> render_click()
      assert has_element?(view, "#{overlay} input[type='checkbox'][data-nav-item]")
    end

    test "BACK on step 1 closes the wizard", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status")
      render_click(view, "open_error_report_modal", %{})

      assert has_element?(
               view,
               "#error-report-modal [data-detail-mode='modal'][data-dismiss-event='report_cancel']"
             )

      refute has_element?(view, "#error-report-modal [data-detail-nested='true']")
    end

    test "BACK past step 1 returns a step, the wizard stays open", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status")
      render_click(view, "open_error_report_modal", %{})
      view |> element("#error-report-modal button", "Next") |> render_click()

      overlay = "#error-report-modal [data-detail-mode='modal']"
      assert has_element?(view, "#{overlay}[data-detail-nested='true']")
      assert has_element?(view, "#{overlay}[data-dismiss-event='report_step_back']")

      render_click(view, "report_step_back", %{})

      assert has_element?(view, "[data-testid='consent-step-1']")
    end
  end

  test "3-step flow: consent + send shows the GitHub-post result", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")

    # Open modal — anchors to first bucket automatically (no fingerprint).
    render_click(view, "open_error_report_modal", %{})
    assert has_element?(view, "[data-testid='consent-step-1']")

    # Advance through step 1 → 2 → 3.
    view |> element("#error-report-modal button", "Next") |> render_click()
    assert has_element?(view, "[data-testid='consent-step-2']")

    view |> element("#error-report-modal button", "Next") |> render_click()
    assert has_element?(view, "[data-testid='consent-step-3']")

    # Tick consent checkbox.
    view
    |> element("#error-report-modal [data-testid=consent-step-3] input[type=checkbox]")
    |> render_click()

    # Send the report.
    view |> element("#error-report-modal button", "Review & post to GitHub") |> render_click()

    assert has_element?(view, "[data-testid=report-fallback]")
    html = render(view)
    assert html =~ "issues/new"
    assert html =~ "Copy report"
  end
end
