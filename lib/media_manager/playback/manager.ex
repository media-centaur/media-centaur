defmodule MediaManager.Playback.Manager do
  @moduledoc """
  Singleton GenServer managing at most one active MpvSession.
  Provides the public API for playback control.
  """
  use GenServer
  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Playback.{MpvSession, SessionSupervisor}

  defstruct session: nil,
            monitor_ref: nil,
            state: :idle,
            now_playing: nil

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # --- Public API ---

  def play(params), do: GenServer.call(__MODULE__, {:play, params})
  def pause, do: GenServer.call(__MODULE__, :pause)
  def stop, do: GenServer.call(__MODULE__, :stop)
  def seek(position), do: GenServer.call(__MODULE__, {:seek, position})
  def current_state, do: GenServer.call(__MODULE__, :current_state)

  # --- Callbacks ---

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "playback:events")

    state =
      case DynamicSupervisor.which_children(SessionSupervisor) do
        [{_, pid, _, _}] when is_pid(pid) ->
          ref = Process.monitor(pid)
          %__MODULE__{session: pid, monitor_ref: ref, state: :playing}

        _ ->
          %__MODULE__{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:play, params}, _from, state) do
    Log.info(:playback, "play #{params[:entity_name] || params.entity_id}")
    state = stop_existing_session(state)

    case SessionSupervisor.start_session(params) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        now_playing = %{
          entity_id: params.entity_id,
          entity_name: params[:entity_name],
          season_number: params[:season_number],
          episode_number: params[:episode_number],
          episode_name: params[:episode_name],
          content_url: params.content_url,
          position_seconds: params[:start_position] || 0.0,
          duration_seconds: 0.0
        }

        {:reply, :ok,
         %{state | session: pid, monitor_ref: ref, state: :starting, now_playing: now_playing}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:pause, _from, %{session: pid} = state) when is_pid(pid) do
    Log.info(:playback, "pause toggled")
    result = MpvSession.pause(pid)
    {:reply, result, state}
  end

  def handle_call(:pause, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_call(:stop, _from, %{session: pid} = state) when is_pid(pid) do
    Log.info(:playback, "stop requested")
    result = MpvSession.stop(pid)
    {:reply, result, state}
  end

  def handle_call(:stop, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_call({:seek, position}, _from, %{session: pid} = state) when is_pid(pid) do
    Log.info(:playback, "seek to #{position}")
    result = MpvSession.seek(pid, position)
    {:reply, result, state}
  end

  def handle_call({:seek, _position}, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_call(:current_state, _from, state) do
    {:reply, %{state: state.state, now_playing: state.now_playing}, state}
  end

  # --- PubSub Events from MpvSession ---

  @impl true
  def handle_info({:playback_state_changed, new_state, now_playing}, state) do
    Log.info(:playback, "state changed to #{new_state}")

    state =
      case new_state do
        :stopped ->
          %{state | state: :idle, now_playing: nil}

        other ->
          now_playing_map =
            if now_playing do
              Map.merge(state.now_playing || %{}, now_playing)
            else
              state.now_playing
            end

          %{state | state: other, now_playing: now_playing_map}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:playback_progress, progress}, state) do
    now_playing =
      if state.now_playing do
        state.now_playing
        |> Map.put(:position_seconds, progress.position_seconds)
        |> Map.put(:duration_seconds, progress.duration_seconds)
      end

    {:noreply, %{state | now_playing: now_playing}}
  end

  # MpvSession process died
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor_ref: ref} = state) do
    Log.info(:playback, "session process exited")
    {:noreply, %{state | session: nil, monitor_ref: nil, state: :idle, now_playing: nil}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  # --- Private Helpers ---

  defp stop_existing_session(%{session: pid, monitor_ref: ref} = state) when is_pid(pid) do
    Process.demonitor(ref, [:flush])
    SessionSupervisor.terminate_session(pid)
    %{state | session: nil, monitor_ref: nil, state: :idle, now_playing: nil}
  end

  defp stop_existing_session(state), do: state
end
