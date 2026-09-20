defmodule MediaCentaur.Pipeline.ImageRefreshTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Pipeline.ImageRefresh
  alias MediaCentaur.TestFactory
  alias MediaCentaur.Topics

  setup :setup_tmdb_client

  setup do
    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())
    :ok
  end

  defp identified_movie do
    movie = TestFactory.create_movie(%{name: "Sample Movie", tmdb_id: "550"})
    TestFactory.create_linked_file(%{movie_id: movie.id, media_dir: "/media/movies"})
    movie
  end

  describe "refresh_entity/2" do
    test "a title the store holds is read without a request (ADR-071)" do
      movie = identified_movie()

      TestFactory.create_title_record(%{
        tmdb_id: 550,
        media_type: :movie,
        payload: movie_detail(%{"id" => 550, "poster_path" => "/stored.jpg"})
      })

      stub_tmdb_error("/movie/550", 500)

      assert {:ok, count} = ImageRefresh.refresh_entity(movie.id, :movie)
      assert count >= 1
      assert_receive {:enqueue_images, %{images: images}}
      assert Enum.any?(images, &String.ends_with?(&1.source_url, "/stored.jpg"))
    end

    test "broadcasts enqueue_images with the TMDB artwork for a movie" do
      movie = identified_movie()
      stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg", "backdrop_path" => "/b.jpg"}))

      assert {:ok, count} = ImageRefresh.refresh_entity(movie.id, :movie)
      assert count >= 2

      assert_receive {:enqueue_images,
                      %{entity_id: entity_id, media_dir: "/media/movies", images: images}}

      assert entity_id == movie.id
      roles = Enum.map(images, & &1.role)
      assert "poster" in roles and "backdrop" in roles
      assert Enum.all?(images, &(&1.owner_id == movie.id and &1.owner_type == "movie"))
    end

    test "errors with :no_tmdb_id for an unidentified entity" do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})
      assert {:error, :no_tmdb_id} = ImageRefresh.refresh_entity(movie.id, :movie)
    end
  end

  describe "enqueue_refresh/2" do
    test "errors with :no_tmdb_id without enqueuing for an unidentified entity" do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})

      assert {:error, :no_tmdb_id} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      refute_receive {:enqueue_images, _}, 100
    end

    test "enqueues and (inline) refreshes an identified movie" do
      movie = identified_movie()
      stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg"}))

      assert {:ok, _job} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      assert_receive {:enqueue_images, %{entity_id: entity_id}}
      assert entity_id == movie.id
    end
  end
end
