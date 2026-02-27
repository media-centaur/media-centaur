defmodule MediaManager.Pipeline.Stages.IngestTest do
  @moduledoc """
  Tests for the Phase 1 Ingest bridge that delegates to EntityResolver.
  """
  use MediaManager.DataCase

  alias MediaManager.Pipeline.Payload
  alias MediaManager.Pipeline.Stages.Ingest
  alias MediaManager.Library.Entity
  alias MediaManager.Parser

  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
  end

  defp payload_for(overrides \\ %{}) do
    defaults = %{
      title: "Fight Club",
      year: 1999,
      type: :movie,
      season: nil,
      episode: nil,
      parent_title: nil,
      parent_year: nil,
      file_path: "/media/Fight.Club.1999.mkv",
      episode_title: nil
    }

    parsed = struct(Parser.Result, Map.merge(defaults, overrides))

    %Payload{
      file_path: parsed.file_path,
      parsed: parsed,
      tmdb_id: overrides[:tmdb_id] || 550,
      tmdb_type: overrides[:tmdb_type] || :movie,
      confidence: 0.95
    }
  end

  # ---------------------------------------------------------------------------
  # Movie
  # ---------------------------------------------------------------------------

  describe "movie ingestion" do
    test "creates a movie entity via EntityResolver" do
      stub_routes([{"/movie/550", movie_detail()}])

      payload = payload_for()

      assert {:ok, result} = Ingest.run(payload)
      assert result.entity_id != nil
      assert result.ingest_status == :new

      entity = Ash.get!(Entity, result.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"
    end

    test "reuses existing entity on second ingest" do
      stub_routes([{"/movie/550", movie_detail()}])

      payload = payload_for()
      assert {:ok, first} = Ingest.run(payload)

      # Second ingest for same TMDB ID
      second_payload =
        payload_for(%{file_path: "/media/Fight.Club.1999.other.mkv"})

      assert {:ok, second} = Ingest.run(second_payload)
      assert second.entity_id == first.entity_id
      assert second.ingest_status == :existing
    end
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  describe "movie in collection" do
    test "creates movie series entity with child movie" do
      stub_routes([
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      payload =
        payload_for(%{
          tmdb_id: 155,
          title: "The Shadowy Sentinel",
          year: 2008,
          file_path: "/media/The.Shadowy.Sentinel.2008.mkv"
        })

      assert {:ok, result} = Ingest.run(payload)
      assert result.entity_id != nil

      entity = Ash.get!(Entity, result.entity_id, action: :with_associations)
      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"
      assert length(entity.movies) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # TV
  # ---------------------------------------------------------------------------

  describe "TV ingestion" do
    test "creates TV entity with season and episode" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail()}
      ])

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          title: "Sample Show Eight",
          year: 2008,
          type: :tv,
          season: 1,
          episode: 1,
          file_path: "/media/TV/Sample.Show.Eight.S01E01.mkv"
        })

      assert {:ok, result} = Ingest.run(payload)
      assert result.entity_id != nil
      assert result.ingest_status == :new

      entity = Ash.get!(Entity, result.entity_id, action: :with_associations)
      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"
      assert length(entity.seasons) == 1
      assert length(hd(entity.seasons).episodes) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "TMDB detail fetch failure returns error" do
      stub_tmdb_error("/movie/999", 500)

      payload = payload_for(%{tmdb_id: 999})

      assert {:error, _reason} = Ingest.run(payload)
    end
  end
end
