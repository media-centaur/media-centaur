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
    Buckets.ingest(error_entry(2, :watcher, "permission denied on watch dir"))

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

  test "clicking Report errors opens the modal", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    assert has_element?(view, "[data-testid='report-modal']")
  end

  test "confirm submits via submit_report and shows the copy-fallback (no token)", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_confirm", %{"fingerprint" => hd(Buckets.list_buckets()).fingerprint})

    # No token is configured in test, so submission falls back to presenting
    # the redacted bundle for the user to copy (never the old window.open path).
    assert has_element?(view, "[data-testid=report-fallback]")
  end

  test "cancel dismisses the modal", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_cancel", %{})
    refute has_element?(view, "[data-testid='report-modal']")
  end
end
