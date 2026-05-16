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

  alias MediaCentarr.Library.Views.Browse
  alias MediaCentarr.Library.Views.BrowseItem
  alias MediaCentarr.Library.Views.ContinueWatching
  alias MediaCentarr.Library.Views.ContinueWatchingItem
  alias MediaCentarr.Library.Views.HeroCandidates
  alias MediaCentarr.Library.Views.HeroCandidatesItem
  alias MediaCentarr.Library.Views.RecentlyAdded
  alias MediaCentarr.Library.Views.RecentlyAddedItem
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

  @doc """
  Returns up to `:limit` Hero Candidate items — entities suitable as
  the Home page hero (those with both a backdrop and a description).
  Defaults to 12.
  """
  @spec hero_candidates(keyword()) :: [HeroCandidatesItem.t()]
  def hero_candidates(opts \\ []), do: HeroCandidates.read(opts)

  @doc """
  Returns up to `:limit` Recently Added items in newest-first order.
  Defaults to 16.
  """
  @spec recently_added(keyword()) :: [RecentlyAddedItem.t()]
  def recently_added(opts \\ []), do: RecentlyAdded.read(opts)

  @doc """
  Returns the library browse grid as pre-shaped `BrowseItem` structs
  in display order (alphabetical by name, case-insensitive).

  Reads bypass the GenServer via `:ets.tab2list/1` when the
  projection's Cache.Worker is running; falls back to the underlying
  DB query when it isn't (test mode / pre-boot window).

  Options:
    * `:kind`         — filter by `:movie | :tv_series | :movie_series | :video_object`
    * `:present_only` — when `true`, exclude entities whose backing
                        files aren't currently reachable
  """
  @spec browse(keyword()) :: [BrowseItem.t()]
  def browse(opts \\ []), do: Browse.read(opts)
end
