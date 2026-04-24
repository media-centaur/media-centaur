defmodule MediaCentarrWeb.StatusLive.ReportModalTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.Buckets
  alias MediaCentarr.Topics

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

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.error_reports(),
      {:buckets_changed, Buckets.list_buckets()}
    )

    :timer.sleep(50)
    :ok
  end

  test "clicking Report errors opens the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    assert has_element?(view, "[data-testid='report-modal']")
  end

  test "confirm emits error_reports:open_issue push_event", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_confirm", %{"fingerprint" => hd(Buckets.list_buckets()).fingerprint})

    assert_push_event(view, "error_reports:open_issue", %{url: url})
    assert url =~ "https://github.com/media-centarr/media-centarr/issues/new"
  end

  test "cancel dismisses the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_cancel", %{})
    refute has_element?(view, "[data-testid='report-modal']")
  end
end
