defmodule MediaCentarr.Pipeline.Stages.FetchMetadataTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Pipeline.Payload
  alias MediaCentarr.Pipeline.Stages.FetchMetadata

  import MediaCentarr.TestFactory
  import MediaCentarr.TmdbStubs

  setup do
    setup_tmdb_client()
  end

  defp payload_for(overrides \\ %{}) do
    parsed = build_parser_result(Map.drop(overrides, [:tmdb_id, :tmdb_type]))

    %Payload{
      file_path: parsed.file_path,
      parsed: parsed,
      tmdb_id: overrides[:tmdb_id] || 550,
      tmdb_type: overrides[:tmdb_type] || :movie
    }
  end

  # ---------------------------------------------------------------------------
  # Standalone movie
  # ---------------------------------------------------------------------------

  describe "standalone movie" do
    test "fetches movie details and builds metadata" do
      stub_routes([{"/movie/550", movie_detail()}])

      payload = payload_for()

      assert {:ok, result} = FetchMetadata.run(payload)
      metadata = result.metadata

      assert metadata.entity_type == :movie
      assert metadata.entity_attrs.name == "Sample Movie"
      assert metadata.entity_attrs.type == :movie
      assert metadata.entity_attrs.content_url == "/media/Sample.Movie.1999.mkv"
      assert metadata.identifier == %{source: "tmdb", external_id: "550"}
      refute metadata.images == []
      assert Enum.any?(metadata.images, &(&1.role == "poster"))
      assert is_nil(metadata.child_movie)
      assert is_nil(metadata.season)
    end

    test "includes backdrop image when available" do
      stub_routes([{"/movie/550", movie_detail()}])

      payload = payload_for()

      assert {:ok, result} = FetchMetadata.run(payload)
      assert Enum.any?(result.metadata.images, &(&1.role == "backdrop"))
    end
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  describe "movie in collection" do
    test "fetches collection details and builds movie series metadata" do
      stub_routes([
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      payload = payload_for(%{tmdb_id: 155, title: "Sample Movie Two", year: 2008})

      assert {:ok, result} = FetchMetadata.run(payload)
      metadata = result.metadata

      assert metadata.entity_type == :movie_series
      assert metadata.entity_attrs.name == "Sample Movie Collection"
      assert metadata.identifier == %{source: "tmdb_collection", external_id: "263"}

      child = metadata.child_movie
      assert child != nil
      assert child.attrs.name == "Sample Movie Two"
      assert child.identifier == %{source: "tmdb", external_id: "155"}
      assert child.attrs.position == 1
    end

    test "handles collection fetch failure gracefully" do
      stub_routes([
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", {:error, 500}}
      ])

      payload = payload_for(%{tmdb_id: 155, title: "Sample Movie Two", year: 2008})

      assert {:ok, result} = FetchMetadata.run(payload)
      metadata = result.metadata

      assert metadata.entity_type == :movie_series
      assert metadata.entity_attrs.name == "Sample Movie Collection"
      assert metadata.child_movie.attrs.position == 0
    end
  end

  # ---------------------------------------------------------------------------
  # TV series
  # ---------------------------------------------------------------------------

  describe "TV series" do
    test "fetches TV and season details" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail()}
      ])

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          title: "Sample Show",
          year: 2008,
          type: :tv,
          season: 1,
          episode: 1,
          file_path: "/media/TV/Sample.Show.S01E01.mkv"
        })

      assert {:ok, result} = FetchMetadata.run(payload)
      metadata = result.metadata

      assert metadata.entity_type == :tv_series
      assert metadata.entity_attrs.name == "Sample Show"
      assert metadata.entity_attrs.number_of_seasons == 5
      assert metadata.identifier == %{source: "tmdb", external_id: "1396"}

      season = metadata.season
      assert season.season_number == 1
      assert season.name == "Season 1"
      assert season.number_of_episodes == 2

      episode = season.episode
      assert episode.attrs.episode_number == 1
      assert episode.attrs.name == "Pilot"
      assert episode.attrs.content_url == "/media/TV/Sample.Show.S01E01.mkv"
    end

    test "includes episode thumbnail when available" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail()}
      ])

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          type: :tv,
          season: 1,
          episode: 1,
          file_path: "/media/TV/Sample.Show.S01E01.mkv"
        })

      assert {:ok, result} = FetchMetadata.run(payload)
      episode = result.metadata.season.episode

      assert length(episode.images) == 1
      assert hd(episode.images).role == "thumb"
    end

    test "builds minimal season when TMDB season fetch fails" do
      stub_routes([
        {"/tv/1396/season/1", {:error, 500}},
        {"/tv/1396", tv_detail()}
      ])

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          type: :tv,
          season: 1,
          episode: 1,
          file_path: "/media/TV/Sample.Show.S01E01.mkv"
        })

      assert {:ok, result} = FetchMetadata.run(payload)
      season = result.metadata.season

      assert season.season_number == 1
      assert season.name == "Season 1"
      assert season.number_of_episodes == 0
      assert season.episode.attrs.episode_number == 1
      assert season.episode.images == []
    end
  end

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  describe "errors" do
    test "movie detail fetch failure returns error" do
      stub_tmdb_error("/movie/550", 500)

      payload = payload_for()

      assert {:error, _reason} = FetchMetadata.run(payload)
    end

    test "TV detail fetch failure returns error" do
      stub_tmdb_error("/tv/1396", 500)

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          type: :tv,
          season: 1,
          episode: 1
        })

      assert {:error, _reason} = FetchMetadata.run(payload)
    end
  end
end
