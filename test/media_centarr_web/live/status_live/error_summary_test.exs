defmodule MediaCentarrWeb.StatusLive.ErrorSummaryTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentarr.ErrorReports.Bucket
  alias MediaCentarr.Topics

  defp sample_bucket do
    %Bucket{
      fingerprint: "abc123",
      component: :tmdb,
      normalized_message: "TMDB returned <status>",
      display_title: "[TMDB] TMDB returned <status>",
      count: 3,
      first_seen: DateTime.utc_now(),
      last_seen: DateTime.utc_now(),
      sample_entries: []
    }
  end

  test "mount populates error_buckets assign", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    assert has_element?(view, "[data-testid='error-summary-card']")
  end

  test "receives :buckets_changed broadcasts", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.error_reports(),
      {:buckets_changed, [sample_bucket()]}
    )

    :timer.sleep(50)
    assert has_element?(view, "[data-testid='error-summary-card']")
  end
end
