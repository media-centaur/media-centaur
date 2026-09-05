defmodule MediaCentaur.Pipeline.ProducerTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Discovery.Producer, as: DiscoveryProducer
  alias MediaCentaur.Pipeline.Import.Producer, as: ImportProducer
  alias MediaCentaur.Pipeline.Payload

  describe "DiscoveryProducer.build_payload/1" do
    test "builds payload with file_path and media_directory" do
      payload =
        DiscoveryProducer.build_payload(%{
          path: "/media/movies/Fight.Club.1999.mkv",
          media_dir: "/media/movies"
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.media_directory == "/media/movies"
      assert payload.tmdb_id == nil
      assert payload.tmdb_type == nil
      assert payload.pending_file_id == nil
    end
  end

  describe "ImportProducer.build_payload/1" do
    test "builds payload with tmdb_id, tmdb_type, and no pending_file_id" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Fight.Club.1999.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: :movie
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.media_directory == "/media/movies"
      assert payload.tmdb_id == 550
      assert payload.tmdb_type == :movie
      assert payload.pending_file_id == nil
    end

    test "builds payload with pending_file_id for review-resolved" do
      pending_id = Ecto.UUID.generate()

      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Ambiguous.Title.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: :movie,
          pending_file_id: pending_id
        })

      assert %Payload{} = payload
      assert payload.tmdb_id == 550
      assert payload.tmdb_type == :movie
      assert payload.pending_file_id == pending_id
    end

    test "normalizes string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/tv/Some.Show.S01E01.mkv",
          media_dir: "/media/tv",
          tmdb_id: 1399,
          tmdb_type: "tv"
        })

      assert payload.tmdb_type == :tv
    end

    test "normalizes movie string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Movie.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: "movie"
        })

      assert payload.tmdb_type == :movie
    end
  end

  describe "DiscoveryProducer.reconcile_action/2" do
    test "runs immediately once the watcher reports running, regardless of attempt count" do
      assert DiscoveryProducer.reconcile_action(0, true) == :run
      assert DiscoveryProducer.reconcile_action(19, true) == :run
    end

    test "retries with a delay while the watcher isn't running yet and attempts remain" do
      assert {:retry, delay} = DiscoveryProducer.reconcile_action(0, false)
      # `is_integer(delay)` is proven by the type checker since Elixir 1.20
      # (asserting it is a compile warning); the bound is the real check.
      assert delay > 0
    end

    test "gives up silently once the attempt budget is exhausted" do
      # Startup reconciliation is a one-time opportunity racing against
      # `MediaCentaur.Watcher.Supervisor.start_watchers/0` (ADR-023) — it must
      # not retry forever, and it must not treat a deliberately-disabled
      # watcher (`services:*:start_watchers` off) as an error worth logging.
      assert DiscoveryProducer.reconcile_action(DiscoveryProducer.max_reconcile_attempts(), false) ==
               :skip
    end
  end
end
