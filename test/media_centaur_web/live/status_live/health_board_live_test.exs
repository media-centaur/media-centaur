defmodule MediaCentaurWeb.StatusLive.HealthBoardLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Buckets

  test "renders a tile per subsystem and opens a drill-in on ?subsystem=", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    assert has_element?(view, "#subsystem-tile-pipeline")
    assert has_element?(view, "#subsystem-tile-watcher")

    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    assert has_element?(view, "#health-drill-in", "Media import")
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
      headline: "Image downloads failing for 11 items",
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
    # The row body is a button that opens the issue view (report now lives there).
    assert has_element?(view, "#incident-fp-pipeline-error button[phx-click=select_incident]")
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
    # Dismissing broadcasts the global Buckets snapshot, which replaces the
    # injected list in the view. Warnings logged by earlier tests can have
    # minted pipeline buckets there, so start from an empty snapshot.
    Buckets.dismiss(Enum.map(Buckets.list_buckets(), & &1.fingerprint))

    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    inject_bucket(view, "fp-dismiss-all")

    view |> element("#health-drill-in button", "Dismiss all") |> render_click()

    refute has_element?(view, "#incident-fp-dismiss-all")
    assert has_element?(view, "#health-drill-in", "No issues")
  end

  # The issue view is open when its footer Dismiss button (which carries the
  # bucket's fingerprint) is in the DOM — that subtree only renders when a
  # bucket is selected.
  defp incident_open?(view, fingerprint) do
    has_element?(view, "#issue-view button[phx-value-fingerprint='#{fingerprint}']")
  end

  test "clicking an incident patches in ?incident= and opens the issue view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    inject_bucket(view, "fp-deeplink")

    view |> element("#incident-fp-deeplink button[phx-click=select_incident]") |> render_click()

    assert_patch(view, ~p"/status?subsystem=pipeline&incident=fp-deeplink")
    assert incident_open?(view, "fp-deeplink")
  end

  test "closing the issue view drops ?incident= but keeps the subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    inject_bucket(view, "fp-close")
    view |> element("#incident-fp-close button[phx-click=select_incident]") |> render_click()
    assert_patch(view, ~p"/status?subsystem=pipeline&incident=fp-close")

    view |> element("#issue-view button", "Close") |> render_click()

    assert_patch(view, ~p"/status?subsystem=pipeline")
    refute incident_open?(view, "fp-close")
  end

  test "a deep link to ?incident= opens the issue view on a cold load", %{conn: conn} do
    # Seed the buckets cache the way production does (the LogHandler ingests
    # entries), then cold-load the URL and assert the modal is already open.
    Buckets.ingest(
      Entry.new(%{
        id: 1,
        timestamp: ~U[2026-06-08 08:11:00Z],
        level: :error,
        component: :pipeline,
        message: "cold-load deep link probe",
        metadata: %{}
      })
    )

    bucket =
      Enum.find(Buckets.list_buckets(), fn bucket ->
        Enum.any?(bucket.sample_entries, &(&1.message == "cold-load deep link probe"))
      end)

    on_exit(fn -> Buckets.dismiss([bucket.fingerprint]) end)

    {:ok, view, _html} = live(conn, ~p"/status?incident=#{bucket.fingerprint}")

    assert incident_open?(view, bucket.fingerprint)
  end
end
