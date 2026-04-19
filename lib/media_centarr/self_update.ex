defmodule MediaCentarr.SelfUpdate do
  use Boundary,
    deps: [MediaCentarr.Settings],
    exports: [Service, UpdateChecker]

  @moduledoc """
  In-app release check + self-update for Media Centarr.

  Owns the relationship between the running release and the
  `media-centarr/media-centarr` GitHub repository: polls the GitHub
  Releases API for the latest tag, caches the result, and drives the
  download → verify → stage → hand-off pipeline that applies an update.

  The context is deliberately small and boundary-visible so the web
  layer can wire the Settings > Overview card, a scheduled Oban
  worker can keep state fresh, and nothing else reaches into the
  update internals directly.

  ## Trust model

  Trust is anchored to GitHub's account and release process for
  `media-centarr/media-centarr`. TLS verification is always on, the
  download URL is built from a fixed template (never pulled from API
  response fields), and `tag_name` values are validated against a
  strict semver regex before being used anywhere. A compromised
  GitHub account defeats these checks — release signing is tracked
  as a follow-up.
  """

  alias MediaCentarr.SelfUpdate.{CheckerJob, Service, Storage, UpdateChecker, Updater}
  alias MediaCentarr.Topics

  @boot_check_delay_seconds 30

  @doc """
  True only when update checks should run. Returns false in dev and test —
  dev builds update by rebuilding from source; test builds never hit the
  network.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:media_centarr, :environment, :dev) == :prod
  end

  @doc """
  Subscribes the caller to `self_update:status` — `{:check_started}` and
  `{:check_complete, outcome}` messages fire here when the scheduled or
  manual check runs.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_status())
  end

  @doc """
  Enqueues a one-off update check immediately.

  Returns `{:ok, job}` or `{:error, reason}`. Deduplicates against an
  already-scheduled job.
  """
  @spec check_now() :: {:ok, Oban.Job.t()} | {:error, term()}
  def check_now, do: CheckerJob.enqueue_now()

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
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_progress())
  end

  @doc """
  Applies the cached pending release via the `Updater` GenServer.

  Returns `:ok` if the apply pipeline has started,
  `{:error, :no_update_pending | :invalid_tag | :already_running}` otherwise.
  """
  @spec apply_pending() ::
          :ok | {:error, :no_update_pending | :invalid_tag | :already_running}
  def apply_pending, do: Updater.apply_pending()

  @doc "Returns the current `Updater` state."
  @spec current_status() :: Updater.status()
  def current_status, do: Updater.status()

  @doc """
  Records the outcome of a release check into both the durable store and
  the hot-path cache. Called by `CheckerJob` and by the LiveView's
  manual check path so the two layers never drift.

  See `Storage.record_check_result/1` for the full contract.
  """
  @spec record_check_result({:ok, map()} | {:error, term()}) ::
          {:ok, UpdateChecker.classification(), map()} | {:error, term()}
  def record_check_result(outcome), do: Storage.record_check_result(outcome)

  @doc "Returns the systemd state for the media-centarr unit. See `Service.state/1`."
  @spec service_state() :: Service.state()
  def service_state, do: Service.state()

  @doc "Queues a systemd-managed restart of the running unit."
  @spec service_restart() :: :ok | {:error, term()}
  def service_restart, do: Service.restart()

  @doc "Queues a systemd-managed stop of the running unit."
  @spec service_stop() :: :ok | {:error, term()}
  def service_stop, do: Service.stop()

  @doc "Fetches the textual output of `systemctl --user status` for the unit."
  @spec service_status_output() :: {:ok, String.t()} | {:error, term()}
  def service_status_output, do: Service.status_output()

  @doc """
  App-boot hydration. Reads the persisted `latest_known` entry into the
  hot-path `:persistent_term` cache and unconditionally enqueues a
  fresh check.

  The boot check used to be gated on `Storage.stale?` — but that let a
  stale persisted row survive indefinitely on installs that restart
  often, because each boot would rehydrate it with a fresh 5-minute
  TTL before the UI ever asked for a new check. Always enqueueing is
  safe: `CheckerJob`'s 1-hour `unique` constraint dedupes with a cron
  tick that just fired, so this can't spam the GitHub API.
  """
  @spec boot!() :: :ok
  def boot! do
    :ok = Storage.hydrate_cache()
    # Boot delay keeps the first HTTP call off the supervision-start
    # hot path — the app is serving requests long before this fires.
    _ = CheckerJob.enqueue_after(@boot_check_delay_seconds)
    :ok
  end
end
