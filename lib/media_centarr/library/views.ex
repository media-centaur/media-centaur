defmodule MediaCentarr.Library.Views do
  @moduledoc """
  Public read API for ETS-backed Library projections (ADR-041).

  Consumers (typically LiveViews) subscribe to `library:views` once at
  mount, read view-shaped data via these functions, and re-read on
  `{:library_view_updated, view_id}` messages.

  Reads are microsecond-scale ETS lookups when the projection's
  `Cache.Worker` is running. When it isn't (test mode, or briefly
  during boot before the first refresh completes), reads fall back
  to the underlying DB query so behaviour is identical from the
  caller's POV.
  """

  alias MediaCentarr.Library.Views.ContinueWatching
  alias MediaCentarr.Topics

  @doc "Subscribe the caller to projection-refreshed events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())
  end

  @doc """
  Returns up to `:limit` Continue Watching items in display order
  (most-recently-watched first). Defaults to 12.
  """
  @spec continue_watching(keyword()) :: [ContinueWatchingItem.t()]
  def continue_watching(opts \\ []), do: ContinueWatching.read(opts)
end
