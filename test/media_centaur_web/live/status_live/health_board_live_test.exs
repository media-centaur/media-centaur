defmodule MediaCentaurWeb.StatusLive.HealthBoardLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders a tile per subsystem and opens a drill-in on ?subsystem=", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    assert has_element?(view, "#subsystem-tile-pipeline")
    assert has_element?(view, "#subsystem-tile-watcher")

    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    assert has_element?(view, "#health-drill-in", "Import")
  end

  test "clicking a tile patches to that subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    view |> element("#subsystem-tile-tmdb") |> render_click()
    assert_patch(view, ~p"/status?subsystem=tmdb")
    assert has_element?(view, "#health-drill-in", "Metadata")
  end

  test "a buckets_changed broadcast renders the unhealthy tile + reportable incident",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")

    bucket = %MediaCentaur.ErrorReports.Bucket{
      fingerprint: "fp-pipeline-error",
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

    # The error tile gains its accent and the drill-in renders the incident row.
    assert render(view) =~ "Image downloads failing for 11 items"
    assert has_element?(view, "#incident-fp-pipeline-error")
    assert has_element?(view, "#incident-fp-pipeline-error button", "Report this")
  end
end
