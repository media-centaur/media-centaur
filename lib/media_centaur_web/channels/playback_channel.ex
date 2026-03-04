defmodule MediaCentaurWeb.PlaybackChannel do
  @moduledoc """
  Handles the `play` command and forwards playback state changes and
  entity progress updates from PubSub to the UI.
  """
  use Phoenix.Channel
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback.{Manager, Resolver}

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

    case Resolver.resolve(entity_id) do
      {:ok, play_params} ->
        case Manager.play(play_params) do
          :ok ->
            {:reply, {:ok, play_reply(play_params)}, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: to_string(reason)}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
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
  def handle_info(
        {:entity_progress_updated, entity_id, progress_summary, resume_target,
         child_targets_delta, last_activity_at},
        socket
      ) do
    payload = %{
      entity_id: entity_id,
      progress: progress_summary,
      resumeTarget: resume_target,
      childTargets: child_targets_delta,
      lastActivityAt: last_activity_at && DateTime.to_iso8601(last_activity_at)
    }

    Log.info(:channel, "playback push entity_progress_updated for #{entity_id}")
    push(socket, "playback:entity_progress_updated", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp play_reply(params) do
    %{
      action: to_string(params.action),
      entity_id: params.entity_id,
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      position_seconds: params[:start_position] || 0.0
    }
  end
end
