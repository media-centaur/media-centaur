defmodule MediaCentarr.ReleaseTracking.Views do
  @moduledoc """
  Public read API for ETS-backed ReleaseTracking projections (ADR-041).

  Consumers (typically LiveViews) subscribe to `release_tracking:views`
  once at mount, read view-shaped data via these functions, and
  re-read on `{:release_tracking_view_updated, view_id}` messages.

  Reads are microsecond-scale ETS lookups when the projection's
  `Cache.Worker` is running. When it isn't (test mode, or briefly
  during boot before the first refresh completes), reads fall back
  to the underlying DB query so behaviour is identical from the
  caller's POV.
  """

  alias MediaCentarr.ReleaseTracking.Views.ComingUp
  alias MediaCentarr.ReleaseTracking.Views.ComingUpItem
  alias MediaCentarr.Topics

  @doc "Subscribe the caller to ReleaseTracking projection-refreshed events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.release_tracking_views())
  end

  @doc """
  Returns up to `:limit` Coming Up items in the requested date window,
  ordered by air date ascending. Defaults to 30.
  """
  @spec coming_up(Date.t(), Date.t(), keyword()) :: [ComingUpItem.t()]
  def coming_up(from_date, to_date, opts \\ []), do: ComingUp.read(from_date, to_date, opts)
end
