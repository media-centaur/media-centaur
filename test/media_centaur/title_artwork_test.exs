defmodule MediaCentaur.TitleArtworkTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TitleArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork

  # Identities unique to this file, so the referenced tier (a filesystem
  # check under the test data_dir) holds nothing for them unless a test
  # seeds it — which keeps the module `async: true`.
  defp title(tmdb_id, media_type, paths \\ []) do
    Title.new!(
      Map.merge(
        %{tmdb_id: tmdb_id, media_type: media_type, name: "Sample Title #{tmdb_id}"},
        Map.new(paths)
      )
    )
  end

  @library %{
    "poster" => "/media-images/owner/poster.jpg",
    "backdrop" => "/media-images/owner/backdrop.jpg",
    "logo" => "/media-images/owner/logo.png"
  }

  describe "urls/3" do
    test "the library tier wins for every role when the owned entity has the image" do
      assert TitleArtwork.urls(
               title(998_000_001, :movie, poster_path: "/p.jpg", backdrop_path: "/b.jpg"),
               @library,
               :w185
             ) ==
               %{
                 poster_url: "/media-images/owner/poster.jpg",
                 backdrop_url: "/media-images/owner/backdrop.jpg",
                 logo_url: "/media-images/owner/logo.png"
               }
    end

    test "each role falls independently: an owned entity without a backdrop takes the next tier's" do
      library = %{"poster" => "/media-images/owner/poster.jpg"}

      assert TitleArtwork.urls(title(998_000_002, :movie, backdrop_path: "/b.jpg"), library, :w185) == %{
               poster_url: "/media-images/owner/poster.jpg",
               backdrop_url: "https://image.tmdb.org/t/p/w1280/b.jpg",
               logo_url: nil
             }
    end

    test "the hotlink takes the poster at the width the surface paints and the backdrop at w1280" do
      assert TitleArtwork.urls(
               title(998_000_003, :tv_series, poster_path: "/p.jpg", backdrop_path: "/b.jpg"),
               %{},
               :w92
             ) ==
               %{
                 poster_url: "https://image.tmdb.org/t/p/w92/p.jpg",
                 backdrop_url: "https://image.tmdb.org/t/p/w1280/b.jpg",
                 logo_url: nil
               }
    end

    test "the referenced tier beats the hotlink" do
      path = TmdbArtwork.on_disk_path(:backdrop, :movie, 998_000_004)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "not-a-real-jpeg")
      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

      assert %{backdrop_url: "/media-images/" <> _, poster_url: "https://image.tmdb.org/t/p/w185/p.jpg"} =
               TitleArtwork.urls(
                 title(998_000_004, :movie, poster_path: "/p.jpg", backdrop_path: "/b.jpg"),
                 %{},
                 :w185
               )
    end

    test "nothing on any tier is nil for every role — an activity snapshot carries no paths" do
      assert TitleArtwork.urls(title(998_000_005, :movie), %{}, :w185) ==
               %{poster_url: nil, backdrop_url: nil, logo_url: nil}
    end

    test "a poster width outside TMDB's classes is refused" do
      bad_width = Enum.at([:w999], 0)

      assert_raise FunctionClauseError, fn ->
        TitleArtwork.urls(title(998_000_006, :movie, poster_path: "/p.jpg"), %{}, bad_width)
      end
    end
  end
end
