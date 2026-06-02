defmodule MediaCentaurWeb.StatusLive.ErrorSummaryTest do
  use MediaCentaurWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.Topics

  defp sample_bucket do
    %Bucket{
      fingerprint: "abc123",
      component: :tmdb,
      normalized_message: "TMDB returned <status>",
      display_title: "[TMDB] TMDB returned <status>",
      severity: :error,
      count: 3,
      first_seen: DateTime.utc_now(),
      last_seen: DateTime.utc_now(),
      sample_entries: []
    }
  end

  test "mount renders the status page without errors", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, "/status")
    assert html =~ "Status"
  end

  test "receives :buckets_changed broadcasts and re-renders without crashing", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.error_reports(),
      {:buckets_changed, [sample_bucket()]}
    )

    # PubSub delivers to the LiveView's mailbox with a synchronous local send;
    # the next render (via render/1) serialises after it in the LV's FIFO
    # mailbox, so the broadcast is already applied — no settle sleep needed.
    assert render(view) =~ "Status"
  end
end
