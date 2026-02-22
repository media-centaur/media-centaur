defmodule MediaManagerWeb.PlaybackChannel do
  @moduledoc """
  Handles playback commands (play, pause, stop, seek) and forwards
  playback state changes and progress ticks from PubSub to the UI.
  """
  use Phoenix.Channel
  require Logger

  alias MediaManager.Library.{Entity, WatchProgress}
  alias MediaManager.Playback.{EpisodeList, Manager, Resume}

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
         {:ok, content_url} <- EpisodeList.find_content_url(entity, season, episode) do
      play_params = %{
        action: :play_episode,
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
    reply_result(Manager.pause(), socket)
  end

  @impl true
  def handle_in("stop", _params, socket) do
    reply_result(Manager.stop(), socket)
  end

  @impl true
  def handle_in("seek", %{"position_seconds" => position}, socket) do
    reply_result(Manager.seek(position), socket)
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

  defp reply_result(:ok, socket), do: {:reply, :ok, socket}

  defp reply_result({:error, reason}, socket) do
    {:reply, {:error, %{reason: to_string(reason)}}, socket}
  end

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
      {:no_playable_content} ->
        {:error, :no_playable_content}

      {action, content_url, position} ->
        {season, episode} = episode_context(action, entity, content_url, progress_records)

        {:ok,
         %{
           action: action,
           entity_id: entity.id,
           season_number: season,
           episode_number: episode,
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

  defp episode_context(:resume, _entity, _url, progress_records) do
    most_recent_episode(progress_records)
  end

  defp episode_context(_action, entity, content_url, _progress_records) do
    EpisodeList.find_by_content_url(entity, content_url) || {nil, nil}
  end

  defp most_recent_episode([]), do: {nil, nil}

  defp most_recent_episode(progress_records) do
    most_recent = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    if most_recent, do: {most_recent.season_number, most_recent.episode_number}, else: {nil, nil}
  end
end
