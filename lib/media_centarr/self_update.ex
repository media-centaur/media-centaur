defmodule MediaCentarr.SelfUpdate do
  use Boundary,
    deps: [MediaCentarr.Settings],
    exports: [UpdateChecker]

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

  alias MediaCentarr.SelfUpdate.{CheckerJob, Storage, UpdateChecker}
  alias MediaCentarr.Topics

  @boot_check_delay_seconds 30
  @stale_ttl_ms :timer.hours(6)

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
  App-boot hydration. Reads the persisted `latest_known` entry into the
  hot-path `:persistent_term` cache and enqueues a fresh check when the
  last persisted check is stale.
  """
  @spec boot!() :: :ok
  def boot! do
    :ok = Storage.hydrate_cache()

    if Storage.stale?(@stale_ttl_ms) do
      # Boot delay keeps the first HTTP call off the supervision-start
      # hot path — the app is serving requests long before this fires.
      _ = CheckerJob.enqueue_after(@boot_check_delay_seconds)
    end

    :ok
  end
end
