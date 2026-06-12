defmodule MediaCentaur.Pipeline.EntityImageContextTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.EntityImageContext, as: Context
  alias MediaCentaur.TestFactory

  describe "find_tmdb_context/2" do
    test "returns the tmdb id for an identified movie" do
      movie = TestFactory.create_movie(%{name: "Sample Movie", tmdb_id: "550"})
      assert {:ok, "550"} = Context.find_tmdb_context(movie.id, :movie)
    end

    test "skips an unidentified movie" do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})
      assert {:skip, :no_tmdb_id} = Context.find_tmdb_context(movie.id, :movie)
    end
  end

  describe "find_media_dir/2" do
    test "returns the media dir of a movie's linked file" do
      movie = TestFactory.create_movie(%{name: "Sample Movie", tmdb_id: "550"})
      TestFactory.create_linked_file(%{movie_id: movie.id, media_dir: "/media/movies"})

      assert {:ok, "/media/movies"} = Context.find_media_dir(movie.id, :movie)
    end

    test "skips a movie with no files" do
      movie = TestFactory.create_movie(%{name: "Sample Movie", tmdb_id: "550"})
      assert {:skip, :no_media_dir} = Context.find_media_dir(movie.id, :movie)
    end
  end
end
