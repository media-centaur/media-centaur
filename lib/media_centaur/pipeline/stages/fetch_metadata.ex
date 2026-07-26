defmodule MediaCentaur.Pipeline.Stages.FetchMetadata do
  @moduledoc """
  Pipeline stage 3: fetches full TMDB details for the matched entity and
  assembles a structured metadata map using `TMDB.Mapper`.

  The metadata map contains everything Library.Inbound needs to create
  entities, images, identifiers, and TV hierarchy — but does not itself
  touch the database.

  ## Metadata structure

  All cases include:
  - `entity_type` — `:movie`, `:tv_series`, or `:movie_series`
  - `entity_attrs` — attribute map for the top-level entity
  - `images` — list of `%{role, url, extension}` maps (no owner IDs)
  - `identifier` — `%{source, external_id}` for the entity's TMDB identifier

  Movie in collection adds:
  - `child_movie` — `%{attrs, images, identifier, position}`

  TV adds:
  - `season` — `%{season_number, name, number_of_episodes, episode}`
    where `episode` is `%{attrs, images}`

  Extra adds:
  - `extra` — `%{name, content_url, season_number}`
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.TMDB.{Client, Mapper}

  @behaviour MediaCentaur.Pipeline.Stage

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:error, term()}
  @impl true
  def run(%Payload{tmdb_type: tmdb_type, parsed: parsed} = payload) do
    # Extras resolve media type from the parsed season; everything else uses
    # the search-determined tmdb_type (which handles :unknown → :movie/:tv).
    fetch_type =
      if parsed.type == :extra, do: Parser.effective_media_type(parsed), else: tmdb_type

    case fetch_metadata(payload, fetch_type) do
      {:ok, metadata} ->
        emit_enriched(metadata)
        {:ok, %{payload | metadata: metadata}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Announces a successful enrichment with the *resolved title* — the Status
  # page's metadata-activity feed retains these (the stage wrapper's telemetry
  # only carries the file path). A movie landing in a collection reads as the
  # movie, not the collection, since that's what the user recognises.
  defp emit_enriched(metadata) do
    {kind, title} = enriched_identity(metadata)

    :telemetry.execute(
      [:media_centaur, :metadata, :enriched],
      %{system_time: System.system_time()},
      %{kind: kind, title: title, year: enriched_year(metadata)}
    )
  end

  defp enriched_identity(%{child_movie: %{attrs: %{name: name}}}), do: {:movie, name}
  defp enriched_identity(%{entity_type: type, entity_attrs: attrs}), do: {type, attrs[:name]}

  defp enriched_year(%{child_movie: %{attrs: %{date_published: %Date{year: year}}}}), do: year
  defp enriched_year(%{entity_attrs: %{date_published: %Date{year: year}}}), do: year
  defp enriched_year(_metadata), do: nil

  # ---------------------------------------------------------------------------
  # Movie
  # ---------------------------------------------------------------------------

  defp fetch_metadata(%Payload{tmdb_id: tmdb_id, parsed: parsed} = _payload, :movie) do
    with {:ok, data} <- Client.get_movie(tmdb_id) do
      case data["belongs_to_collection"] do
        %{"id" => collection_id} ->
          fetch_movie_in_collection(tmdb_id, data, parsed, collection_id)

        _ ->
          build_standalone_movie(tmdb_id, data, parsed)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # TV
  # ---------------------------------------------------------------------------

  defp fetch_metadata(%Payload{tmdb_id: tmdb_id, parsed: parsed} = _payload, :tv) do
    with {:ok, data} <- Client.get_tv(tmdb_id) do
      build_tv(tmdb_id, data, parsed)
    end
  end

  defp build_standalone_movie(tmdb_id, data, parsed) do
    entity_attrs = Mapper.movie_attrs(tmdb_id, data, parsed.file_path)
    images = build_images(data)

    metadata = %{
      entity_type: :movie,
      entity_attrs: entity_attrs,
      images: images,
      identifier: %{source: "tmdb", external_id: to_string(tmdb_id)},
      child_movie: nil,
      season: nil,
      extra: build_extra(parsed)
    }

    Log.info(:pipeline, "fetched movie metadata — tmdb:#{tmdb_id} \"#{data["title"]}\"")
    {:ok, metadata}
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  defp fetch_movie_in_collection(tmdb_id, movie_data, parsed, collection_id) do
    {collection_attrs, collection_images, position} =
      case Client.get_collection(collection_id) do
        {:ok, collection_data} ->
          {
            Mapper.movie_series_attrs(collection_id, collection_data),
            build_images(collection_data),
            determine_position(collection_data["parts"], tmdb_id)
          }

        {:error, _reason} ->
          # Carry the collection's TMDB id even on fetch failure, so
          # `Library.Inbound` writes the `tmdb_collection` ExternalId. Without
          # it the MovieSeries is un-findable (the next movie mints a duplicate)
          # and un-repairable (image-repair skips owners with no tmdb id). The
          # missing artwork is recovered later by the link-time backfill.
          {
            %{
              type: :movie_series,
              tmdb_id: to_string(collection_id),
              name: movie_data["belongs_to_collection"]["name"]
            },
            [],
            0
          }
      end

    # Library Schema v2 Phase 2 Task I — file_path no longer rides on the
    # child movie attrs; it's added at the event level by
    # `Pipeline.Stages.Ingest`, then linked to the leaf's WatchedFile by
    # `Library.Inbound.link_file/2`. The child uses the same mapping as a
    # standalone movie — a hand-built subset here once dropped
    # cast/crew/status/genres on every collection child.
    child_attrs =
      tmdb_id
      |> Mapper.movie_attrs(movie_data, nil)
      |> Map.put(:position, position)

    metadata = %{
      entity_type: :movie_series,
      entity_attrs: collection_attrs,
      images: collection_images,
      identifier: %{source: "tmdb_collection", external_id: to_string(collection_id)},
      child_movie: %{
        attrs: child_attrs,
        images: build_images(movie_data),
        identifier: %{source: "tmdb", external_id: to_string(tmdb_id)}
      },
      season: nil,
      extra: build_extra(parsed)
    }

    Log.info(
      :pipeline,
      "fetched collection metadata for tmdb:#{tmdb_id} in collection #{collection_id}"
    )

    {:ok, metadata}
  end

  defp build_tv(tmdb_id, data, parsed) do
    entity_attrs = Mapper.tv_attrs(tmdb_id, data)
    images = build_images(data)

    if divert?(data, parsed) do
      build_divert_metadata(tmdb_id, data, parsed, entity_attrs, images)
    else
      build_ingest_metadata(tmdb_id, data, parsed, entity_attrs, images)
    end
  end

  # Case (a) from the reconciliation campaign: the parsed season is **not**
  # in TMDB's canonical season list — the cour / absolute-numbering mismatch.
  # Diverting (rather than `build_minimal_season`) is what stops the phantom
  # season. Guarded on a non-empty season list so a trimmed `data` (or a TV
  # detail without `seasons`) falls back to the normal path rather than
  # diverting everything.
  defp divert?(data, parsed) do
    season_numbers = tmdb_season_numbers(data)
    parsed.season != nil and season_numbers != [] and parsed.season not in season_numbers
  end

  defp tmdb_season_numbers(data) do
    data
    |> Map.get("seasons", [])
    |> Enum.map(& &1["season_number"])
    |> Enum.reject(&is_nil/1)
  end

  defp build_ingest_metadata(tmdb_id, data, parsed, entity_attrs, images) do
    season =
      if parsed.season do
        case Client.get_season(tmdb_id, parsed.season) do
          {:ok, season_data} ->
            build_season(season_data, parsed)

          {:error, _reason} ->
            build_minimal_season(parsed)
        end
      end

    metadata = %{
      entity_type: :tv_series,
      entity_attrs: entity_attrs,
      images: images,
      identifier: %{source: "tmdb", external_id: to_string(tmdb_id)},
      child_movie: nil,
      season: season,
      extra: build_extra(parsed),
      divert: nil
    }

    Log.info(:pipeline, "fetched TV metadata — tmdb:#{tmdb_id} \"#{data["name"]}\"")
    {:ok, metadata}
  end

  # No phantom season; the file is parked in the reconciliation queue by
  # `Pipeline.Stages.Ingest`, which reads this `divert` payload. The series
  # entity is still created (no season/episode, no file link).
  defp build_divert_metadata(tmdb_id, data, parsed, entity_attrs, images) do
    metadata = %{
      entity_type: :tv_series,
      entity_attrs: entity_attrs,
      images: images,
      identifier: %{source: "tmdb", external_id: to_string(tmdb_id)},
      child_movie: nil,
      season: nil,
      extra: build_extra(parsed),
      divert: %{
        tmdb_id: tmdb_id,
        series_title: data["name"],
        claimed_season: parsed.season,
        claimed_episode: parsed.episode,
        claimed_title: parsed.episode_title
      }
    }

    Log.info(
      :pipeline,
      "diverted TV file to reconciliation — tmdb:#{tmdb_id} S#{parsed.season} not in canonical seasons"
    )

    {:ok, metadata}
  end

  defp build_season(season_data, parsed) do
    episodes = season_data["episodes"] || []

    # Library Schema v2 Phase 2 Task I — file_path no longer rides on
    # the episode attrs; it's added at the event level by
    # `Pipeline.Stages.Ingest` and linked to the Episode's WatchedFile
    # by `Library.Inbound.link_file/2`.
    episode =
      if parsed.episode do
        tmdb_episode = Enum.find(episodes, &(&1["episode_number"] == parsed.episode))

        episode_attrs = %{
          episode_number: parsed.episode,
          name: tmdb_episode && tmdb_episode["name"],
          description: tmdb_episode && tmdb_episode["overview"],
          duration_seconds: tmdb_episode && Mapper.minutes_to_seconds(tmdb_episode["runtime"])
        }

        episode_images = build_episode_images(tmdb_episode)

        %{attrs: episode_attrs, images: episode_images}
      end

    %{
      season_number: season_data["season_number"],
      name: season_data["name"],
      number_of_episodes: length(episodes),
      episode: episode
    }
  end

  defp build_minimal_season(parsed) do
    episode =
      if parsed.episode do
        %{
          attrs: %{
            episode_number: parsed.episode,
            name: nil,
            description: nil,
            duration_seconds: nil
          },
          images: []
        }
      end

    %{
      season_number: parsed.season,
      name: "Season #{parsed.season}",
      number_of_episodes: 0,
      episode: episode
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_images(data), do: Mapper.image_list(data)

  defp build_episode_images(nil), do: []

  defp build_episode_images(tmdb_episode) do
    if tmdb_episode["still_path"] do
      [%{role: "thumb", url: Mapper.tmdb_image_url(tmdb_episode["still_path"]), extension: "jpg"}]
    else
      []
    end
  end

  defp build_extra(%{type: :extra, title: title, file_path: file_path, season: season}) do
    %{name: title, content_url: file_path, season_number: season}
  end

  defp build_extra(_parsed), do: nil

  defp determine_position(nil, _tmdb_id), do: 0

  defp determine_position(parts, tmdb_id) do
    tmdb_id_int = if is_binary(tmdb_id), do: String.to_integer(tmdb_id), else: tmdb_id

    case Enum.find_index(parts, fn part -> part["id"] == tmdb_id_int end) do
      nil -> length(parts)
      index -> index
    end
  end
end
