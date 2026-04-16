defmodule MediaCentarr.Pipeline.Stages.FetchMetadata do
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
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.{Parser, Pipeline.Payload}
  alias MediaCentarr.TMDB.{Client, Mapper}

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:error, term()}
  def run(%Payload{tmdb_type: tmdb_type, parsed: parsed} = payload) do
    # Extras resolve media type from the parsed season; everything else uses
    # the search-determined tmdb_type (which handles :unknown → :movie/:tv).
    fetch_type =
      if parsed.type == :extra, do: Parser.effective_media_type(parsed), else: tmdb_type

    case fetch_metadata(payload, fetch_type) do
      {:ok, metadata} ->
        {:ok, %{payload | metadata: metadata}}

      {:error, reason} ->
        {:error, reason}
    end
  end

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
          {
            %{type: :movie_series, name: movie_data["belongs_to_collection"]["name"]},
            [],
            0
          }
      end

    child_attrs = %{
      tmdb_id: to_string(tmdb_id),
      name: movie_data["title"],
      description: movie_data["overview"],
      date_published: movie_data["release_date"],
      url: Mapper.tmdb_url(:movie, tmdb_id),
      duration: Mapper.minutes_to_iso8601(movie_data["runtime"]),
      director: Mapper.extract_director(movie_data["credits"]),
      content_rating: Mapper.extract_us_rating(movie_data["release_dates"]),
      aggregate_rating_value: movie_data["vote_average"],
      content_url: parsed.file_path,
      position: position
    }

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
      extra: build_extra(parsed)
    }

    Log.info(:pipeline, "fetched TV metadata — tmdb:#{tmdb_id} \"#{data["name"]}\"")
    {:ok, metadata}
  end

  defp build_season(season_data, parsed) do
    episodes = season_data["episodes"] || []

    episode =
      if parsed.episode do
        tmdb_episode = Enum.find(episodes, &(&1["episode_number"] == parsed.episode))

        episode_attrs = %{
          episode_number: parsed.episode,
          name: tmdb_episode && tmdb_episode["name"],
          description: tmdb_episode && tmdb_episode["overview"],
          duration: tmdb_episode && Mapper.minutes_to_iso8601(tmdb_episode["runtime"]),
          content_url: parsed.file_path
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
            duration: nil,
            content_url: parsed.file_path
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

  defp build_images(data) do
    poster_path = data["poster_path"]
    backdrop_path = data["backdrop_path"]
    logo_path = find_logo_path(data)

    Enum.reject(
      [
        poster_path &&
          %{role: "poster", url: Mapper.tmdb_image_url(poster_path), extension: "jpg"},
        backdrop_path &&
          %{role: "backdrop", url: Mapper.tmdb_image_url(backdrop_path), extension: "jpg"},
        logo_path && %{role: "logo", url: Mapper.tmdb_image_url(logo_path), extension: "png"}
      ],
      &is_nil/1
    )
  end

  defp build_episode_images(nil), do: []

  defp build_episode_images(tmdb_episode) do
    if tmdb_episode["still_path"] do
      [%{role: "thumb", url: Mapper.tmdb_image_url(tmdb_episode["still_path"]), extension: "jpg"}]
    else
      []
    end
  end

  defp find_logo_path(data) do
    logos = get_in(data, ["images", "logos"]) || []
    logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)
    logo && logo["file_path"]
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
