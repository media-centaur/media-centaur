defmodule MediaCentaurWeb.ViewModel.SeriesDetail do
  @moduledoc """
  Presentation view model for the TV-series detail modal.

  Composes data from two bounded contexts —
  `MediaCentaur.Library` (entity, episodes, watch progress) and
  `MediaCentaur.ReleaseTracking` (announced releases for tracked
  shows) — into a single typed struct the modal LiveView assigns and
  the `DetailPanel` component renders.

  `compose/2` does the cross-context fetch and delegates to `build/4`,
  which is pure and unit-tested without a database.

  Movie collections have their own composer with the same shape
  (`MediaCentaurWeb.ViewModel.CollectionDetail`); leaf kinds (movie /
  video_object) load as plain maps via `Library.ModalEntry`. The detail
  modal's single loader (`MediaCentaurWeb.Live.EntityModal`) resolves
  the container kind once and dispatches between the three.
  """

  alias MediaCentaur.Library
  alias MediaCentaur.Library.ProgressSummary
  alias MediaCentaur.Library.Views.DetailItem
  alias MediaCentaur.Playback.ResumeTarget
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.SeasonView

  # `MediaCentaur.ReleaseTracking.Release` is not exported by its
  # owning boundary (per ADR-029 data-decoupling). The composer reads
  # release records by field, not by struct match — same convention as
  # `upcoming_cards.ex`. The shape contract is documented on
  # `build/4`: `[%{air_date, title, season_number, episode_number,
  # released, in_library}]`.

  @enforce_keys [:entity, :seasons]
  defstruct [
    :entity,
    :progress,
    :progress_records,
    :seasons,
    :extras,
    :resume_target,
    # Cached input to `build/4` — kept on the struct so in-memory
    # progress merges can rebuild `seasons` (which carries
    # per-episode state) without a fresh DB query per playback tick.
    :releases
  ]

  @type t :: %__MODULE__{
          entity: map(),
          progress: map() | nil,
          progress_records: list(),
          seasons: [SeasonView.t()],
          extras: list(),
          resume_target: map() | nil,
          releases: [map()]
        }

  @doc """
  Loads + composes the view model for a TV series. Returns `:not_found`
  if no `:tv_series` projection row matches `entity_id`. Callers reach
  this through the detail modal's single loader, which resolves the
  container kind via `MediaCentaur.Library.Presentable` first — so
  `compose/1` is only ever asked about ids already known to present as
  `:tv_series`, and its projection read is the data fetch, not a probe.

  Reads the Library half from `MediaCentaur.Library.Views.Detail`
  (Pillar-2 ETS projection, microsecond reads in production; falls
  back to a live build in test mode). Cross-context overlays
  (ReleaseTracking releases) compose at this layer
  per ADR-029, mirroring the HomeLive pattern.

  Computes the resume target via `MediaCentaur.Playback.ResumeTarget`
  on the loaded entry, so callers don't have to thread it separately.
  """
  @spec compose(Ecto.UUID.t()) :: {:ok, t()} | :not_found
  def compose(entity_id) when is_binary(entity_id) do
    case Library.Views.detail_by_container(:tv_series, entity_id) do
      %DetailItem{} = detail_item ->
        compose_from_detail(detail_item, entity_id)

      nil ->
        :not_found
    end
  end

  defp compose_from_detail(detail_item, entity_id) do
    entity = detail_item |> DetailItem.to_entity_view() |> Library.MediaTrackOverrides.put_on_entity()
    progress_records = Library.ProgressRecords.list_for_tv_series(entity_id)
    progress_summary = ProgressSummary.compute(entity, progress_records)

    entry = %{
      entity: entity,
      progress: progress_summary,
      progress_records: progress_records
    }

    releases =
      ReleaseTracking.list_relevant_releases_for_library_container(entity_id, :tv_series)

    resume_target = ResumeTarget.compute(entity, progress_records)
    {:ok, build(entry, releases, resume_target)}
  end

  @doc """
  Pure: builds a `%SeriesDetail{}` from a loaded library entry, the
  releases relevant to it, and the precomputed
  resume target.

  Releases are expected to be `MediaCentaur.ReleaseTracking.Release.t()`
  rows (or any map with the same fields: `air_date, title,
  season_number, episode_number, released, in_library`).

  No database access. Tests construct the inputs as fixtures.
  """
  @spec build(map(), [map()], map() | nil) :: t()
  def build(entry, releases, resume_target) do
    seasons = entry.entity.seasons || []
    releases_by_season = Enum.group_by(releases, & &1.season_number)
    library_season_numbers = MapSet.new(seasons, & &1.season_number)
    progress_by_episode_id = index_progress_by_episode_id(entry.progress_records)
    resume_episode_key = resume_target_episode_key(resume_target)

    library_seasons =
      Enum.map(seasons, fn season ->
        build_library_season(
          season,
          Map.get(releases_by_season, season.season_number, []),
          progress_by_episode_id,
          resume_episode_key
        )
      end)

    future_seasons =
      releases_by_season
      |> Enum.reject(fn {n, _} -> MapSet.member?(library_season_numbers, n) end)
      |> Enum.sort_by(fn {n, _} -> n end)
      |> Enum.map(fn {n, rels} -> build_future_season(n, rels) end)

    %__MODULE__{
      entity: entry.entity,
      progress: entry.progress,
      progress_records: entry.progress_records,
      seasons: library_seasons ++ future_seasons,
      extras: entry.entity.extras || [],
      resume_target: resume_target,
      releases: releases
    }
  end

  @doc """
  Updates the in-memory view model with new progress data and rebuilds
  the season list. Used by the modal's progress-tick merge path so
  per-episode `state` and `is_resume_target` flags stay current
  without a fresh DB query.

  Pure: reuses the cached `releases` on the
  existing struct.
  """
  @spec with_progress(t(), map() | nil, list(), map() | nil) :: t()
  def with_progress(%__MODULE__{} = sd, progress, progress_records, resume_target) do
    entry = %{
      entity: sd.entity,
      progress: progress,
      progress_records: progress_records
    }

    build(entry, sd.releases || [], resume_target)
  end

  # --- Library season construction ---

  defp build_library_season(season, season_releases, progress_by_episode_id, resume_episode_key) do
    items =
      build_library_items(
        season,
        season_releases,
        progress_by_episode_id,
        resume_episode_key
      )

    watched_count = count_watched_episodes(season.episodes || [], progress_by_episode_id)
    total_count = max(length(season.episodes || []), length(season.episode_list || []))

    %SeasonView{
      season_number: season.season_number,
      name: Map.get(season, :name),
      kind: :library,
      items: items,
      extras: Map.get(season, :extras),
      watched_count: watched_count,
      total_count: total_count
    }
  end

  # One row per episode number the season knows about, in order: the
  # episode list TMDB gave us, plus any library or release row numbered
  # outside it (a misparsed `E1080`, an absolute episode number).
  #
  # A library row wins over everything — a file is a file. A release row
  # wins over an episode-list entry, because the calendar is refreshed on
  # a cadence where the list is an ingest-time snapshot, and it carries
  # the episode's title.
  #
  # A season whose episode list is empty has never been refreshed
  # (*Refresh episode lists* under Settings → Maintenance); it renders
  # its library and release rows and nothing else, which is what it did
  # before the list existed.
  defp build_library_items(season, releases, progress_by_episode_id, resume_episode_key) do
    episode_map = Map.new(season.episodes || [], &{&1.episode_number, &1})
    release_map = Map.new(releases, &{&1.episode_number, &1})
    listed = Map.new(season.episode_list || [], &{&1.episode_number, &1})
    today = Date.utc_today()

    (Map.keys(listed) ++ Map.keys(episode_map) ++ Map.keys(release_map))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn number ->
      cond do
        episode = Map.get(episode_map, number) ->
          build_library_item(episode, season.season_number, progress_by_episode_id, resume_episode_key)

        release = Map.get(release_map, number) ->
          build_release_item(release)

        true ->
          build_listed_item(Map.fetch!(listed, number), season.season_number, today)
      end
    end)
  end

  # An episode TMDB lists that no file was imported for. Dated in the
  # future means it has not aired; a past date — or no date at all — is a
  # gap the person can act on, because absence of a date is not evidence
  # that an episode is still to come.
  defp build_listed_item(entry, season_number, today) do
    fields = [
      season_number: season_number,
      episode_number: entry.episode_number,
      title: entry.name,
      air_date: entry.air_date
    ]

    if entry.air_date && Date.compare(entry.air_date, today) == :gt,
      do: struct!(EpisodeRow.Upcoming, fields),
      else: struct!(EpisodeRow.Missing, fields)
  end

  defp build_library_item(episode, season_number, progress_by_episode_id, resume_episode_key) do
    progress = Map.get(progress_by_episode_id, episode.id)

    %EpisodeRow.Library{
      episode: episode,
      season_number: season_number,
      progress: progress,
      state: episode_state(progress),
      is_resume_target: resume_episode_key == {season_number, episode.episode_number}
    }
  end

  # --- Future season construction ---

  defp build_future_season(season_number, releases) do
    items =
      releases
      |> Enum.sort_by(& &1.episode_number)
      |> Enum.map(&build_release_item/1)

    %SeasonView{
      season_number: season_number,
      name: nil,
      kind: :future,
      items: items,
      extras: [],
      watched_count: nil,
      total_count: length(items)
    }
  end

  # A release row becomes whichever row its air date says it is. The DB
  # query already excludes aired-and-in-library rows, so an aired release
  # here is one the library does not have — the same state an episode-list
  # entry with a past date describes, and therefore the same row. The
  # calendar knows the episode's title, so both carry it.
  defp build_release_item(release) do
    fields = [
      season_number: release.season_number,
      episode_number: release.episode_number,
      title: release.title,
      air_date: release.air_date
    ]

    if aired?(release),
      do: struct!(EpisodeRow.Missing, fields),
      else: struct!(EpisodeRow.Upcoming, fields)
  end

  defp aired?(%{air_date: %Date{} = air_date}), do: Date.compare(air_date, Date.utc_today()) != :gt
  defp aired?(_), do: false

  # --- Helpers (extracted from DetailPanel) ---

  # Both `Detail.PlayableRow.state_from_progress/1` and this caller delegate to the
  # same Library helper so the rendering layer and the composition
  # layer can't drift.
  defdelegate episode_state(progress),
    to: MediaCentaur.Library.ProgressRecords,
    as: :state_from_progress

  defp count_watched_episodes(episodes, progress_by_episode_id) do
    Enum.count(episodes, fn episode ->
      case Map.get(progress_by_episode_id, episode.id) do
        %{completed: true} -> true
        _ -> false
      end
    end)
  end

  defp index_progress_by_episode_id(progress_records) do
    # WatchProgress is keyed by `playable_item_id` since Library Schema
    # v2 Phase 2 Task C. The container id (Episode UUID) lives on the
    # synthesised `:playable_item` field that
    # `EntityShape.extract_progress/2` attaches at runtime (or that
    # tests inject via `build_progress`).
    progress_records
    |> Enum.map(fn record ->
      {MediaCentaur.Library.ProgressRecords.progress_container_id(record), record}
    end)
    |> Enum.reject(fn {episode_id, _record} -> is_nil(episode_id) end)
    |> Map.new()
  end

  # ResumeTarget.compute returns the string-keyed hint shape produced
  # by build_hint/4 — the same shape detail_panel previously matched on
  # via `resume_episode_key/1`.
  defp resume_target_episode_key(%{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode), do: {season, episode}

  defp resume_target_episode_key(_), do: nil
end
