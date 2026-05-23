defmodule MediaCentaur.Pipeline.ProducerTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Discovery.Producer, as: DiscoveryProducer
  alias MediaCentaur.Pipeline.Import.Producer, as: ImportProducer
  alias MediaCentaur.Pipeline.Payload

  describe "DiscoveryProducer.build_payload/1" do
    test "builds payload with file_path and watch_directory" do
      payload =
        DiscoveryProducer.build_payload(%{
          path: "/media/movies/Fight.Club.1999.mkv",
          watch_dir: "/media/movies"
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.watch_directory == "/media/movies"
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
          watch_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: :movie
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.watch_directory == "/media/movies"
      assert payload.tmdb_id == 550
      assert payload.tmdb_type == :movie
      assert payload.pending_file_id == nil
    end

    test "builds payload with pending_file_id for review-resolved" do
      pending_id = Ecto.UUID.generate()

      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Ambiguous.Title.mkv",
          watch_dir: "/media/movies",
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
          watch_dir: "/media/tv",
          tmdb_id: 1399,
          tmdb_type: "tv"
        })

      assert payload.tmdb_type == :tv
    end

    test "normalizes movie string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Movie.mkv",
          watch_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: "movie"
        })

      assert payload.tmdb_type == :movie
    end
  end
end
