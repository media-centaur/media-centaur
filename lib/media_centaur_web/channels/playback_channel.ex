defmodule MediaCentaurWeb.PlaybackChannel do
  @moduledoc """
  Handles playback commands (play, pause, stop, seek) and forwards
  playback state changes and progress ticks from PubSub to the UI.
  """
  use Phoenix.Channel
  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.{Helpers, WatchProgress}
  alias MediaCentaur.Playback.{EpisodeList, Manager, MovieList, Resume}

  @impl true
  def join("playback", _params, socket) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")
    state = Manager.current_state()
    Log.info(:channel, "playback channel joined, state: #{state.state}")
    {:ok, state, socket}
  end

  @impl true
  def handle_in("play", %{"entity_id" => entity_id} = payload, socket) do
    Log.info(:channel, fn -> "playback recv play: #{inspect(payload, limit: 5)}" end)

    with {:ok, entity} <- load_entity(entity_id),
         progress_records <- load_progress(entity_id),
         {:ok, play_params} <- resolve_playback(entity, progress_records) do
      case Manager.play(play_params) do
        :ok ->
          {:reply, {:ok, play_reply(play_params)}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: to_string(reason)}}, socket}
      end
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("play_episode", params, socket) do
    Log.info(:channel, fn -> "playback recv play_episode: #{inspect(params, limit: 5)}" end)

    %{"entity_id" => entity_id, "season_number" => season, "episode_number" => episode} = params

    with {:ok, entity} <- load_entity(entity_id),
         {:ok, content_url} <- EpisodeList.find_content_url(entity, season, episode) do
      episode_name = EpisodeList.find_episode_name(entity, season, episode)

      play_params = %{
        action: :play_episode,
        entity_id: entity_id,
        entity_name: entity.name,
        season_number: season,
        episode_number: episode,
        episode_name: episode_name,
        content_url: content_url,
        start_position: 0.0
      }

      case Manager.play(play_params) do
        :ok ->
          {:reply, {:ok, play_reply(play_params)}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: to_string(reason)}}, socket}
      end
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("pause", _params, socket) do
    Log.info(:channel, "playback recv pause")
    reply_result(Manager.pause(), socket)
  end

  @impl true
  def handle_in("stop", _params, socket) do
    Log.info(:channel, "playback recv stop")
    reply_result(Manager.stop(), socket)
  end

  @impl true
  def handle_in("seek", %{"position_seconds" => position} = _payload, socket) do
    Log.info(:channel, "playback recv seek to #{position}")
    reply_result(Manager.seek(position), socket)
  end

  # --- PubSub forwarding ---

  @impl true
  def handle_info({:playback_state_changed, state, now_playing}, socket) do
    payload = %{state: to_string(state), now_playing: now_playing}
    Log.info(:channel, "playback push state_changed: #{state}")
    push(socket, "playback:state_changed", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:playback_progress, progress}, socket) do
    push(socket, "playback:progress", progress)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:entity_progress_updated, entity_id, progress_summary, resume_target, _progress_records},
        socket
      ) do
    payload = %{entity_id: entity_id, progress: progress_summary, resumeTarget: resume_target}
    Log.info(:channel, "playback push entity_progress_updated for #{entity_id}")
    push(socket, "playback:entity_progress_updated", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp reply_result(:ok, socket), do: {:reply, :ok, socket}

  defp reply_result({:error, reason}, socket) do
    {:reply, {:error, %{reason: to_string(reason)}}, socket}
  end

  defp load_entity(entity_id), do: Helpers.load_entity(entity_id)

  defp load_progress(entity_id) do
    WatchProgress
    |> Ash.Query.for_read(:for_entity, %{entity_id: entity_id})
    |> Ash.read!()
  end

  defp resolve_playback(entity, progress_records) do
    case Resume.resolve(entity, progress_records) do
      {:no_playable_content} ->
        {:error, :no_playable_content}

      {action, content_url, position} ->
        {season, episode, episode_name} =
          episode_context(action, entity, content_url, progress_records)

        {:ok,
         %{
           action: action,
           entity_id: entity.id,
           entity_name: entity.name,
           season_number: season,
           episode_number: episode,
           episode_name: episode_name,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  defp play_reply(params) do
    %{
      action: to_string(params.action),
      entity_id: params.entity_id,
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      position_seconds: params[:start_position] || 0.0
    }
  end

  defp episode_context(_action, %{type: :movie_series} = entity, content_url, _progress_records) do
    case MovieList.find_by_content_url(entity, content_url) do
      {ordinal, _movie_id, movie_name} -> {0, ordinal, movie_name}
      nil -> {nil, nil, nil}
    end
  end

  defp episode_context(:resume, entity, _url, progress_records) do
    {season, episode} = most_recent_episode(progress_records)
    episode_name = EpisodeList.find_episode_name(entity, season, episode)
    {season, episode, episode_name}
  end

  defp episode_context(_action, entity, content_url, _progress_records) do
    case EpisodeList.find_by_content_url(entity, content_url) do
      {season, episode} ->
        episode_name = EpisodeList.find_episode_name(entity, season, episode)
        {season, episode, episode_name}

      nil ->
        {nil, nil, nil}
    end
  end

  defp most_recent_episode([]), do: {nil, nil}

  defp most_recent_episode(progress_records) do
    most_recent = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    if most_recent, do: {most_recent.season_number, most_recent.episode_number}, else: {nil, nil}
  end
end
