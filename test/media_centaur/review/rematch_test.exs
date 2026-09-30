defmodule MediaCentaur.Review.RematchTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Review
  alias MediaCentaur.Review.{Rematch, RematchJob}

  defp matched_movie do
    movie =
      create_entity(%{
        type: :movie,
        name: "Wrong Movie",
        content_url: "/media/movies/Sample Movie (2017).mkv"
      })

    create_linked_file(%{
      movie_id: movie.id,
      file_path: "/media/movies/Sample Movie (2017).mkv",
      media_dir: "/media/movies"
    })

    movie
  end

  describe "rematch_entity/1" do
    # Regression (campaign durable-work, F9): a rematch rode two PubSub hops
    # — Review to the library's teardown, then the files back to Review. A
    # lost second hop left the files unlinked and in no queue, until a
    # restart re-discovered them and could re-import the very match the
    # person was fixing.
    test "records the rematch as a job and changes nothing yet" do
      movie = matched_movie()

      assert :ok = Rematch.rematch_entity(movie.id)

      assert_enqueued(worker: RematchJob, args: %{"entity_id" => movie.id})
      assert [_file] = Library.Files.list_by_entity_id(movie.id)
    end

    test "the job releases the entity and puts its files in review, together" do
      movie = matched_movie()
      :ok = Rematch.rematch_entity(movie.id)

      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert {:error, _gone} = Library.Containers.fetch(:movie, movie.id)
      assert [pending] = Review.list_pending_files_for_review()
      assert pending.file_path == "/media/movies/Sample Movie (2017).mkv"
    end

    test "a job for an entity already released does nothing" do
      assert :ok = perform_job(RematchJob, %{"entity_id" => Ecto.UUID.generate()})
      assert Review.list_pending_files_for_review() == []
    end
  end
end
