defmodule MediaCentarr.Acquisition.Reactor.Handlers do
  @moduledoc """
  Translates release-tracking PubSub events into pursuit-orchestration
  side effects.

  Called by `Acquisition.Reactor` (the GenServer that owns the
  subscription). Splitting the handlers out of the Reactor keeps the
  GenServer module trivial — it's just a subscribe-and-dispatch shim —
  while keeping the auto-grab policy + per-decision branching here in
  a testable plain-function module.

  ## Why this module exists separately from `Acquisition`

  Until 2026-05-14 the dispatcher logic lived on the
  `Acquisition` facade as a public `handle_release_ready_event/2`
  function with private `apply_decision/5` clauses. That conflated two
  responsibilities on the facade: "what's the public API of the
  Acquisition context?" and "how does the Reactor translate domain
  events?". Pulling the handlers out makes the facade thinner and
  keeps the Reactor's tested surface (these functions) explicit.

  ## Public surface

  - `release_ready/2` — process a `{:release_ready, item, release}`
    event by asking `AutoAcquirePolicy.decide/3` whether to enqueue,
    skip, or cancel, and applying that decision.

  Pure dispatch + Acquisition-context side effects. No GenServer state.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{AutoGrabPolicy, AutoGrabSettings, CancelReasons}
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Format
  alias MediaCentarr.ReleaseTracking

  @doc """
  Processes a release-ready event. Looks up any existing pursuit, asks
  `AutoGrabPolicy.decide/3`, and applies the resulting decision
  (enqueue / skip / cancel).

  Returns `:ok` unconditionally — auto-grab failures are logged and
  swallowed; the Reactor doesn't crash on a single bad release.
  Auto-grab globally off (`AutoGrabService.running?/0 == false`)
  short-circuits at the entry point.
  """
  @spec release_ready(struct(), struct()) :: :ok
  def release_ready(item, release) do
    if Acquisition.auto_grab_running?() do
      do_release_ready(item, release)
    end

    :ok
  end

  defp do_release_ready(item, release) do
    settings = AutoGrabSettings.load()

    tmdb_id = to_string(item.tmdb_id)
    tmdb_type = ReleaseTracking.tmdb_type_for(item.media_type)

    existing_pursuit =
      Pursuits.find_by_tmdb_recipe(%{
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type,
        season_number: release.season_number,
        episode_number: release.episode_number
      })

    existing_target = existing_pursuit && Pursuits.current_target(existing_pursuit)
    existing_status = existing_target && existing_target.status

    effective_mode = AutoGrabSettings.effective_mode(item.auto_grab_mode, settings)

    decision =
      AutoGrabPolicy.decide(release.in_library, existing_status,
        prowlarr_ready: Capabilities.prowlarr_ready?(),
        mode: effective_mode
      )

    apply_decision(decision, item, release, settings, existing_target)
    :ok
  end

  defp apply_decision(:enqueue, item, release, settings, _existing_target) do
    case Acquisition.enqueue(
           to_string(item.tmdb_id),
           ReleaseTracking.tmdb_type_for(item.media_type),
           item.name,
           season_number: release.season_number,
           episode_number: release.episode_number,
           min_quality: AutoGrabSettings.effective_min_quality(item.min_quality, settings),
           max_quality: AutoGrabSettings.effective_max_quality(item.max_quality, settings),
           quality_4k_patience_hours:
             AutoGrabSettings.effective_patience_hours(
               item.quality_4k_patience_hours,
               settings
             )
         ) do
      {:ok, _target} ->
        Log.info(:library, "auto-acquisition armed — #{item.name} #{describe_release(release)}")

      {:error, reason} ->
        Log.warning(:library, "auto-acquisition enqueue failed — #{inspect(reason)}")
    end
  end

  defp apply_decision({:cancel, :user_disabled}, item, _release, _settings, existing_target) do
    if existing_target do
      Acquisition.cancel_target(existing_target.id, CancelReasons.user_disabled())
      Log.info(:library, "auto-acquisition cancelled (user disabled) — #{item.name}")
    end
  end

  defp apply_decision({:skip, :acquisition_unavailable}, item, _release, _settings, _target) do
    Log.info(:library, "auto-acquisition skipped (prowlarr not ready) — #{item.name}")
  end

  defp apply_decision({:skip, :mode_off}, _item, _release, _settings, _target), do: :ok
  defp apply_decision({:skip, :already_in_library}, _item, _release, _settings, _target), do: :ok
  defp apply_decision({:skip, :already_active}, _item, _release, _settings, _target), do: :ok

  defp describe_release(%{season_number: season, episode_number: episode}),
    do: Format.episode_label(season, episode)
end
