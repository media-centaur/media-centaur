defmodule MediaCentaur.Pipeline.ProducerTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Producer
  alias MediaCentaur.Pipeline.Payload

  describe "build_payload/2" do
    test ":file_detected builds payload with correct fields" do
      payload =
        Producer.build_payload(:file_detected, %{
          path: "/media/movies/Fight.Club.1999.mkv",
          watch_dir: "/media/movies"
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.watch_directory == "/media/movies"
      assert payload.entry_point == :file_detected
      assert payload.tmdb_id == nil
      assert payload.tmdb_type == nil
      assert payload.pending_file_id == nil
    end

    test ":review_resolved builds payload with tmdb_id, tmdb_type, and pending_file_id" do
      pending_id = Ecto.UUID.generate()

      payload =
        Producer.build_payload(:review_resolved, %{
          path: "/media/movies/Ambiguous.Title.mkv",
          watch_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: "movie",
          pending_file_id: pending_id
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Ambiguous.Title.mkv"
      assert payload.watch_directory == "/media/movies"
      assert payload.entry_point == :review_resolved
      assert payload.tmdb_id == 550
      assert payload.tmdb_type == :movie
      assert payload.pending_file_id == pending_id
    end

    test ":review_resolved normalizes string tmdb_type to atom for tv" do
      payload =
        Producer.build_payload(:review_resolved, %{
          path: "/media/tv/Some.Show.S01E01.mkv",
          watch_dir: "/media/tv",
          tmdb_id: 1399,
          tmdb_type: "tv",
          pending_file_id: Ecto.UUID.generate()
        })

      assert payload.tmdb_type == :tv
    end
  end
end
