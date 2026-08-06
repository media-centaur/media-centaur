defmodule MediaCentaur.Status.Views do
  @moduledoc """
  Public read API for ETS-backed Status-page projections (instant-navigation
  campaign; same shape as `MediaCentaur.Library.Views` / ADR-041).

  The Status page's expensive slices — the library overview (per-image disk
  check + several aggregate counts) and the storage picture (`df` probes that
  can block on sleeping drives) — are computed off the navigation path by
  `Cache.Worker`-driven projections and read here as microsecond ETS lookups.
  This is what lets `StatusLive` render a complete first paint on both the
  dead and connected mounts instead of a skeleton with async pops.

  Consumers subscribe to `status:views` once at mount, read via these
  functions, and re-read on `{:status_view_updated, view_id}` messages.

  When a projection's Worker isn't running (test mode, or briefly during
  boot before the first refresh completes), reads fall back to the live
  computation so behaviour is identical from the caller's POV.
  """

  alias MediaCentaur.Status.LibraryOverview
  alias MediaCentaur.Status.Views.Overview
  alias MediaCentaur.Status.Views.Storage
  alias MediaCentaur.Status.Views.StorageSnapshot
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to projection-refreshed events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.status_views())
  end

  @doc """
  Returns the cached library-overview snapshot for the Status page's
  "Your library" section.
  """
  @spec overview() :: LibraryOverview.t()
  def overview, do: Overview.read()

  @doc """
  Returns the cached storage snapshot — drive capacity per mount point,
  at-risk absence summary, and per-media-dir reachability.
  """
  @spec storage() :: StorageSnapshot.t()
  def storage, do: Storage.read()
end
