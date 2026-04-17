defmodule MediaCentarr.Serializer do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Converts library records into schema.org JSON-LD maps matching DATA-FORMAT.md.

  Image `contentUrl` values are resolved to absolute filesystem paths
  via `Config.resolve_image_path/1`.
  """

  alias MediaCentarr.Config

  alias MediaCentarr.Library.{
    Extra,
    Image,
    ExternalId,
    Movie,
    Season,
    Episode
  }

  alias MediaCentarr.Library.{EpisodeList, MovieList}

  @doc """
  Dispatches to the type-specific serializer based on a plain map's `:type` field.

  Used by tests that build entity maps with `build_entity/1`.
  """
  def serialize_entity(%{type: :movie} = entity), do: serialize_movie(entity)
  def serialize_entity(%{type: :tv_series} = entity), do: serialize_tv_series(entity)
  def serialize_entity(%{type: :movie_series} = entity), do: serialize_movie_series(entity)
  def serialize_entity(%{type: :video_object} = entity), do: serialize_video_object(entity)

  @doc """
  Serializes a standalone `%Movie{}` struct into a wrapped map.

  Produces the same JSON-LD output as `serialize_entity/1` for an
  `%Entity{type: :movie}`.
  """
  def serialize_movie(movie) do
    %{
      "@id" => movie.id,
      "entity" =>
        %{
          "@type" => "Movie",
          "name" => movie.name,
          "description" => movie.description,
          "datePublished" => movie.date_published,
          "genre" => movie.genres,
          "contentUrl" => movie.content_url,
          "url" => movie.url,
          "duration" => movie.duration,
          "director" => movie.director,
          "contentRating" => movie.content_rating
        }
        |> maybe_add_extras(movie)
        |> maybe_add_images(movie)
        |> maybe_add_external_ids(movie)
        |> maybe_add_rating(movie)
        |> compact()
    }
  end

  @doc """
  Serializes a `%TVSeries{}` struct into a wrapped map.

  Produces the same JSON-LD output as `serialize_entity/1` for an
  `%Entity{type: :tv_series}`.
  """
  def serialize_tv_series(tv_series) do
    %{
      "@id" => tv_series.id,
      "entity" =>
        %{
          "@type" => "TVSeries",
          "name" => tv_series.name,
          "description" => tv_series.description,
          "datePublished" => tv_series.date_published,
          "genre" => tv_series.genres,
          "url" => tv_series.url,
          "numberOfSeasons" => tv_series.number_of_seasons,
          "containsSeason" => serialize_seasons(tv_series.seasons)
        }
        |> maybe_add_extras(tv_series)
        |> maybe_add_images(tv_series)
        |> maybe_add_external_ids(tv_series)
        |> maybe_add_rating(tv_series)
        |> compact()
    }
  end

  @doc """
  Serializes a `%MovieSeries{}` struct into a wrapped map.

  Applies the same single-movie collapse logic as the Entity-based
  serialization: a movie series with exactly one child movie is exported
  as a top-level Movie; two or more children produce a MovieSeries with
  hasPart.
  """
  def serialize_movie_series(movie_series) do
    movies = sorted_child_movies(movie_series.movies)

    case movies do
      [single_movie] ->
        %{
          "@id" => movie_series.id,
          "entity" => maybe_add_extras(serialize_child_movie(single_movie), movie_series)
        }

      _ ->
        %{
          "@id" => movie_series.id,
          "entity" => serialize_as_typed_movie_series(movie_series, movies)
        }
    end
  end

  @doc """
  Serializes a `%VideoObject{}` struct into a wrapped map.

  Produces the same JSON-LD output as `serialize_entity/1` for an
  `%Entity{type: :video_object}`.
  """
  def serialize_video_object(video_object) do
    %{
      "@id" => video_object.id,
      "entity" =>
        %{
          "@type" => "VideoObject",
          "name" => video_object.name,
          "description" => video_object.description,
          "datePublished" => video_object.date_published,
          "contentUrl" => video_object.content_url,
          "url" => video_object.url
        }
        |> maybe_add_images(video_object)
        |> maybe_add_external_ids(video_object)
        |> compact()
    }
  end

  defp serialize_as_typed_movie_series(movie_series, movies) do
    child_movies = Enum.map(movies, &serialize_child_movie/1)
    extras = serialize_top_level_extras(movie_series)

    %{
      "@type" => "MovieSeries",
      "name" => movie_series.name,
      "description" => movie_series.description,
      "datePublished" => movie_series.date_published,
      "genre" => movie_series.genres,
      "url" => movie_series.url,
      "hasPart" => child_movies ++ extras
    }
    |> maybe_add_images(movie_series)
    |> maybe_add_external_ids(movie_series)
    |> maybe_add_rating(movie_series)
    |> compact()
  end

  defp serialize_seasons(seasons) when is_list(seasons) do
    seasons
    |> EpisodeList.sort_seasons()
    |> Enum.map(&serialize_season/1)
  end

  defp serialize_seasons(_), do: nil

  defp serialize_season(%Season{} = season) do
    %{
      "@id" => season.id,
      "seasonNumber" => season.season_number,
      "numberOfEpisodes" => season.number_of_episodes,
      "name" => season.name,
      "episode" => serialize_episodes(season.episodes)
    }
    |> maybe_add_season_extras(season)
    |> compact()
  end

  defp maybe_add_season_extras(map, %Season{extras: extras}) when is_list(extras) and extras != [] do
    serialized =
      extras
      |> Enum.sort_by(&(&1.position || 0))
      |> Enum.map(&serialize_extra/1)

    Map.put(map, "hasPart", serialized)
  end

  defp maybe_add_season_extras(map, _), do: map

  defp serialize_episodes(episodes) when is_list(episodes) do
    episodes
    |> EpisodeList.sort_episodes()
    |> Enum.map(&serialize_episode/1)
  end

  defp serialize_episodes(_), do: nil

  defp serialize_episode(%Episode{} = episode) do
    %{
      "@id" => episode.id,
      "episodeNumber" => episode.episode_number,
      "name" => episode.name,
      "description" => episode.description,
      "duration" => episode.duration,
      "contentUrl" => episode.content_url
    }
    |> maybe_add_images(episode)
    |> compact()
  end

  # --- Extras serialization ---

  defp maybe_add_extras(map, record) do
    case serialize_top_level_extras(record) do
      [] -> map
      extras -> Map.put(map, "hasPart", extras)
    end
  end

  defp serialize_top_level_extras(record) do
    case Map.get(record, :extras) do
      extras when is_list(extras) and extras != [] ->
        extras
        |> Enum.filter(fn extra -> is_nil(extra.season_id) end)
        |> Enum.sort_by(&(&1.position || 0))
        |> Enum.map(&serialize_extra/1)

      _ ->
        []
    end
  end

  defp serialize_extra(%Extra{} = extra) do
    compact(%{
      "@id" => extra.id,
      "@type" => "VideoObject",
      "name" => extra.name,
      "contentUrl" => extra.content_url
    })
  end

  defp serialize_child_movie(%Movie{} = movie) do
    %{
      "@id" => movie.id,
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
    |> maybe_add_images(movie)
    |> maybe_add_child_movie_identifier(movie)
    |> maybe_add_child_movie_rating(movie)
    |> compact()
  end

  defp maybe_add_child_movie_identifier(map, %Movie{tmdb_id: tmdb_id}) when is_binary(tmdb_id) do
    identifier = %{
      "@type" => "PropertyValue",
      "propertyID" => "tmdb",
      "value" => tmdb_id
    }

    Map.update(map, "identifier", [identifier], fn existing -> existing ++ [identifier] end)
  end

  defp maybe_add_child_movie_identifier(map, _), do: map

  defp maybe_add_child_movie_rating(map, %Movie{aggregate_rating_value: value}) when is_number(value) do
    Map.put(map, "aggregateRating", %{"ratingValue" => value})
  end

  defp maybe_add_child_movie_rating(map, _), do: map

  defp sorted_child_movies(movies), do: MovieList.sort_movies(movies)

  defp maybe_add_images(map, record) do
    case Map.get(record, :images) do
      images when is_list(images) ->
        Map.put(map, "image", Enum.map(images, &serialize_image/1))

      _ ->
        map
    end
  end

  defp serialize_image(%Image{} = image) do
    compact(%{
      "@type" => "ImageObject",
      "name" => image.role,
      "contentUrl" => Config.resolve_image_path(image.content_url)
    })
  end

  defp maybe_add_external_ids(map, record) do
    case Map.get(record, :external_ids) do
      external_ids when is_list(external_ids) ->
        Map.put(map, "identifier", Enum.map(external_ids, &serialize_external_id/1))

      _ ->
        map
    end
  end

  defp serialize_external_id(%ExternalId{} = ext_id) do
    compact(%{
      "@type" => "PropertyValue",
      "propertyID" => ext_id.source,
      "value" => ext_id.external_id
    })
  end

  defp maybe_add_rating(map, record) do
    case Map.get(record, :aggregate_rating_value) do
      value when is_number(value) ->
        Map.put(map, "aggregateRating", %{"ratingValue" => value})

      _ ->
        map
    end
  end

  defp compact(map) when is_map(map) do
    Map.filter(map, fn {_key, value} -> value != nil and value != [] end)
  end
end
