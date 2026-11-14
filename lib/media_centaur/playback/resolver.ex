defmodule MediaCentaur.Playback.Resolver do
  @moduledoc """
  Resolves a UUID into playback parameters for one profile.

  The UUID can identify any playable thing: a top-level Entity, an Episode,
  a child Movie, or an Extra. The resolver figures out what the UUID refers to,
  loads the necessary context, reads where the profile stands (ADR-078), and
  returns the play params `Sessions.play/2` starts with: the profile and the
  `Playback.Entry` to play.

  UUID resolution order:
  1. Entity — the title's `MediaCentaur.Library.TitleProgress`
     (`ProgressRecords.title_progress/2`): its next item at next's offset;
     a complete title plays its first item from the start
  2. Episode — that episode, at its own viewing in flight
  3. Movie (child) — that movie, at its own viewing in flight
  4. Extra — that extra, at its own viewing in flight

  A directly named item starts at its row's offset when the row holds a
  viewing that counts (`ProgressRecords.viewing?/1`), whatever its watched
  mark, else from the start.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Format, Library}

  alias MediaCentaur.Library.{
    EntityShape,
    EpisodeOrder,
    MovieOrder,
    ProgressRecords,
    TitleProgress,
    TypeResolver
  }

  alias MediaCentaur.Playback.{Entry, PlayableFks}

  @type play_params :: %{profile_id: String.t(), entry: Entry.t()}

  @doc """
  Resolves a UUID into playback parameters for `profile_id`.

  Returns `{:ok, play_params}` or `{:error, reason}`.
  """
  @spec resolve(String.t(), String.t()) :: {:ok, play_params()} | {:error, atom()}
  def resolve(profile_id, uuid) when is_binary(profile_id) and is_binary(uuid) do
    Log.info(:playback, "resolving #{Format.short_id(uuid)} for #{Format.short_id(profile_id)}")

    with {:error, :not_found} <- resolve_entity(profile_id, uuid),
         {:error, :not_found} <- resolve_episode(profile_id, uuid),
         {:error, :not_found} <- resolve_movie(profile_id, uuid),
         {:error, :not_found} <- resolve_extra(profile_id, uuid) do
      Log.info(
        :playback,
        "resolve failed — #{Format.short_id(uuid)} not found as entity/episode/movie/extra"
      )

      {:error, :not_found}
    else
      {:ok, entry} -> {:ok, %{profile_id: profile_id, entry: entry}}
      {:error, _reason} = error -> error
    end
  end

  # --- Entity resolution ---

  defp resolve_entity(profile_id, uuid) do
    case load_entity(uuid) do
      {:ok, entity} ->
        %{title_progress: progress} = ProgressRecords.title_progress(profile_id, entity)
        resolve_entity_playback(entity, progress)

      :not_found ->
        {:error, :not_found}
    end
  end

  defp load_entity(uuid) do
    case TypeResolver.resolve_container(uuid, preload: Library.Containers.full_preloads_by_type()) do
      {:ok, type, record} -> {:ok, EntityShape.to_entity_view(record, type)}
      :not_found -> :not_found
    end
  end

  defp resolve_entity_playback(entity, %TitleProgress{total: 0}) do
    Log.info(:playback, "no playable content for entity #{entity.name}")
    {:error, :no_playable_content}
  end

  defp resolve_entity_playback(entity, %TitleProgress{state: :complete}) do
    [first | _rest] = TitleProgress.ordered_set(entity)
    entry_for(entity, first.id, 0.0)
  end

  defp resolve_entity_playback(entity, %TitleProgress{next: next}),
    do: entry_for(entity, next.item_id, next.offset_seconds)

  defp entry_for(entity, item_id, position) do
    content_url = item_content_url(entity, item_id)
    {season, episode, episode_name} = PlayableFks.context_by_url(entity, content_url)
    action = if position > 0, do: :resume, else: :play

    Log.info(:playback, fn ->
      "resolved entity #{entity.name} — #{action}, #{Path.basename(content_url)}" <>
        if(position > 0, do: ", resume at #{position}s", else: "")
    end)

    {:ok,
     struct!(
       %Entry{
         entity_id: entity.id,
         entity_name: entity.name,
         season_number: season,
         episode_number: episode,
         episode_name: episode_name,
         content_url: content_url,
         start_position: position
       },
       PlayableFks.resolve(entity, content_url)
     )}
  end

  # The file of an item of the title's ordered set.
  defp item_content_url(%{type: :tv_series} = entity, item_id) do
    Enum.find_value(EpisodeOrder.list_available(entity), fn {_season, _episode, url, id} ->
      if id == item_id, do: url
    end)
  end

  defp item_content_url(%{type: :movie_series} = entity, item_id) do
    Enum.find_value(MovieOrder.list_available(entity), fn {_ordinal, id, url} ->
      if id == item_id, do: url
    end)
  end

  defp item_content_url(entity, _item_id), do: entity.content_url

  # --- Episode resolution ---

  defp resolve_episode(profile_id, uuid) do
    case Library.Episodes.fetch(uuid) do
      {:ok, episode} ->
        resolve_episode_playback(profile_id, episode)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_episode_playback(_profile_id, %{content_url: nil} = episode) do
    Log.info(:playback, "episode #{Format.short_id(episode.id)} has no content_url")
    {:error, :no_playable_content}
  end

  defp resolve_episode_playback(profile_id, episode) do
    with {:ok, season} <- Library.Seasons.fetch(episode.season_id),
         {:ok, tv_series} <-
           Library.Containers.fetch_with_associations(:tv_series, season.tv_series_id) do
      entity = EntityShape.to_entity_view(tv_series, :tv_series)

      position = viewing_offset(ProgressRecords.fetch_for_container(profile_id, :episode, episode.id))

      action = if position > 0.0, do: :resume, else: :play_episode

      Log.info(:playback, fn ->
        "resolved episode S#{season.season_number}E#{episode.episode_number} of #{entity.name} — #{action}" <>
          if(position > 0, do: ", resume at #{position}s", else: "")
      end)

      {:ok,
       %Entry{
         entity_id: entity.id,
         entity_name: entity.name,
         season_number: season.season_number,
         episode_number: episode.episode_number,
         episode_name: episode.name,
         content_url: episode.content_url,
         start_position: position,
         episode_id: episode.id
       }}
    else
      {:error, _} ->
        Log.info(
          :playback,
          "episode #{Format.short_id(episode.id)} — parent season or entity not found"
        )

        {:error, :not_found}
    end
  end

  # --- Movie (child) resolution ---

  defp resolve_movie(profile_id, uuid) do
    case Library.Containers.fetch(:movie, uuid) do
      {:ok, movie} ->
        resolve_movie_playback(profile_id, movie)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_movie_playback(_profile_id, %{content_url: nil} = movie) do
    Log.info(:playback, "movie #{Format.short_id(movie.id)} has no content_url")
    {:error, :no_playable_content}
  end

  defp resolve_movie_playback(profile_id, movie) do
    case resolve_movie_parent(movie) do
      {:ok, entity} ->
        available = MovieOrder.list_available(entity)

        ordinal =
          case Enum.find(available, fn {_ord, id, _url} -> id == movie.id end) do
            {ord, _id, _url} -> ord
            nil -> nil
          end

        if ordinal do
          position = viewing_offset(ProgressRecords.fetch_for_container(profile_id, :movie, movie.id))

          action = if position > 0.0, do: :resume, else: :play_movie

          Log.info(:playback, fn ->
            "resolved movie #{movie.name} (##{ordinal}) of #{entity.name} — #{action}" <>
              if(position > 0, do: ", resume at #{position}s", else: "")
          end)

          {:ok,
           %Entry{
             entity_id: entity.id,
             entity_name: entity.name,
             season_number: 0,
             episode_number: ordinal,
             episode_name: movie.name,
             content_url: movie.content_url,
             start_position: position,
             movie_id: movie.id
           }}
        else
          Log.info(
            :playback,
            "movie #{movie.name} not found in available list for #{entity.name}"
          )

          {:error, :no_playable_content}
        end

      :not_found ->
        Log.info(:playback, "movie #{Format.short_id(movie.id)} — parent entity not found")
        {:error, :not_found}
    end
  end

  defp resolve_movie_parent(movie) do
    {type, id} =
      if movie.movie_series_id, do: {:movie_series, movie.movie_series_id}, else: {:movie, movie.id}

    case Library.Containers.fetch_with_associations(type, id) do
      {:ok, record} -> {:ok, EntityShape.to_entity_view(record, type)}
      _absent -> :not_found
    end
  end

  # --- Extra resolution ---

  defp resolve_extra(profile_id, uuid) do
    case Library.Extras.fetch(uuid) do
      {:ok, extra} ->
        resolve_extra_playback(profile_id, extra)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_extra_playback(_profile_id, %{content_url: nil} = extra) do
    Log.info(:playback, "extra #{Format.short_id(extra.id)} has no content_url")
    {:error, :no_playable_content}
  end

  defp resolve_extra_playback(profile_id, extra) do
    {entity_id, entity_name} = resolve_extra_parent(extra)
    position = viewing_offset(ProgressRecords.fetch_for_extra(profile_id, extra.id))

    {:ok,
     %Entry{
       entity_id: entity_id,
       entity_name: entity_name,
       season_number: nil,
       episode_number: nil,
       episode_name: extra.name,
       content_url: extra.content_url,
       start_position: position,
       extra_id: extra.id
     }}
  end

  defp resolve_extra_parent(extra) do
    # Resolve the Extra's container — `owner_type` is one of :movie,
    # :tv_series, :movie_series, :season. Seasons aren't directly
    # resolvable by `load_entity/1`; for season-owned extras we fall back
    # to surfacing the season id without a name. The parent-aware playback
    # row carries enough context for the UI.
    if extra.owner_type in [:movie, :tv_series, :movie_series] do
      case load_entity(extra.owner_id) do
        {:ok, entity} -> {entity.id, entity.name}
        :not_found -> {extra.owner_id, nil}
      end
    else
      {extra.owner_id, nil}
    end
  end

  # --- Shared helpers ---

  # Where a directly named item starts: its row's offset when the row
  # holds a viewing that counts, else the start.
  defp viewing_offset({:ok, progress}) do
    if ProgressRecords.viewing?(progress), do: progress.position_seconds / 1, else: 0.0
  end

  defp viewing_offset({:error, :not_found}), do: 0.0
end
