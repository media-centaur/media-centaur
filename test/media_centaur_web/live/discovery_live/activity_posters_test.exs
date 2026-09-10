defmodule MediaCentaurWeb.DiscoveryLive.ActivityPostersTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.ActivityPosters

  defp activity(tmdb_id, media_type, poster_path \\ nil) do
    %Activity{
      id: Ecto.UUID.generate(),
      tmdb_id: tmdb_id,
      media_type: media_type,
      title:
        Title.new!(%{
          tmdb_id: tmdb_id,
          media_type: media_type,
          name: "Sample Title #{tmdb_id}",
          poster_path: poster_path
        })
    }
  end

  describe "library_refs/1" do
    test "turns the TMDB owner map into the entity refs Library.Posters reads" do
      owners = %{{3219, :tv_series} => "series-id", {550, :movie} => "movie-id"}

      assert Enum.sort(ActivityPosters.library_refs(owners)) ==
               Enum.sort([{:tv_series, "series-id"}, {:movie, "movie-id"}])
    end

    test "is empty when this install owns none of the identities" do
      assert ActivityPosters.library_refs(%{}) == []
    end
  end

  describe "url/3" do
    test "prefers the library entity's own poster when this install owns the title" do
      owners = %{{3219, :tv_series} => "series-id"}
      library = %{{:tv_series, "series-id"} => "/media-images/series-id/poster.jpg"}

      assert ActivityPosters.url(activity(3219, :tv_series, "/p.jpg"), owners, library) ==
               "/media-images/series-id/poster.jpg"
    end

    test "falls back to the TMDB hotlink for a title no entity owns" do
      assert ActivityPosters.url(activity(550, :movie, "/p.jpg"), %{}, %{}) ==
               "https://image.tmdb.org/t/p/w92/p.jpg"
    end

    test "falls back past an owned entity that carries no poster of its own" do
      owners = %{{550, :movie} => "movie-id"}

      assert ActivityPosters.url(activity(550, :movie, "/p.jpg"), owners, %{}) ==
               "https://image.tmdb.org/t/p/w92/p.jpg"
    end

    test "is nil when no tier holds artwork — an activity snapshot carries no poster path" do
      assert ActivityPosters.url(activity(550, :movie), %{}, %{}) == nil
    end
  end

  describe "missing/1" do
    test "names each identity whose row resolved to no artwork at all, once" do
      rows = [
        %{activity: activity(550, :movie), poster_url: nil},
        %{activity: activity(550, :movie), poster_url: nil},
        %{activity: activity(3219, :tv_series), poster_url: nil},
        %{activity: activity(615, :tv_series), poster_url: "/media-images/x/poster.jpg"}
      ]

      assert Enum.sort(ActivityPosters.missing(rows)) ==
               Enum.sort([{550, :movie}, {3219, :tv_series}])
    end

    test "is empty when every row painted something" do
      rows = [%{activity: activity(615, :tv_series), poster_url: "/media-images/x/poster.jpg"}]

      assert ActivityPosters.missing(rows) == []
    end
  end
end
