defmodule MediaCentaur.Repo.DataMigrations.CaughtUpAndLabelOnTheIntentTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.CaughtUpAndLabelOnTheIntent
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Watchlist

  defp intent_columns(tmdb_id) do
    %{rows: [row]} =
      Repo.query!(
        "SELECT caught_up_season, caught_up_episode, title_name, title_year FROM title_intents WHERE tmdb_id = ?",
        [tmdb_id]
      )

    row
  end

  describe "migrate/1" do
    test "moves an unlinked series' start point onto its intent, zeroes the watermark, unflags its releases and labels every record from the store" do
      # The old shape: an unlinked tracked series carrying a start point in
      # the library's columns, with the episodes it covered flagged as held.
      item =
        create_tracking_item(%{
          tmdb_id: 4242,
          media_type: :tv_series,
          name: "Sample Show",
          last_library_season: 1,
          last_library_episode: 28,
          payload:
            MediaCentaur.TmdbStubs.tv_detail(%{
              "id" => 4242,
              "name" => "Sample Show",
              "first_air_date" => "2023-09-29"
            })
        })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 28,
        in_library: true
      })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 29,
        in_library: false
      })

      Repo.query!("UPDATE title_intents SET title_name = NULL, title_year = NULL", [])

      linked =
        create_tracking_item(%{
          tmdb_id: 4343,
          media_type: :tv_series,
          name: "Owned Show",
          library_container_type: :tv_series,
          library_container_id: Ecto.UUID.generate(),
          last_library_season: 2,
          last_library_episode: 3
        })

      create_tracking_release(%{
        item_id: linked.id,
        season_number: 2,
        episode_number: 3,
        in_library: true
      })

      assert :ok = CaughtUpAndLabelOnTheIntent.migrate(Repo)

      assert Watchlist.caught_up(4242, :tv_series) == {1, 28}
      assert intent_columns(4242) == [1, 28, "Sample Show", "2023"]
      moved = ReleaseTracking.get_item(item.id)
      assert {moved.last_library_season, moved.last_library_episode} == {0, 0}
      assert Enum.all?(ReleaseTracking.list_releases_for_item(item.id), &(&1.in_library == false))

      # A linked series keeps its watermark and its library's flags.
      assert Watchlist.caught_up(4343, :tv_series) == nil
      kept = ReleaseTracking.get_item(linked.id)
      assert {kept.last_library_season, kept.last_library_episode} == {2, 3}
      assert [%{in_library: true}] = ReleaseTracking.list_releases_for_item(linked.id)
    end

    test "is idempotent: a second run moves nothing and overwrites no label" do
      item =
        create_tracking_item(%{
          tmdb_id: 4242,
          media_type: :tv_series,
          last_library_season: 1,
          last_library_episode: 5
        })

      assert :ok = CaughtUpAndLabelOnTheIntent.migrate(Repo)
      {:ok, _} = Watchlist.catch_up(4242, :tv_series, {1, 9})
      Repo.query!("UPDATE title_intents SET title_name = 'Renamed' WHERE tmdb_id = 4242", [])

      assert :ok = CaughtUpAndLabelOnTheIntent.migrate(Repo)

      assert Watchlist.caught_up(4242, :tv_series) == {1, 9}
      assert [_, _, "Renamed", _] = intent_columns(4242)
      assert ReleaseTracking.get_item(item.id).last_library_season == 0
    end
  end
end
