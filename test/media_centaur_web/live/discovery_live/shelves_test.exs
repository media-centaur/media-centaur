defmodule MediaCentaurWeb.DiscoveryLive.ShelvesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.PosterRow.Item
  alias MediaCentaurWeb.DiscoveryLive.Shelves

  defp member(tmdb_id, position),
    do: %Member{tmdb_id: tmdb_id, position: position, digital_date: ~D[2026-10-30]}

  defp title(tmdb_id, name),
    do:
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        name: name,
        year: "2026",
        poster_path: "/p#{tmdb_id}.jpg"
      })

  describe "new_releases_items/5" do
    test "one tile per stored member in shelf order, keyed by ref, with the year and a poster" do
      members = [member(902, 0), member(901, 1)]
      snapshots = %{{901, :movie} => title(901, "Movie A"), {902, :movie} => title(902, "Movie B")}

      assert [
               %Item{id: "movie-902", ref: {902, :movie}, name: "Movie B", year: "2026", marker: nil},
               %Item{id: "movie-901", ref: {901, :movie}, name: "Movie A"}
             ] = Shelves.new_releases_items(members, snapshots, %{}, %{}, %{})

      assert [%Item{poster_url: "https://image.tmdb.org/t/p/w342/p902.jpg"} | _rest] =
               Shelves.new_releases_items(members, snapshots, %{}, %{}, %{})
    end

    test "a member the store has no record for is not drawn; an ignored one is dropped" do
      members = [member(901, 0), member(902, 1), member(903, 2)]
      snapshots = %{{901, :movie} => title(901, "Movie A"), {902, :movie} => title(902, "Movie B")}

      assert [%Item{id: "movie-901"}] =
               Shelves.new_releases_items(members, snapshots, %{{902, :movie} => :ignored}, %{}, %{})
    end

    test "the marker is the library's claim first, else the acquisition state, else the rung" do
      members = [member(901, 0), member(902, 1), member(903, 2), member(904, 3)]

      snapshots =
        Map.new([901, 902, 903, 904], &{{&1, :movie}, title(&1, "Movie #{&1}")})

      items =
        Shelves.new_releases_items(
          members,
          snapshots,
          %{{901, :movie} => :follow, {903, :movie} => :list, {904, :movie} => :grab},
          %{{901, :movie} => "owner-uuid"},
          %{{902, :movie} => :downloading}
        )

      assert Enum.map(items, & &1.marker) == ["In library", "Downloading", "On your list", "Auto-grab"]
    end
  end

  describe "empty_reason/3" do
    test "TMDB never configured is the capability gap, whatever else holds" do
      assert Shelves.empty_reason(false, true, 0) == :tmdb_unconfigured
      assert Shelves.empty_reason(false, false, 3) == :tmdb_unconfigured
    end

    test "with tiles there is no reason" do
      assert Shelves.empty_reason(true, false, 1) == nil
    end

    test "nothing to show says whether TMDB is down or the refresh is still to run" do
      assert Shelves.empty_reason(true, false, 0) == :tmdb_down
      assert Shelves.empty_reason(true, true, 0) == :filling
    end
  end

  describe "reloads?/1" do
    test "the broadcasts that change the shelf, and nothing else" do
      assert Shelves.reloads?({:new_releases_changed})
      assert Shelves.reloads?({:tmdb_title_changed, {901, :movie}})
      assert Shelves.reloads?({:title_intent_changed, %{}})
      assert Shelves.reloads?({:entities_changed, %{}})
      assert Shelves.reloads?({:integration_availability_changed, :tmdb, :up})
      refute Shelves.reloads?({:integration_availability_changed, :prowlarr, :up})
      refute Shelves.reloads?({:playback_state_changed, %{}})
    end
  end
end
