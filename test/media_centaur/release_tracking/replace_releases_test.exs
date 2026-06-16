defmodule MediaCentaur.ReleaseTracking.ReplaceReleasesTest do
  @moduledoc """
  Regression for the duplicate-releases bug: an item's releases must be a set,
  rebuilt atomically. `replace_releases!/3` is the single owner of that invariant
  and the `release_tracking_releases_identity_index` is the structural backstop.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking

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
end
