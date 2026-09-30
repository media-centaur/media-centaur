defmodule MediaCentaur.Pipeline.ImageRefreshTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Pipeline.ImageQueue
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

      assert Enum.any?(
               ImageQueue.list_pending(movie.id),
               &String.ends_with?(&1.source_url, "/stored.jpg")
             )
    end

    # Changed 2026-09-30 (campaign durable-work, F11): the refresh writes the
    # queue rows itself and nudges the image pipeline; it used to hand them
    # over in an `enqueue_images` message the producer turned into rows, so a
    # lost message left the refresh reported done with nothing queued.
    test "queues the TMDB artwork for a movie as stored rows, and nudges the image pipeline" do
      movie = identified_movie()
      stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg", "backdrop_path" => "/b.jpg"}))

      assert {:ok, count} = ImageRefresh.refresh_entity(movie.id, :movie)
      assert count >= 2

      queued = ImageQueue.list_pending(movie.id)
      roles = Enum.map(queued, & &1.role)
      assert "poster" in roles and "backdrop" in roles
      assert Enum.all?(queued, &(&1.owner_id == movie.id and &1.owner_type == "movie"))
      assert Enum.all?(queued, &(&1.media_dir == "/media/movies"))

      movie_id = movie.id
      assert_receive {:images_pending, %{entity_id: ^movie_id, media_dir: "/media/movies"}}
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
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert ImageQueue.list_pending(movie.id) == []
    end

    # Regression: unique on entity_id for 60 s counted completed jobs, so a
    # second refresh a person asked for soon after the first finished was
    # silently not enqueued (ADR-077, rule 6).
    test "a refresh asked for after the last one finished is enqueued" do
      movie = identified_movie()
      stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg"}))

      assert {:ok, _job} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert ImageQueue.list_pending(movie.id) != []

      assert {:ok, %Oban.Job{conflict?: false}} = ImageRefresh.enqueue_refresh(movie.id, :movie)
    end

    test "a second refresh while one waits collapses into it" do
      movie = identified_movie()

      assert {:ok, %Oban.Job{conflict?: false}} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      assert {:ok, %Oban.Job{conflict?: true}} = ImageRefresh.enqueue_refresh(movie.id, :movie)
    end

    test "enqueues a refresh that, run, refreshes an identified movie" do
      movie = identified_movie()
      stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg"}))

      assert {:ok, _job} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert [_poster | _] = ImageQueue.list_pending(movie.id)
    end
  end
end
