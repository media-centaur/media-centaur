defmodule MediaCentarrWeb.ViewModel.SeriesDetail do
  @moduledoc """
  Presentation view model for the TV-series detail modal.

  Composes data from two bounded contexts —
  `MediaCentarr.Library` (entity, episodes, watch progress) and
  `MediaCentarr.ReleaseTracking` (announced releases for tracked
  shows) — into a single typed struct the modal LiveView assigns and
  the `DetailPanel` component renders.

  `compose/2` does the cross-context fetch and delegates to `build/4`,
  which is pure and unit-tested without a database.

  Movie / movie_series entities are not handled here — they go through
  `Library.load_modal_entry/1` directly, since their detail pages don't
  surface release-tracking data.
  """

  alias MediaCentarr.Library
  alias MediaCentarr.Playback.ResumeTarget
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarrWeb.ViewModel.EpisodeListItem
  alias MediaCentarrWeb.ViewModel.SeasonView

  # `MediaCentarr.ReleaseTracking.Release` is not exported by its
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
    :tracking_status,
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
          tracking_status: :watching | :ignored | nil,
          seasons: [SeasonView.t()],
          extras: list(),
          resume_target: map() | nil,
          releases: [map()]
        }

  @doc """
  Loads + composes the view model for a TV series. Returns
  `:not_found` if no library entity matches `entity_id` (or it's
  filtered by the present-files gating in `Library.load_modal_entry/1`).

  Returns `{:error, :wrong_type}` if the entity exists but isn't a
  `:tv_series` — the modal should fall back to its movie/movie_series
  flow.

  Computes the resume target via `MediaCentarr.Playback.ResumeTarget`
  on the loaded entry, so callers don't have to thread it separately.
  """
  @spec compose(Ecto.UUID.t()) :: {:ok, t()} | :not_found | {:error, :wrong_type}
  def compose(entity_id) when is_binary(entity_id) do
    case Library.load_modal_entry(entity_id) do
      {:ok, %{entity: %{type: :tv_series}} = entry} ->
        releases =
          ReleaseTracking.list_relevant_releases_for_library_container(entity_id, :tv_series)

        tracking_status = lookup_tracking_status(entry.entity)
        resume_target = ResumeTarget.compute(entry.entity, entry.progress_records)
        {:ok, build(entry, releases, tracking_status, resume_target)}

      {:ok, _other_type} ->
        {:error, :wrong_type}

      :not_found ->
        :not_found
    end
  end

  @doc """
  Pure: builds a `%SeriesDetail{}` from a loaded library entry, the
  releases relevant to it, the tracking status, and the precomputed
  resume target.

  Releases are expected to be `MediaCentarr.ReleaseTracking.Release.t()`
  rows (or any map with the same fields: `air_date, title,
  season_number, episode_number, released, in_library`).

  No database access. Tests construct the inputs as fixtures.
  """
  @spec build(map(), [map()], :watching | :ignored | nil, map() | nil) :: t()
  def build(entry, releases, tracking_status, resume_target) do
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
      tracking_status: tracking_status,
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

  Pure: reuses the cached `releases` and `tracking_status` on the
  existing struct.
  """
  @spec with_progress(t(), map() | nil, list(), map() | nil) :: t()
  def with_progress(%__MODULE__{} = sd, progress, progress_records, resume_target) do
    entry = %{
      entity: sd.entity,
      progress: progress,
      progress_records: progress_records
    }

    build(entry, sd.releases || [], sd.tracking_status, resume_target)
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
    total_count = max(length(season.episodes || []), season.number_of_episodes || 0)

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

  # Merge the library episodes (with gap-filling) and the season's
  # releases into one ordered list. Release wins over Missing for the
  # same {season, episode} — richer data displaces the bare placeholder.
  defp build_library_items(season, releases, progress_by_episode_id, resume_episode_key) do
    episode_map = Map.new(season.episodes || [], &{&1.episode_number, &1})
    release_map = Map.new(releases, &{&1.episode_number, &1})

    max_known_episode =
      season.episodes
      |> List.wrap()
      |> Enum.map(& &1.episode_number)
      |> Enum.max(fn -> 0 end)

    max_known_release =
      releases
      |> Enum.map(& &1.episode_number)
      |> Enum.max(fn -> 0 end)

    upper = Enum.max([season.number_of_episodes || 0, max_known_episode, max_known_release])

    if upper == 0 do
      []
    else
      for n <- 1..upper do
        cond do
          episode = Map.get(episode_map, n) ->
            build_library_item(episode, season.season_number, progress_by_episode_id, resume_episode_key)

          release = Map.get(release_map, n) ->
            build_upcoming_item(release)

          true ->
            %EpisodeListItem.Missing{
              season_number: season.season_number,
              episode_number: n
            }
        end
      end
    end
  end

  defp build_library_item(episode, season_number, progress_by_episode_id, resume_episode_key) do
    progress = Map.get(progress_by_episode_id, episode.id)

    %EpisodeListItem.Library{
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
      |> Enum.map(&build_upcoming_item/1)

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

  defp build_upcoming_item(release) do
    %EpisodeListItem.Upcoming{
      season_number: release.season_number,
      episode_number: release.episode_number,
      title: release.title,
      air_date: release.air_date,
      sub_status: upcoming_sub_status(release)
    }
  end

  defp upcoming_sub_status(%{released: false}), do: :unaired
  defp upcoming_sub_status(%{released: true, in_library: false}), do: :aired_not_in_library
  # The DB filter already excludes in_library: true, so this clause is
  # unreachable in practice — but keeping it explicit makes the
  # mapping total at the type level.
  defp upcoming_sub_status(_), do: :aired_not_in_library

  # --- Helpers (extracted from DetailPanel) ---

  defp episode_state(nil), do: :unwatched

  defp episode_state(progress) do
    cond do
      progress.completed -> :watched
      (progress.position_seconds || 0.0) > 0.0 -> :current
      true -> :unwatched
    end
  end

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
      {MediaCentarr.Library.EpisodeList.progress_container_id(record), record}
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

  defp lookup_tracking_status(%{external_ids: external_ids, type: :tv_series})
       when is_list(external_ids) do
    case Enum.find(external_ids, &match?(%{source: "tmdb"}, &1)) do
      %{external_id: tmdb_id_str} ->
        case Integer.parse(tmdb_id_str) do
          {tmdb_id, ""} -> ReleaseTracking.tracking_status({tmdb_id, :tv_series})
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp lookup_tracking_status(_), do: nil
end
