defmodule MediaCentaurWeb.ReconcileLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Reconciliation
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  defp seed_show do
    series = create_tv_series(%{name: "Sample Show", tmdb_id: "42"})
    season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

    for episode_number <- [1, 2] do
      episode = create_episode(%{season_id: season.id, episode_number: episode_number, name: "Ep"})
      playable_item = create_playable_item_for_episode(episode)

      create_linked_file(%{
        playable_item_id: playable_item.id,
        file_path: "/media/s/E#{episode_number}.mkv"
      })
    end

    TmdbStubs.stub_routes([
      {"/tv/42/season/1",
       TmdbStubs.season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Alpha"},
           %{"episode_number" => 2, "name" => "Beta"},
           %{"episode_number" => 3, "name" => "Gamma"},
           %{"episode_number" => 4, "name" => "Delta"}
         ]
       })},
      {"/tv/42", TmdbStubs.tv_detail(%{"id" => 42, "seasons" => [%{"season_number" => 1}]})}
    ])

    series
  end

  defp divert_file do
    {:ok, file} =
      Reconciliation.divert(%{
        file_path: "/media/s/S02E01.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        series_title: "Sample Show",
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: "Gamma"
      })

    file
  end

  test "empty queue renders the explainer, not a crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/reconcile")

    assert html =~ "Episode mapping"
    assert html =~ "absolute numbering"
  end

  test "selected show renders its recommended mapping", %{conn: conn} do
    seed_show()
    divert_file()

    {:ok, _view, html} = live(conn, "/reconcile")

    assert html =~ "Sample Show"
    assert html =~ "1 file(s) waiting"
    # The recommended target (E3 — Gamma) appears as the selected option.
    assert html =~ "Gamma"
  end

  test "confirming links the file to its canonical episode and clears the queue", %{conn: conn} do
    seed_show()
    divert_file()

    {:ok, view, _html} = live(conn, "/reconcile")

    html = view |> element("button", "Confirm matches") |> render_click()

    assert html =~ "Linked 1 file(s)"
    assert {:ok, "/media/s/S02E01.mkv"} = Library.find_present_episode("42", 1, 3)
    assert Reconciliation.list_awaiting() == []
  end

  test "overriding the target episode is honored on confirm", %{conn: conn} do
    seed_show()
    file = divert_file()

    {:ok, view, _html} = live(conn, "/reconcile")

    # The picker change (a form phx-change) re-targets the file from E3 to E4.
    view
    |> element("#reconcile-row-#{file.id} form")
    |> render_change(%{"file" => file.id, "target" => "1-4"})

    view |> element("button", "Confirm matches") |> render_click()

    assert {:ok, _} = Library.find_present_episode("42", 1, 4)
    assert Library.find_present_episode("42", 1, 3) == :not_found
  end

  test "dismiss all clears the queue without linking", %{conn: conn} do
    seed_show()
    divert_file()

    {:ok, view, _html} = live(conn, "/reconcile")

    html = view |> element("button", "Dismiss all") |> render_click()

    assert html =~ "Dismissed 1 file(s)"
    assert Reconciliation.list_awaiting() == []
    assert Library.find_present_episode("42", 1, 3) == :not_found
  end
end
