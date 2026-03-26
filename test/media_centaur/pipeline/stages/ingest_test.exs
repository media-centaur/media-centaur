defmodule MediaCentaur.Pipeline.Stages.IngestTest do
  @moduledoc """
  Tests for the Ingest stage — broadcasts entity events to pipeline:publish.

  No TMDB stubs needed: Ingest consumes pre-built metadata, not TMDB data.
  Entity creation is tested in Library.InboundTest — these tests verify the
  broadcast event format and payload passthrough.
  """
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.Ingest

  # Library.Inbound and Review.Intake don't start in test mode, so no
  # async DB conflicts from PubSub-triggered GenServer processing.

  setup do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_publish())
    :ok
  end

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
            %{role: "poster", url: "https://image.tmdb.org/poster.jpg"}
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
      watch_directory: "/media",
      tmdb_id: overrides[:tmdb_id] || 550,
      tmdb_type: overrides[:tmdb_type] || :movie,
      metadata: metadata
    }
  end

  # ---------------------------------------------------------------------------
  # Broadcast format
  # ---------------------------------------------------------------------------

  describe "entity publication" do
    test "broadcasts entity_published event with correct format" do
      payload = movie_payload()

      assert {:ok, result} = Ingest.run(payload)
      assert result.file_path == payload.file_path

      assert_receive {:entity_published, event}
      assert event.entity_type == :movie
      assert event.entity_attrs.name == "Fight Club"
      assert event.identifier == %{property_id: "tmdb", value: "550"}
      assert event.file_path == "/media/Fight.Club.1999.mkv"
      assert event.watch_dir == "/media"
      assert [%{role: "poster"}] = event.images
      assert event.child_movie == nil
      assert event.season == nil
      assert event.extra == nil
    end

    test "broadcasts collection event with child_movie" do
      payload = %Payload{
        file_path: "/media/The.Shadowy.Sentinel.2008.mkv",
        watch_directory: "/media",
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
        }
      }

      assert {:ok, _result} = Ingest.run(payload)

      assert_receive {:entity_published, event}
      assert event.entity_type == :movie_series
      assert event.child_movie.attrs.name == "The Shadowy Sentinel"
      assert event.watch_dir == "/media"
    end

    test "broadcasts TV event with season and episode" do
      payload = %Payload{
        file_path: "/media/TV/Sample.Show.Eight.S01E01.mkv",
        watch_directory: "/media/TV",
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
        }
      }

      assert {:ok, _result} = Ingest.run(payload)

      assert_receive {:entity_published, event}
      assert event.entity_type == :tv_series
      assert event.season.season_number == 1
      assert event.season.episode.attrs.name == "Pilot"
      assert event.watch_dir == "/media/TV"
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "nil metadata raises" do
      payload = %Payload{metadata: nil}

      assert_raise BadMapError, fn ->
        Ingest.run(payload)
      end
    end
  end
end
