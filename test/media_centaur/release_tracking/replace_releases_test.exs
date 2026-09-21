defmodule MediaCentaur.ReleaseTracking.ReplaceReleasesTest do
  @moduledoc """
  Regression for the duplicate-releases bug: an item's releases must be a set,
  rebuilt atomically. `replace_releases!/3` is the single owner of that invariant
  and the `release_tracking_releases_identity_index` is the structural backstop.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TmdbStubs

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Title

  defp tv_item, do: create_tracking_item(%{media_type: :tv_series, name: "Sample Show"})

  defp ep(season, episode, attrs \\ %{}) do
    Map.merge(
      %{
        air_date: Date.utc_today(),
        title: "Sample Episode",
        season_number: season,
        episode_number: episode,
        released: true
      },
      attrs
    )
  end

  describe "replace_releases!/3" do
    test "is idempotent — repeated rebuilds never duplicate releases" do
      item = tv_item()
      releases = [ep(1, 29), ep(1, 30)]

      :ok = ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)
      :ok = ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)

      rows = ReleaseTracking.list_releases_for_item(item.id)
      assert length(rows) == 2

      assert rows |> Enum.map(&{&1.season_number, &1.episode_number}) |> Enum.sort() == [
               {1, 29},
               {1, 30}
             ]
    end

    test "a rebuild replaces the prior set wholesale" do
      item = tv_item()
      :ok = ReleaseTracking.replace_releases!(item, [ep(1, 29)], &ReleaseTracking.persist_release!/2)
      :ok = ReleaseTracking.replace_releases!(item, [ep(1, 30)], &ReleaseTracking.persist_release!/2)

      rows = ReleaseTracking.list_releases_for_item(item.id)
      assert [%{season_number: 1, episode_number: 30}] = rows
    end
  end

  describe "identity unique index" do
    test "rejects a second row with the same (item, season, episode)" do
      item = tv_item()

      attrs = %{
        item_id: item.id,
        season_number: 1,
        episode_number: 29,
        air_date: Date.utc_today(),
        title: "x"
      }

      assert {:ok, _} = ReleaseTracking.create_release(attrs)
      assert {:error, changeset} = ReleaseTracking.create_release(attrs)
      refute changeset.valid?
    end

    test "distinguishes a movie's theatrical vs digital release by release_type" do
      item = create_tracking_item(%{media_type: :movie, name: "Sample Movie", tmdb_id: 12_345})
      base = %{item_id: item.id, part_tmdb_id: 12_345, air_date: Date.utc_today(), title: "Sample Movie"}

      assert {:ok, _} = ReleaseTracking.create_release(Map.put(base, :release_type, "theatrical"))
      assert {:ok, _} = ReleaseTracking.create_release(Map.put(base, :release_type, "digital"))
      assert {:error, _} = ReleaseTracking.create_release(Map.put(base, :release_type, "digital"))
    end
  end

  describe "onboarding a movie TMDB lists twice in one release type" do
    @tmdb_id 426_063

    # TMDB's per-country release array repeats a type for re-releases,
    # staggered platform rollouts and edition-specific disc dates. Release
    # tracking stores one row per (item, type), so onboarding used to raise
    # Ecto.InvalidChangesetError out of replace_releases!/3 on any such film
    # — the user saw tracking fail outright.
    setup do
      setup_tmdb_client()

      stub_get_movie(@tmdb_id, %{
        "id" => @tmdb_id,
        "title" => "Sample Movie",
        "release_date" => "2024-12-25",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [
                %{"type" => 3, "release_date" => "2024-12-25T00:00:00.000Z"},
                %{"type" => 4, "release_date" => "2025-02-21T00:00:00.000Z"},
                %{"type" => 4, "release_date" => "2025-01-21T00:00:00.000Z"}
              ]
            }
          ]
        }
      })

      :ok
    end

    test "tracks it, keeping the earliest date for the repeated type" do
      film = Title.new!(%{tmdb_id: @tmdb_id, media_type: :movie, name: "Sample Movie"})

      assert {:ok, _intent} = ReleaseTracking.set_rung(film, :follow)

      item = ReleaseTracking.get_item_by_tmdb(@tmdb_id, :movie)
      assert item, "the film must be tracked"

      rows = ReleaseTracking.list_releases_for_item(item.id)

      assert rows |> Enum.map(&{&1.release_type, &1.air_date}) |> Enum.sort() == [
               {"digital", ~D[2025-01-21]},
               {"theatrical", ~D[2024-12-25]}
             ]

      await_supervised_tasks()
    end
  end
end
