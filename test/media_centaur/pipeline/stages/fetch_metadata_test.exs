defmodule MediaCentaur.Pipeline.Stages.FetchMetadataTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.FetchMetadata

  import MediaCentaur.TestFactory
  import MediaCentaur.TmdbStubs

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
      # Library Schema v2 Phase 2 Task I — the file path lives on the
      # published event (added by `Pipeline.Stages.Ingest`), not on the
      # metadata's entity attrs.
      refute Map.has_key?(metadata.entity_attrs, :content_url)
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

    test "child movie attrs carry the full standalone-movie metadata" do
      stub_routes([
        {"/movie/155",
         movie_in_collection_detail(%{
           "status" => "Released",
           "vote_count" => 1234,
           "tagline" => "A sample tagline.",
           "credits" => %{
             "cast" => [
               %{
                 "id" => 42,
                 "name" => "Sample Actor",
                 "character" => "Lead",
                 "profile_path" => "/actor.jpg",
                 "order" => 0
               }
             ],
             "crew" => [
               %{"department" => "Directing", "job" => "Director", "name" => "A. Director"}
             ]
           }
         })},
        {"/collection/263", collection_detail()}
      ])

      payload = payload_for(%{tmdb_id: 155, title: "Sample Movie Two", year: 2008})

      assert {:ok, result} = FetchMetadata.run(payload)
      attrs = result.metadata.child_movie.attrs

      assert [%{"name" => "Sample Actor", "character" => "Lead"}] = attrs.cast
      assert [%{"name" => "A. Director", "job" => "Director"}] = attrs.crew
      assert attrs.genres == ["Drama"]
      assert attrs.status == :released
      assert attrs.vote_count == 1234
      assert attrs.tagline == "A sample tagline."
      assert attrs.director == "A. Director"
      assert attrs.position == 1
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

      # Even when the collection fetch fails we must carry the collection's
      # TMDB id, so the MovieSeries gets a `tmdb_collection` ExternalId. Without
      # it the container is un-findable (the next movie mints a duplicate) and
      # un-repairable (image-repair skips owners with no tmdb id).
      assert metadata.entity_attrs.tmdb_id == "263"
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
      # Library Schema v2 Phase 2 Task I — the file path lives on the
      # published event (added by `Pipeline.Stages.Ingest`), not on the
      # episode attrs.
      refute Map.has_key?(episode.attrs, :content_url)
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

    test "diverts to reconciliation when the parsed season isn't in TMDB's season list" do
      # TMDB lists seasons 0 and 1; a file labelled S02 is the cour /
      # absolute-numbering case — divert instead of minting a phantom.
      stub_routes([
        {"/tv/1396", tv_detail(%{"seasons" => [%{"season_number" => 0}, %{"season_number" => 1}]})}
      ])

      payload =
        payload_for(%{
          tmdb_id: 1396,
          tmdb_type: :tv,
          type: :tv,
          season: 2,
          episode: 1,
          file_path: "/media/TV/Sample.Show.S02E01.mkv"
        })

      assert {:ok, result} = FetchMetadata.run(payload)
      metadata = result.metadata

      # No phantom season is built.
      assert metadata.season == nil
      assert metadata.divert.tmdb_id == 1396
      assert metadata.divert.claimed_season == 2
      assert metadata.divert.claimed_episode == 1
    end

    test "does not divert when the parsed season is canonical" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail(%{"seasons" => [%{"season_number" => 1}]})}
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
      assert result.metadata.divert == nil
      assert result.metadata.season.season_number == 1
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

  # The Status page's metadata-activity feed is fed by this event — it's the
  # one piece of enrichment signal that carries the resolved title (the stage
  # wrapper's telemetry only knows the file path). A failed fetch emits nothing.
  describe "enrichment telemetry" do
    setup do
      test_pid = self()

      :telemetry.attach(
        "test-metadata-enriched",
        [:media_centaur, :metadata, :enriched],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:enriched, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-metadata-enriched") end)
    end

    test "emits a metadata.enriched event with kind and title on movie success" do
      stub_routes([{"/movie/550", movie_detail()}])

      assert {:ok, _result} = FetchMetadata.run(payload_for())

      assert_received {:enriched, metadata}
      assert metadata.kind == :movie
      assert metadata.title == "Sample Movie"
    end

    test "emits nothing when the fetch fails" do
      stub_tmdb_error("/movie/550", 500)

      assert {:error, _reason} = FetchMetadata.run(payload_for())

      refute_received {:enriched, _metadata}
    end
  end
end
