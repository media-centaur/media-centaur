defmodule MediaCentaurWeb.DiscoveryLive.ActivityArtworkTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.ActivityArtwork

  defp activity(tmdb_id, media_type, poster_path \\ nil, backdrop_path \\ nil) do
    %Activity{
      id: Ecto.UUID.generate(),
      tmdb_id: tmdb_id,
      media_type: media_type,
      title:
        Title.new!(%{
          tmdb_id: tmdb_id,
          media_type: media_type,
          name: "Sample Title #{tmdb_id}",
          poster_path: poster_path,
          backdrop_path: backdrop_path
        })
    }
  end

  @library %{
    "poster" => %{{:tv_series, "series-id"} => "/media-images/series-id/poster.jpg"},
    "backdrop" => %{{:tv_series, "series-id"} => "/media-images/series-id/backdrop.jpg"}
  }
  @empty %{"poster" => %{}, "backdrop" => %{}}

  describe "library_refs/1" do
    test "turns the TMDB owner map into the entity refs Library.Artwork reads" do
      owners = %{{3219, :tv_series} => "series-id", {550, :movie} => "movie-id"}

      assert Enum.sort(ActivityArtwork.library_refs(owners)) ==
               Enum.sort([{:tv_series, "series-id"}, {:movie, "movie-id"}])
    end

    test "is empty when this install owns none of the identities" do
      assert ActivityArtwork.library_refs(%{}) == []
    end
  end

  describe "urls/3" do
    test "the library tier serves both roles for an owned title" do
      owners = %{{3219, :tv_series} => "series-id"}

      assert ActivityArtwork.urls(activity(3219, :tv_series, "/p.jpg", "/b.jpg"), owners, @library) == %{
               poster_url: "/media-images/series-id/poster.jpg",
               backdrop_url: "/media-images/series-id/backdrop.jpg"
             }
    end

    test "each role falls independently: an owned entity without a backdrop falls to the next tier" do
      owners = %{{3219, :tv_series} => "series-id"}
      library = %{"poster" => @library["poster"], "backdrop" => %{}}

      assert ActivityArtwork.urls(activity(3219, :tv_series), owners, library) ==
               %{poster_url: "/media-images/series-id/poster.jpg", backdrop_url: nil}
    end

    test "the hotlink asks TMDB for a poster the band can paint and a backdrop the box can" do
      assert ActivityArtwork.urls(activity(550, :movie, "/p.jpg", "/b.jpg"), %{}, @empty) == %{
               poster_url: "https://image.tmdb.org/t/p/w185/p.jpg",
               backdrop_url: "https://image.tmdb.org/t/p/w1280/b.jpg"
             }
    end

    test "falls back past an owned entity that carries no image of its own" do
      owners = %{{550, :movie} => "movie-id"}

      assert ActivityArtwork.urls(activity(550, :movie, "/p.jpg"), owners, @empty) ==
               %{poster_url: "https://image.tmdb.org/t/p/w185/p.jpg", backdrop_url: nil}
    end

    test "nothing on any tier is nil for both — the snapshot carries no paths" do
      assert ActivityArtwork.urls(activity(550, :movie), %{}, @empty) == %{
               poster_url: nil,
               backdrop_url: nil
             }
    end
  end

  describe "missing/1" do
    test "names each identity whose row painted nothing for either role, once" do
      rows = [
        %{activity: activity(550, :movie), poster_url: nil, backdrop_url: nil},
        %{activity: activity(550, :movie), poster_url: "/media-images/x/poster.jpg", backdrop_url: nil},
        %{
          activity: activity(3219, :tv_series),
          poster_url: nil,
          backdrop_url: "/media-images/y/backdrop.jpg"
        },
        %{activity: activity(615, :tv_series), poster_url: "/p.jpg", backdrop_url: "/b.jpg"}
      ]

      assert Enum.sort(ActivityArtwork.missing(rows)) == Enum.sort([{550, :movie}, {3219, :tv_series}])
    end

    test "is empty when every row painted both" do
      rows = [%{activity: activity(615, :tv_series), poster_url: "/p.jpg", backdrop_url: "/b.jpg"}]

      assert ActivityArtwork.missing(rows) == []
    end
  end
end
