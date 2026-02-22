defmodule MediaManagerWeb.PlaybackChannel do
  use Phoenix.Channel
  require Logger

  alias MediaManager.Library.{Entity, WatchProgress}
  alias MediaManager.Playback.{Manager, Resume}

  @impl true
  def join("playback", _params, socket) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "playback:events")
    state = Manager.current_state()
    {:ok, state, socket}
  end

  @impl true
  def handle_in("play", %{"entity_id" => entity_id}, socket) do
    with {:ok, entity} <- load_entity(entity_id),
         progress_records <- load_progress(entity_id),
         {:ok, play_params} <- resolve_playback(entity, progress_records) do
      case Manager.play(play_params) do
        :ok ->
          {:reply, {:ok, play_reply(play_params)}, socket}

        {:error, :already_playing} ->
          {:reply, {:error, %{reason: "already_playing"}}, socket}
      end
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("play_episode", params, socket) do
    %{"entity_id" => entity_id, "season_number" => season, "episode_number" => episode} = params

    with {:ok, entity} <- load_entity(entity_id),
         {:ok, content_url} <- find_episode_content_url(entity, season, episode) do
      play_params = %{
        entity_id: entity_id,
        season_number: season,
        episode_number: episode,
        content_url: content_url,
        start_position: 0.0
      }

      case Manager.play(play_params) do
        :ok ->
          {:reply, {:ok, play_reply(play_params)}, socket}

        {:error, :already_playing} ->
          {:reply, {:error, %{reason: "already_playing"}}, socket}
      end
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("pause", _params, socket) do
    case Manager.pause() do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("stop", _params, socket) do
    case Manager.stop() do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("seek", %{"position_seconds" => position}, socket) do
    case Manager.seek(position) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # --- PubSub forwarding ---

  @impl true
  def handle_info({:playback_state_changed, state, now_playing}, socket) do
    push(socket, "playback:state_changed", %{
      state: to_string(state),
      now_playing: now_playing
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:playback_progress, progress}, socket) do
    push(socket, "playback:progress", progress)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:entity_progress_updated, entity_id, progress_summary}, socket) do
    push(socket, "playback:entity_progress_updated", %{
      entity_id: entity_id,
      progress: progress_summary
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp load_entity(entity_id) do
    case Ash.get(Entity, entity_id, action: :with_associations) do
      {:ok, entity} -> {:ok, entity}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp load_progress(entity_id) do
    Ash.read!(WatchProgress, action: :for_entity, args: [entity_id: entity_id])
  end

  defp resolve_playback(entity, progress_records) do
    case Resume.resolve(entity, progress_records) do
      {:resume, content_url, position} ->
        {:ok,
         %{
           entity_id: entity.id,
           season_number: extract_season(entity, progress_records),
           episode_number: extract_episode(entity, progress_records),
           content_url: content_url,
           start_position: position
         }}

      {:play_next, content_url, position} ->
        {:ok,
         %{
           entity_id: entity.id,
           season_number: extract_season_for_url(entity, content_url),
           episode_number: extract_episode_for_url(entity, content_url),
           content_url: content_url,
           start_position: position
         }}

      {:restart, content_url, position} ->
        {:ok,
         %{
           entity_id: entity.id,
           season_number: extract_season_for_url(entity, content_url),
           episode_number: extract_episode_for_url(entity, content_url),
           content_url: content_url,
           start_position: position
         }}

      {:no_playable_content} ->
        {:error, :no_playable_content}
    end
  end

  defp play_reply(params) do
    %{
      entity_id: params.entity_id,
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      position_seconds: params[:start_position] || 0.0
    }
  end

  defp find_episode_content_url(entity, season_number, episode_number) do
    result =
      (entity.seasons || [])
      |> Enum.find(&(&1.season_number == season_number))
      |> case do
        nil -> nil
        season -> Enum.find(season.episodes || [], &(&1.episode_number == episode_number))
      end
      |> case do
        nil -> nil
        episode -> episode.content_url
      end

    case result do
      nil -> {:error, :invalid_episode}
      url -> {:ok, url}
    end
  end

  # Extract season/episode numbers from the most recently watched progress record
  defp extract_season(_entity, []), do: nil

  defp extract_season(_entity, progress_records) do
    most_recent = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    if most_recent, do: most_recent.season_number, else: nil
  end

  defp extract_episode(_entity, []), do: nil

  defp extract_episode(_entity, progress_records) do
    most_recent = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    if most_recent, do: most_recent.episode_number, else: nil
  end

  # Find season/episode numbers for a given content_url by searching the entity tree
  defp extract_season_for_url(%{type: :tv_series} = entity, content_url) do
    find_episode_by_url(entity, content_url)
    |> case do
      {season_number, _episode_number} -> season_number
      nil -> nil
    end
  end

  defp extract_season_for_url(_entity, _url), do: nil

  defp extract_episode_for_url(%{type: :tv_series} = entity, content_url) do
    find_episode_by_url(entity, content_url)
    |> case do
      {_season_number, episode_number} -> episode_number
      nil -> nil
    end
  end

  defp extract_episode_for_url(_entity, _url), do: nil

  defp find_episode_by_url(entity, content_url) do
    Enum.find_value(entity.seasons || [], fn season ->
      Enum.find_value(season.episodes || [], fn episode ->
        if episode.content_url == content_url do
          {season.season_number, episode.episode_number}
        end
      end)
    end)
  end
end
