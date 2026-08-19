defmodule MediaCentaur.SelfUpdate.AutoApply do
  @moduledoc """
  Applies a detected update automatically when the user has opted in,
  deferring the restart until the screen is idle.

  Owns the single decision "should we install this update *now*?", reacting
  to two event streams:

    * `self_update:status` — `{:check_complete, {:update_available, _}, source}`
      means a newer release exists. Only a `:scheduled` source can auto-apply;
      a `:manual` check is always ignored here (it presents, the user decides).
    * `playback:events` — `{:playback_state_changed, %{state: :playing | :paused
      | :stopped}}` lets it track whether anything is on screen.

  On detection: if `auto_update_enabled` and nothing is playing, apply at once;
  if something is playing, arm a deferred flag. When the last session stops and
  the screen goes idle, the armed update is applied. Because auto-apply only
  ever fires into an idle screen, the restart can never interrupt an active
  viewer — which is why a media center defers rather than applying immediately.

  Idleness is derived from the playback **event stream** rather than a direct
  call into the Playback context — the PubSub topic is the decoupling seam, so
  SelfUpdate keeps no compile-time dependency on Playback. A process started at
  boot sees every session begin, so the tracked set is accurate in practice.

  No-ops entirely unless `SelfUpdate.enabled?()` (prod) — dev rebuilds from
  source and tests never touch the network.

  The branching logic lives in the pure `detection_action/2` and
  `resume_action/3` functions; the GenServer is thin wiring around them.
  """

  use GenServer

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.{SelfUpdate, Topics}

  @type detection_action :: :apply | :defer | :ignore
  @type resume_action :: :apply | :hold

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    SelfUpdate.subscribe()
    # Subscribe to the playback topic directly via the shared Topics registry
    # rather than the Playback facade — keeps SelfUpdate decoupled from the
    # Playback context (no compile-time edge), per the Boundary contract.
    Topics.subscribe(Topics.playback_events())

    state = %{
      deferred?: false,
      active: MapSet.new(),
      apply: Keyword.get(opts, :apply_fun, &SelfUpdate.apply_pending/0),
      auto_enabled?: Keyword.get(opts, :auto_enabled_fun, &auto_update_armed?/0)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:check_complete, {:update_available, _release}, source}, state) do
    case detection_action(state.auto_enabled?.(), playing?(state.active), source) do
      :apply ->
        state.apply.()
        {:noreply, %{state | deferred?: false}}

      :defer ->
        {:noreply, %{state | deferred?: true}}

      :ignore ->
        {:noreply, state}
    end
  end

  def handle_info({:playback_state_changed, %{entity_id: id, state: playback_state}}, state) do
    active = track(state.active, id, playback_state)
    state = %{state | active: active}

    if playback_state == :stopped do
      case resume_action(state.deferred?, state.auto_enabled?.(), playing?(active)) do
        :apply ->
          state.apply.()
          {:noreply, %{state | deferred?: false}}

        :hold ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Everything else on the two topics (check_started, up_to_date/error
  # outcomes, progress ticks, track overrides) is irrelevant here.
  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  What to do when a newer release is detected: `:apply` it now, `:defer`
  until the screen is idle, or `:ignore`.

  `:manual` checks are always ignored — a user-initiated "Check for updates" is
  an attended action that should *present* the update for a deliberate Update
  press, never auto-install. Auto-apply is reserved for the unattended
  `:scheduled` poll: ignore when auto-update is off, defer while something is
  playing, otherwise apply.
  """
  @spec detection_action(boolean(), boolean(), SelfUpdate.check_source()) :: detection_action()
  def detection_action(auto_enabled?, playing?, source)
  def detection_action(_auto_enabled?, _playing?, :manual), do: :ignore
  def detection_action(false, _playing?, _source), do: :ignore
  def detection_action(true, true, _source), do: :defer
  def detection_action(true, false, _source), do: :apply

  @doc """
  What to do when playback stops: `:apply` a deferred update if the screen
  is now idle and auto-update is still on, otherwise `:hold`.
  """
  @spec resume_action(boolean(), boolean(), boolean()) :: resume_action()
  def resume_action(deferred?, auto_enabled?, playing?)
  def resume_action(false, _auto_enabled?, _playing?), do: :hold
  def resume_action(true, false, _playing?), do: :hold
  def resume_action(true, true, true), do: :hold
  def resume_action(true, true, false), do: :apply

  # A paused session still occupies the screen — restarting would interrupt
  # it — so only `:stopped` removes an entity from the active set.
  defp track(active, id, playback_state) when playback_state in [:playing, :paused],
    do: MapSet.put(active, id)

  defp track(active, id, :stopped), do: MapSet.delete(active, id)
  defp track(active, _id, _other), do: active

  defp playing?(active), do: not Enum.empty?(active)

  defp auto_update_armed? do
    SelfUpdate.enabled?() and Config.get(:auto_update_enabled) == true
  end
end
