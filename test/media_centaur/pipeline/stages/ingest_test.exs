defmodule MediaCentaur.Pipeline.Stages.IngestTest do
  @moduledoc """
  Tests for the Ingest stage wrapper that delegates to Library.Ingress.

  No TMDB stubs needed: Ingress consumes pre-built metadata, not TMDB data.
  """
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.Ingest
  alias MediaCentaur.Library.Entity

  defp movie_payload(overrides \\ %{}) do
    metadata =
      Map.merge(
        %{
          entity_type: :movie,
          entity_attrs: %{
            type: :movie,
            name: "Fight Club",
            description: "An insomniac office worker...",
            date_published: "1999-10-15",
            content_url: "/media/Fight.Club.1999.mkv",
            url: "https://www.themoviedb.org/movie/550"
          },
          images: [
            %{role: "poster", url: "https://image.tmdb.org/poster.jpg", extension: "jpg"}
          ],
          identifier: %{property_id: "tmdb", value: "550"},
          child_movie: nil,
          season: nil,
          extra: nil
        },
        overrides[:metadata] || %{}
      )

    %Payload{
      file_path: "/media/Fight.Club.1999.mkv",
      tmdb_id: overrides[:tmdb_id] || 550,
      tmdb_type: overrides[:tmdb_type] || :movie,
      metadata: metadata,
      staged_images: overrides[:staged_images] || []
    }
  end

  # ---------------------------------------------------------------------------
  # Movie
  # ---------------------------------------------------------------------------

  describe "movie ingestion" do
    test "creates a movie entity via Ingress" do
      payload = movie_payload()

      assert {:ok, result} = Ingest.run(payload)
      assert result.entity_id != nil
      assert result.ingest_status == :new

      entity = Ash.get!(Entity, result.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"
    end

    test "reuses existing entity on second ingest" do
      payload = movie_payload()
      assert {:ok, first} = Ingest.run(payload)

      # Second ingest for same TMDB ID — uses different file path
      second_payload =
        movie_payload(
          metadata: %{
            entity_attrs: %{
              type: :movie,
              name: "Fight Club",
              content_url: "/media/Fight.Club.1999.other.mkv"
            }
          }
        )

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
      payload = %Payload{
        file_path: "/media/The.Shadowy.Sentinel.2008.mkv",
        tmdb_id: 155,
        tmdb_type: :movie,
        metadata: %{
          entity_type: :movie_series,
          entity_attrs: %{
            type: :movie_series,
            name: "The Shadowy Sentinel Collection"
          },
          images: [],
          identifier: %{property_id: "tmdb_collection", value: "263"},
          child_movie: %{
            attrs: %{
              tmdb_id: "155",
              name: "The Shadowy Sentinel",
              content_url: "/media/The.Shadowy.Sentinel.2008.mkv",
              position: 1
            },
            images: [],
            identifier: %{property_id: "tmdb", value: "155"}
          },
          season: nil,
          extra: nil
        },
        staged_images: []
      }

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
      payload = %Payload{
        file_path: "/media/TV/Sample.Show.Eight.S01E01.mkv",
        tmdb_id: 1396,
        tmdb_type: :tv,
        metadata: %{
          entity_type: :tv_series,
          entity_attrs: %{
            type: :tv_series,
            name: "Sample Show Eight",
            number_of_seasons: 5
          },
          images: [],
          identifier: %{property_id: "tmdb", value: "1396"},
          child_movie: nil,
          season: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 7,
            episode: %{
              attrs: %{
                episode_number: 1,
                name: "Pilot",
                content_url: "/media/TV/Sample.Show.Eight.S01E01.mkv"
              },
              images: []
            }
          },
          extra: nil
        },
        staged_images: []
      }

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
    test "nil metadata raises" do
      payload = %Payload{metadata: nil, staged_images: []}

      assert_raise BadMapError, fn ->
        Ingest.run(payload)
      end
    end
  end
end
