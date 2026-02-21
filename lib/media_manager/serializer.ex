defmodule MediaManager.Serializer do
  @moduledoc """
  Pure-function module that converts loaded Ash entity structs into
  schema.org JSON-LD maps matching DATA-FORMAT.md.

  This is an output/export concern — it lives alongside `JsonWriter`
  which calls it to produce `media.json`.
  """

  alias MediaManager.Library.{Entity, Image, Identifier, Movie, Season, Episode}

  @doc """
  Serializes a list of entities into wrapped JSON-LD maps.
  """
  def serialize_all(entities) do
    Enum.map(entities, &serialize_entity/1)
  end

  @doc """
  Serializes a single entity into a wrapped map: `%{"@id" => uuid, "entity" => %{...}}`.
  """
  def serialize_entity(%Entity{type: :movie_series} = entity) do
    serialize_movie_series(entity)
  end

  def serialize_entity(%Entity{} = entity) do
    %{
      "@id" => entity.id,
      "entity" => entity_to_map(entity)
    }
  end

  defp entity_to_map(%Entity{} = entity) do
    base_fields(entity)
    |> Map.merge(type_specific_fields(entity))
    |> maybe_add_images(entity)
    |> maybe_add_identifiers(entity)
    |> maybe_add_rating(entity)
    |> compact()
  end

  defp base_fields(entity) do
    %{
      "@type" => type_string(entity.type),
      "name" => entity.name,
      "description" => entity.description,
      "datePublished" => entity.date_published,
      "genre" => entity.genres,
      "contentUrl" => entity.content_url,
      "url" => entity.url
    }
  end

  defp type_specific_fields(%Entity{type: :movie} = entity) do
    %{
      "duration" => entity.duration,
      "director" => entity.director,
      "contentRating" => entity.content_rating
    }
  end

  defp type_specific_fields(%Entity{type: :tv_series} = entity) do
    %{
      "numberOfSeasons" => entity.number_of_seasons,
      "containsSeason" => serialize_seasons(entity.seasons)
    }
  end

  defp type_specific_fields(%Entity{type: :movie_series}) do
    # MovieSeries uses custom serialization via serialize_movie_series/1
    %{}
  end

  defp type_specific_fields(%Entity{}) do
    %{}
  end

  defp serialize_seasons(seasons) when is_list(seasons) do
    seasons
    |> Enum.sort_by(& &1.season_number)
    |> Enum.map(&serialize_season/1)
  end

  defp serialize_seasons(_), do: nil

  defp serialize_season(%Season{} = season) do
    %{
      "seasonNumber" => season.season_number,
      "numberOfEpisodes" => season.number_of_episodes,
      "name" => season.name,
      "episode" => serialize_episodes(season.episodes)
    }
    |> compact()
  end

  defp serialize_episodes(episodes) when is_list(episodes) do
    episodes
    |> Enum.sort_by(& &1.episode_number)
    |> Enum.map(&serialize_episode/1)
  end

  defp serialize_episodes(_), do: nil

  defp serialize_episode(%Episode{} = episode) do
    %{
      "episodeNumber" => episode.episode_number,
      "name" => episode.name,
      "description" => episode.description,
      "duration" => episode.duration,
      "contentUrl" => episode.content_url
    }
    |> compact()
  end

  # --- MovieSeries serialization ---

  defp serialize_movie_series(%Entity{} = entity) do
    movies = sorted_child_movies(entity.movies)

    case movies do
      [single_movie] ->
        # 1 child movie → export as top-level Movie using child's data
        %{
          "@id" => entity.id,
          "entity" => serialize_single_child_as_movie(single_movie, entity)
        }

      _ ->
        # 2+ child movies → export as MovieSeries with hasPart
        %{
          "@id" => entity.id,
          "entity" => serialize_as_movie_series(entity, movies)
        }
    end
  end

  defp serialize_single_child_as_movie(%Movie{} = movie, _entity) do
    %{
      "@type" => "Movie",
      "name" => movie.name,
      "description" => movie.description,
      "datePublished" => movie.date_published,
      "contentUrl" => movie.content_url,
      "url" => movie.url,
      "duration" => movie.duration,
      "director" => movie.director,
      "contentRating" => movie.content_rating
    }
    |> maybe_add_child_movie_images(movie)
    |> maybe_add_child_movie_identifier(movie)
    |> maybe_add_child_movie_rating(movie)
    |> compact()
  end

  defp serialize_as_movie_series(%Entity{} = entity, movies) do
    base_fields(entity)
    |> Map.put("hasPart", Enum.map(movies, &serialize_child_movie/1))
    |> maybe_add_images(entity)
    |> maybe_add_identifiers(entity)
    |> maybe_add_rating(entity)
    |> compact()
  end

  defp serialize_child_movie(%Movie{} = movie) do
    %{
      "@type" => "Movie",
      "name" => movie.name,
      "description" => movie.description,
      "datePublished" => movie.date_published,
      "contentUrl" => movie.content_url,
      "url" => movie.url,
      "duration" => movie.duration,
      "director" => movie.director,
      "contentRating" => movie.content_rating
    }
    |> maybe_add_child_movie_images(movie)
    |> maybe_add_child_movie_identifier(movie)
    |> maybe_add_child_movie_rating(movie)
    |> compact()
  end

  defp maybe_add_child_movie_images(map, %Movie{images: images}) when is_list(images) do
    serialized = Enum.map(images, &serialize_image/1)
    Map.put(map, "image", serialized)
  end

  defp maybe_add_child_movie_images(map, _), do: map

  defp maybe_add_child_movie_identifier(map, %Movie{tmdb_id: tmdb_id})
       when is_binary(tmdb_id) do
    identifier = %{
      "@type" => "PropertyValue",
      "propertyID" => "tmdb",
      "value" => tmdb_id
    }

    Map.update(map, "identifier", [identifier], fn existing -> existing ++ [identifier] end)
  end

  defp maybe_add_child_movie_identifier(map, _), do: map

  defp maybe_add_child_movie_rating(map, %Movie{aggregate_rating_value: value})
       when is_number(value) do
    Map.put(map, "aggregateRating", %{"ratingValue" => value})
  end

  defp maybe_add_child_movie_rating(map, _), do: map

  defp sorted_child_movies(movies) when is_list(movies) do
    Enum.sort_by(movies, fn movie -> {movie.position || 0, movie.date_published || ""} end)
  end

  defp sorted_child_movies(_), do: []

  defp maybe_add_images(map, %Entity{images: images}) when is_list(images) do
    serialized = Enum.map(images, &serialize_image/1)
    Map.put(map, "image", serialized)
  end

  defp maybe_add_images(map, _), do: map

  defp serialize_image(%Image{} = image) do
    %{
      "@type" => "ImageObject",
      "name" => image.role,
      "url" => image.url,
      "contentUrl" => image.content_url
    }
    |> compact()
  end

  defp maybe_add_identifiers(map, %Entity{identifiers: identifiers})
       when is_list(identifiers) do
    serialized = Enum.map(identifiers, &serialize_identifier/1)
    Map.put(map, "identifier", serialized)
  end

  defp maybe_add_identifiers(map, _), do: map

  defp serialize_identifier(%Identifier{} = identifier) do
    %{
      "@type" => "PropertyValue",
      "propertyID" => identifier.property_id,
      "value" => identifier.value
    }
    |> compact()
  end

  defp maybe_add_rating(map, %Entity{aggregate_rating_value: value})
       when is_number(value) do
    Map.put(map, "aggregateRating", %{"ratingValue" => value})
  end

  defp maybe_add_rating(map, _), do: map

  defp type_string(:movie), do: "Movie"
  defp type_string(:movie_series), do: "MovieSeries"
  defp type_string(:tv_series), do: "TVSeries"
  defp type_string(:video_object), do: "VideoObject"

  defp compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value == nil or value == [] end)
    |> Map.new()
  end
end
