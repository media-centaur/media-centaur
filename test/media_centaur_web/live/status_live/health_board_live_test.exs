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

  test "drilling into the watcher subsystem renders its Activity widget", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=watcher")
    assert has_element?(view, "#health-drill-in [data-testid=watcher-widget]")
  end

  test "drilling into the pipeline subsystem renders its Activity widget", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    assert has_element?(view, "#health-drill-in [data-testid=pipeline-widget]")
  end

  test "drilling into the tmdb subsystem renders its Activity widget", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=tmdb")
    assert has_element?(view, "#health-drill-in [data-testid=tmdb-widget]")
  end

  test "drilling into the playback subsystem renders its Activity widget", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=playback")
    assert has_element?(view, "#health-drill-in [data-testid=playback-widget]")
  end

  test "clicking a tile patches to that subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    view |> element("#subsystem-tile-tmdb") |> render_click()
    assert_patch(view, ~p"/status?subsystem=tmdb")
    assert has_element?(view, "#health-drill-in", "Metadata")
  end

  test "the selected tile is marked selected; others aren't", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=tmdb")

    selected = view |> element("#subsystem-tile-tmdb") |> render()
    assert selected =~ ~s(data-selected)
    assert selected =~ ~s(aria-pressed="true")

    other = view |> element("#subsystem-tile-watcher") |> render()
    refute other =~ ~s(data-selected)
    assert other =~ ~s(aria-pressed="false")
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

  defp inject_bucket(view, fingerprint) do
    bucket = %MediaCentaur.ErrorReports.Bucket{
      fingerprint: fingerprint,
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing",
      severity: :error,
      count: 4,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: [%{timestamp: ~U[2026-06-01 14:02:00Z], message: "503"}]
    }

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.error_reports(),
      {:buckets_changed, [bucket]}
    )

    assert has_element?(view, "#incident-#{fingerprint}")
  end

  test "dismissing one incident removes its row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    inject_bucket(view, "fp-dismiss-one")

    view
    |> element("#incident-fp-dismiss-one button[aria-label=Dismiss]")
    |> render_click()

    refute has_element?(view, "#incident-fp-dismiss-one")
  end

  test "dismissing all clears every incident in the subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    inject_bucket(view, "fp-dismiss-all")

    view |> element("#health-drill-in button", "Dismiss all") |> render_click()

    refute has_element?(view, "#incident-fp-dismiss-all")
    assert has_element?(view, "#health-drill-in", "No issues for this subsystem")
  end
end
