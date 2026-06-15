defmodule MediaCentaur.Pipeline.ImageRefreshWorkerTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Pipeline.ImageRefreshWorker
  alias MediaCentaur.TestFactory
  alias MediaCentaur.Topics

  setup :setup_tmdb_client

  setup do
    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())
    :ok
  end

  test "perform/1 refreshes artwork for the entity" do
    movie = TestFactory.create_movie(%{name: "Sample Movie", tmdb_id: "550"})
    TestFactory.create_linked_file(%{movie_id: movie.id, media_dir: "/media/movies"})
    stub_get_movie("550", movie_detail(%{"poster_path" => "/p.jpg"}))

    job = %Oban.Job{args: %{"entity_id" => movie.id, "entity_type" => "movie"}}
    assert :ok = ImageRefreshWorker.perform(job)

    assert_receive {:enqueue_images, %{entity_id: entity_id}}
    assert entity_id == movie.id
  end

  test "perform/1 cancels (no retry) when the entity is unidentified" do
    movie = TestFactory.create_movie(%{name: "Sample Movie"})
    job = %Oban.Job{args: %{"entity_id" => movie.id, "entity_type" => "movie"}}
    assert {:cancel, :no_tmdb_id} = ImageRefreshWorker.perform(job)
  end

  test "perform/1 cancels (no retry) on an unrecognized entity_type" do
    job = %Oban.Job{args: %{"entity_id" => "abc", "entity_type" => "bogus"}}
    assert {:cancel, {:bad_entity_type, "bogus"}} = ImageRefreshWorker.perform(job)
  end
end
