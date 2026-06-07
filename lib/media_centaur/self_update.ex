defmodule MediaCentaur.SelfUpdate do
  use Boundary,
    deps: [MediaCentaur.Settings],
    exports: [UpdateChecker]

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

  alias MediaCentaur.Platform.Autostart
  alias MediaCentaur.SelfUpdate.{CheckerJob, Storage, UpdateChecker, Updater}
  alias MediaCentaur.Topics

  @boot_check_delay_seconds 30

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
  Subscribes the caller to `self_update:status` — `{:check_started}` and
  `{:check_complete, outcome}` messages fire here when the scheduled or
  manual check runs.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.self_update_status())
  end

  @doc """
  Enqueues a one-off update check immediately.

  Returns `{:ok, job}` or `{:error, reason}`. Deduplicates against an
  already-scheduled job.
  """
  @spec check_now() :: {:ok, Oban.Job.t()} | {:error, term()}
  def check_now, do: CheckerJob.enqueue_now()

  @doc """
  UI snapshot for the Updates card: the last-known release classification
  and release map, read without forcing a network round-trip.

  When the hot cache has gone stale and background checks are enabled on
  the prod release channel, a forced check is kicked in the background and
  `:checking` is returned; its result arrives as `{:check_complete, …}` on
  `self_update:status` (subscribe via `subscribe/0`). Off the prod channel,
  or with background checks disabled, the last-known state is returned and
  the manual button stays the only network trigger.

  This is the seam that keeps the Settings LiveView a thin UI layer — all
  the cache-read, version classification, and manual-only policy lives here.
  """
  @spec view_status() ::
          {UpdateChecker.classification() | :checking | :idle | {:error, term()}, map() | nil}
  def view_status do
    case UpdateChecker.cached_latest_release() do
      {:fresh, {:ok, release}} ->
        {classify(release), release}

      {:fresh, {:error, reason}} ->
        {{:error, reason}, last_known_release()}

      :stale ->
        if enabled?() and MediaCentaur.Config.get(:update_check_enabled) do
          _ = check_now()
          {:checking, last_known_release()}
        else
          last_known()
        end
    end
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
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.self_update_progress())
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
