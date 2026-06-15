defmodule MediaCentaur.Playback.PlayableFks do
  @moduledoc """
  Resolves a playable entity + content_url into the type-specific
  identifiers the playback layer needs: the WatchProgress FK map and the
  season/episode (or movie-series ordinal) display context. Shared by
  `Resolver` and `SessionRecovery` so the per-type mapping lives in one
  place and can't drift when a new entity type is added.
  """

  alias MediaCentaur.Library.{EpisodeList, MovieList}

  @doc """
  The WatchProgress FK map for `entity` at `content_url`:
  `%{movie_id: id}`, `%{video_object_id: id}`, or `%{episode_id: id}` —
  `%{}` for an unrecognized type.
  """
  @spec resolve(map(), String.t() | nil) :: map()
  def resolve(%{type: :movie} = entity, _content_url), do: %{movie_id: entity.id}

  def resolve(%{type: :video_object} = entity, _content_url), do: %{video_object_id: entity.id}

  def resolve(%{type: :tv_series} = entity, content_url) do
    episode_id =
      Enum.find_value(entity.seasons || [], fn season ->
        Enum.find_value(season.episodes || [], fn episode ->
          if episode.content_url == content_url, do: episode.id
        end)
      end)

    %{episode_id: episode_id}
  end

  def resolve(%{type: :movie_series} = entity, content_url) do
    movie_id =
      case MovieList.find_by_content_url(entity, content_url) do
        {_ordinal, id, _name} -> id
        nil -> nil
      end

    %{movie_id: movie_id}
  end

  def resolve(_entity, _content_url), do: %{}

  @doc """
  The `{season_or_zero, episode_or_ordinal, name}` context for `entity` at
  `content_url`: movie_series → `{0, ordinal, name}`, tv_series →
  `{season, episode, name}`, anything else → `{nil, nil, nil}`.
  """
  @spec context_by_url(map(), String.t() | nil) ::
          {non_neg_integer() | nil, non_neg_integer() | nil, String.t() | nil}
  def context_by_url(%{type: :movie_series} = entity, content_url) do
    case MovieList.find_by_content_url(entity, content_url) do
      {ordinal, _movie_id, movie_name} -> {0, ordinal, movie_name}
      nil -> {nil, nil, nil}
    end
  end

  def context_by_url(%{type: :tv_series} = entity, content_url) do
    case EpisodeList.find_by_content_url(entity, content_url) do
      {season, episode} ->
        {season, episode, EpisodeList.find_episode_name(entity, season, episode)}

      nil ->
        {nil, nil, nil}
    end
  end

  def context_by_url(_entity, _content_url), do: {nil, nil, nil}
end
