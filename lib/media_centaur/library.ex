defmodule MediaCentaur.Library do
  use Boundary,
    deps: [MediaCentaur.Retention, MediaCentaur.Subtitles],
    exports: [
      AbsenceSweeper,
      Availability,
      Browser,
      ChangeLog,
      Completeness,
      Containers,
      ContentUrls,
      ContinueWatchingProgress,
      Deletion,
      EntityShape,
      EntityView,
      Episode,
      EpisodeList,
      Episodes,
      Events,
      Events.EntitiesChanged,
      ExternalId,
      ExternalIds,
      Extra,
      ExtraFile,
      Extras,
      FileEventHandler,
      FilePresence,
      Files,
      Image,
      ImageHealth,
      Images,
      MediaInfo,
      MediaTrackOverride,
      MediaTrackOverrides,
      ModalEntry,
      Movie,
      MovieList,
      MovieSeries,
      Presentable,
      Person,
      PlayableItem,
      PlayableItems,
      Posters,
      Progress,
      Progress.Events,
      Progress.Events.ProgressFlushed,
      Progress.Events.ProgressHydrated,
      Progress.Events.ProgressTicked,
      Progress.Worker,
      ProgressRecords,
      ProgressSummary,
      Relink,
      SearchIndex,
      Season,
      Seasons,
      Stats,
      TVSeries,
      TypeResolver,
      VideoObject,
      Views,
      Views.BrowseItem,
      Views.ContinueWatching,
      Views.ContinueWatchingItem,
      Views.Detail,
      Views.DetailItem,
      Views.DetailItem.WatchedFile,
      Views.HeroCandidates,
      Views.HeroCandidatesItem,
      Views.RecentlyAdded,
      Views.RecentlyAddedItem,
      WatchedFile
    ]

  @moduledoc """
  The media library context.

  Nearly all of the library lives in modules beneath this one, each
  owning a single idea. This module keeps only what belongs to the
  context as a whole — subscribing to change events, and the home-page
  feed delegators the `Views.*` projections read through.

  ## Where things live

  | Concern | Module |
  |---|---|
  | Container records (TVSeries / MovieSeries / Movie / VideoObject) | `Library.Containers` |
  | Seasons, episodes, extras | `Library.Seasons`, `Library.Episodes`, `Library.Extras` |
  | Playable-leaf identity | `Library.PlayableItems` |
  | Files on disk (WatchedFile + ExtraFile) | `Library.Files` |
  | Probed technical metadata | `Library.MediaInfo` |
  | Relink-on-move | `Library.Relink`, `Library.MoveMatcher` |
  | Watch state (DB) | `Library.ProgressRecords` |
  | Watch state (in-memory projection) | `Library.Progress` |
  | Artwork | `Library.Images`, `Library.Posters`, `Library.ImageHealth` |
  | External identifiers | `Library.ExternalIds` |
  | Remembered audio/subtitle tracks | `Library.MediaTrackOverrides` |
  | Movie-vs-collection hoist rule | `Library.Presentable`, `Library.PresentableQueries` |
  | Detail-modal view-model | `Library.ModalEntry` |
  | Search catalogue | `Library.SearchIndex` |
  | Status-page counts | `Library.Stats` |
  | Change feed | `Library.ChangeLog` |
  | Idempotent write primitives | `Library.Writes` |
  | Read projections | `Library.Views.*`, `Library.Browser`, `Library.HomeFeed` |
  """

  alias MediaCentaur.Library.{HomeFeed, Helpers}
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to library entity change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.library_updates())
  end

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"`
  PubSub topic.
  """
  defdelegate broadcast_entities_changed(entity_ids), to: Helpers

  @doc "See `MediaCentaur.Library.HomeFeed.list_in_progress/1` (Continue Watching)."
  def list_in_progress(opts \\ []), do: HomeFeed.list_in_progress(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_recently_added/1`."
  def list_recently_added(opts \\ []), do: HomeFeed.list_recently_added(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_hero_candidates/1`."
  def list_hero_candidates(opts \\ []), do: HomeFeed.list_hero_candidates(opts)
end
