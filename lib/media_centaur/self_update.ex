defmodule MediaCentaur.SelfUpdate do
  use Boundary,
    deps: [
      MediaCentaur.ErrorReports,
      MediaCentaur.HttpClient,
      MediaCentaur.Retention,
      MediaCentaur.Settings
    ],
    exports: [Changelog, StagingSweep, UpdateChecker]

  @moduledoc """
  In-app release check + self-update for Media Centaur.

  Owns the relationship between the running release and the
  `media-centaur/media-centaur` GitHub repository: polls the GitHub
  Releases API for the latest tag, caches the result, and drives the
  download → verify → stage → hand-off pipeline that applies an update.

  The context is deliberately small and boundary-visible so the web
  layer can wire the Settings > Overview card, a scheduled Oban
  worker can keep state fresh, and nothing else reaches into the
  update internals directly.

  ## Trust model

  Trust is anchored to GitHub's account and release process for
  `media-centaur/media-centaur`. TLS verification is always on, the
  download URL is built from a fixed template (never pulled from API
  response fields), and `tag_name` values are validated against a
  strict semver regex before being used anywhere. A compromised
  GitHub account defeats these checks — release signing is tracked
  as a follow-up.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Platform.Autostart
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.SelfUpdate.{CheckerJob, Health, History, Storage, UpdateChecker, Updater}
  alias MediaCentaur.Topics

  @boot_check_delay_seconds 30

  @typedoc """
  What initiated a check. `:scheduled` is the unattended background poll (the
  only source that may auto-apply). `:manual` is a user-pressed "Check for
  updates" — an attended action that presents the result for a deliberate
  Update press and never auto-installs.
  """
  @type check_source :: :scheduled | :manual

  @doc """
  True only when update checks should run. Returns false in dev and test —
  dev builds update by rebuilding from source; test builds never hit the
  network.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:media_centaur, :environment, :dev) == :prod
  end

  @doc """
  True when the unattended checker will actually run on its tick: this build
  runs checks (`enabled?/0`) *and* the user has background checks switched on.
  The checker job and the diagnostics probe share this one gate, so a build
  that never checks can never look like a stalled scheduler.
  """
  @spec scheduled_checks_enabled?() :: boolean()
  def scheduled_checks_enabled? do
    enabled?() and Config.get(:update_check_enabled) == true
  end

  @doc """
  Subscribes the caller to `self_update:status` — `{:check_started}` and
  `{:check_complete, outcome, source}` messages fire here when the scheduled or
  manual check runs. `source` is `:scheduled | :manual`; only `:scheduled`
  drives AutoApply (a manual check presents, the user decides).
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.self_update_status())
  end

  @doc """
  UI snapshot for the Updates card: the last-known release classification and
  release map, read from the hot cache with **no side effects** — it never
  triggers a network round-trip. A `:stale` cache falls back to the last-known
  state (or `{:idle, nil}` when nothing has been observed).

  Passive surfaces (the Settings Updates card, the Status board widget) read
  this snapshot only — the networked poll is owned entirely by the scheduled
  `CheckerJob`. A manual refresh runs `run_check/0` directly.
  """
  @spec view_status() ::
          {UpdateChecker.classification() | :idle | {:error, term()}, map() | nil}
  def view_status do
    case UpdateChecker.cached_latest_release() do
      {:fresh, {:ok, release}} -> {classify(release), release}
      {:fresh, {:error, reason}} -> {{:error, reason}, last_known_release()}
      :stale -> last_known()
    end
  end

  @doc """
  Runs an update check **synchronously** and returns its outcome —
  `{classification, release}` or `{:error, reason}`. Fetches the latest release,
  records it across the durable store, the hot cache, and the health projection,
  then broadcasts `{:check_started}` and `{:check_complete, outcome, source}` on
  `self_update:status` so AutoApply and passive views react.

  `source` (`:scheduled | :manual`, default `:scheduled`) tags who initiated the
  check. AutoApply only auto-installs on `:scheduled`; a `:manual` check still
  refreshes every view's displayed status but never triggers an install — the
  user pressed the button to decide, so the manual path presents the update for
  a deliberate Update press.

  The single check implementation: the scheduled `CheckerJob` calls it with
  `:scheduled`, and the Settings LiveView wraps it in `start_async/3` with
  `:manual` so a manual check resolves its UI through `handle_async` — a
  guaranteed completion path that does not hinge on the broadcast.
  """
  @spec run_check(check_source()) :: {UpdateChecker.classification(), map()} | {:error, term()}
  def run_check(source \\ :scheduled) when source in [:scheduled, :manual] do
    broadcast({:check_started})
    outcome = do_run_check()
    broadcast({:check_complete, outcome, source})
    outcome
  end

  defp do_run_check do
    case Storage.record_check_result(UpdateChecker.latest_release()) do
      {:ok, classification, release} ->
        Health.record_check_success()
        {classification, release}

      {:error, reason} = error ->
        Health.record_check_failure()
        Log.warning(:system, "update check failed: #{inspect(reason)}")
        error
    end
  end

  defp broadcast(message) do
    Topics.publish(Topics.self_update_status(), message)
  end

  @doc """
  Last-known release classification and release map, read from the hot cache
  with **no side effects** — never triggers a check (unlike `view_status/0`).

  Returns `{:idle, nil}` when nothing has been observed yet. Used by passive
  surfaces like the Status board's Updates widget that should display the
  current state without provoking a network poll.
  """
  @spec last_known_status() ::
          {UpdateChecker.classification() | :idle, map() | nil}
  def last_known_status, do: last_known()

  @doc """
  Timestamp of the last successful release check, or `:none` if no check
  has ever succeeded. Used by the Settings UI for the "Last checked …" label.
  """
  @spec last_check_at() :: {:ok, DateTime.t()} | :none
  def last_check_at, do: Storage.get_last_check_at()

  @doc """
  Returns the upgrade history newest-first — `[%{version, recorded_at}]` — for
  the Status → Updates drill-in. See `MediaCentaur.SelfUpdate.History`.
  """
  @spec upgrade_history() :: [History.entry()]
  def upgrade_history, do: History.list()

  @doc """
  Returns the last known release — either freshly cached in
  `:persistent_term` or hydrated from Settings.Entry at boot — or
  `:none` when nothing has been observed yet.
  """
  @spec cached_release() :: {:ok, map()} | :none
  def cached_release do
    case UpdateChecker.cached_latest_release() do
      {:fresh, {:ok, release}} -> {:ok, release}
      {:fresh, {:error, _}} -> :none
      :stale -> :none
    end
  end

  @doc """
  Subscribes the caller to `self_update:progress` — apply-time phase
  transitions (`{:progress, phase, percent}`) and failures
  (`{:apply_failed, reason}`) fire here.
  """
  @spec subscribe_progress() :: :ok | {:error, term()}
  def subscribe_progress do
    Topics.subscribe(Topics.self_update_progress())
  end

  @doc """
  Applies the cached pending release via the `Updater` GenServer.

  Returns `:ok` if the apply pipeline has started,
  `{:error, :no_update_pending | :invalid_tag | :already_running}` otherwise.
  """
  @spec apply_pending() ::
          :ok | {:error, :no_update_pending | :invalid_tag | :already_running}
  def apply_pending, do: Updater.apply_pending()

  @doc """
  Cancels an in-flight apply if it's still in a safe phase. See
  `Updater.cancel/1` for the full contract.
  """
  @spec cancel_apply() :: :ok | {:error, :not_running | :past_point_of_no_return}
  def cancel_apply, do: Updater.cancel()

  @doc "Returns the current `Updater` state."
  @spec current_status() :: Updater.status()
  def current_status, do: Updater.status()

  @doc """
  Records the outcome of a release check into both the durable store and
  the hot-path cache. Called by `CheckerJob` — the single check path —
  so the durable and hot-path layers never drift.

  See `Storage.record_check_result/1` for the full contract.
  """
  @spec record_check_result({:ok, map()} | {:error, term()}) ::
          {:ok, UpdateChecker.classification(), map()} | {:error, term()}
  def record_check_result(outcome), do: Storage.record_check_result(outcome)

  @doc "Returns the autostart-system state for the media-centaur unit. See `Platform.Autostart.state/1`."
  @spec service_state() :: Autostart.state()
  def service_state, do: Autostart.state()

  @doc """
  Returns the autostart unit this BEAM is under, or `nil` — cheap
  (no shell-out). Use in hot paths where you only need to know if
  we're managed and which unit, not its active/enabled state.
  """
  @spec detected_unit() :: String.t() | nil
  def detected_unit, do: Autostart.detected_unit()

  @doc "Queues an autostart-managed restart of the running unit."
  @spec service_restart() :: :ok | {:error, term()}
  def service_restart, do: Autostart.restart()

  @doc "Queues an autostart-managed stop of the running unit."
  @spec service_stop() :: :ok | {:error, term()}
  def service_stop, do: Autostart.stop()

  @doc "Fetches the textual status output for the autostart-managed unit."
  @spec service_status_output() :: {:ok, String.t()} | {:error, term()}
  def service_status_output, do: Autostart.status_output()

  @doc """
  App-boot hydration. Reads the persisted `latest_known` entry into the
  hot-path `:persistent_term` cache and unconditionally enqueues a
  fresh check.

  The boot check used to be gated on `Storage.stale?` — but that let a
  stale persisted row survive indefinitely on installs that restart
  often, because each boot would rehydrate it with a fresh 5-minute
  TTL before the UI ever asked for a new check. Always enqueueing is
  safe: `CheckerJob`'s `unique` window dedupes with a cron tick that
  just fired, and the `due_for_check?/5` gate skips a boot check that
  isn't actually due, so this can't spam the GitHub API.
  """
  @spec boot!() :: :ok
  def boot! do
    :ok = Storage.hydrate_cache()
    # Record the version we just booted into, if it changed since last boot.
    # Path-agnostic upgrade capture: keys off the running version, not any one
    # apply path. Prod-gated by the `enabled?/0` guard around boot!/0 in
    # application.ex — dev rebuilds from source and must not pollute the log.
    :ok = History.record_boot_version()
    # Boot delay keeps the first HTTP call off the supervision-start
    # hot path — the app is serving requests long before this fires.
    _ = CheckerJob.enqueue_after(@boot_check_delay_seconds)
    :ok
  end

  defp classify(release), do: UpdateChecker.compare(release, MediaCentaur.Version.current_version())

  # Last-known release for *display*, read from the hot cache only — never
  # the database, so `view_status/0` stays safe on the render path. The cache
  # is hydrated from durable storage at boot, so it survives a lapsed TTL.
  defp last_known do
    case UpdateChecker.last_cached_release() do
      {:ok, release} -> {classify(release), release}
      _ -> {:idle, nil}
    end
  end

  defp last_known_release do
    case UpdateChecker.last_cached_release() do
      {:ok, release} -> release
      _ -> nil
    end
  end
end
