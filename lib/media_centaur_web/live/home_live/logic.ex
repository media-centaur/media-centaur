defmodule MediaCentaurWeb.HomeLive.Logic do
  @moduledoc """
  Pure helpers for HomeLive — date math, row assembly, the hero pick
  (`select_hero/3`, over `MediaCentaurWeb.HeroRotation`).
  No DB, no PubSub. Tested with `async: true` per ADR-030.

  HomeLive composes data from Library, ReleaseTracking, and WatchHistory
  contexts; this module shapes that data into the item maps each row
  component expects (see `MediaCentaurWeb.Components.{ContinueWatchingRow,
  Marquee, PosterRow, HeroCard}`).
  """

  alias MediaCentaurWeb.Components.{ContinueWatchingRow, HeroCard, Marquee, PosterRow}
  alias MediaCentaurWeb.HeroRotation
  alias MediaCentaurWeb.LibraryFormatters

  @doc """
  Returns `{monday, sunday}` of the week containing `date`. Defaults to today.
  """
  @spec coming_up_window(Date.t()) :: {Date.t(), Date.t()}
  def coming_up_window(date \\ Date.utc_today()) do
    monday = Date.add(date, 1 - Date.day_of_week(date))
    sunday = Date.add(monday, 6)
    {monday, sunday}
  end

  @doc "Shape Library progress rows into ContinueWatchingRow items."
  @spec continue_watching_items([map()]) :: [ContinueWatchingRow.Item.t()]
  def continue_watching_items(progress_rows), do: shape_continue_watching(progress_rows)

  @doc """
  Same as `continue_watching_items/1`, but pins entities the user is
  currently playing (any non-stopped state in `playback`) to the front
  of the row, preserving the original Continue Watching order both
  among the pinned items and among the rest.

  `playback` is the page's playing set (`LiveHelpers.apply_playback_change/3`,
  its own player's viewings keyed by `entity_id`); the value's `:state` is
  what we read.
  """
  @spec continue_watching_items([map()], map()) :: [ContinueWatchingRow.Item.t()]
  def continue_watching_items(progress_rows, playback) when is_map(playback) do
    items = shape_continue_watching(progress_rows)
    {pinned, rest} = Enum.split_with(items, &active_session?(&1.entity_id, playback))
    pinned ++ rest
  end

  # `available?` and the artwork URLs arrive together from the projection
  # (`Views.ItemAvailability`): an offline row carries nil URLs, and the
  # card renders the offline treatment from the flag.
  defp shape_continue_watching(progress_rows) do
    Enum.map(progress_rows, fn row ->
      %ContinueWatchingRow.Item{
        id: row.entity_id,
        entity_id: row.entity_id,
        name: row.entity_name,
        progress_pct: row.progress_pct,
        backdrop_url: row.backdrop_url,
        logo_url: Map.get(row, :logo_url),
        available?: Map.get(row, :available?, true)
      }
    end)
  end

  defp active_session?(entity_id, playback) do
    case Map.get(playback, entity_id) do
      nil -> false
      %{state: :stopped} -> false
      _entry -> true
    end
  end

  @coming_up_cap 7

  @doc """
  Choose Coming Up's shows from the releases in its window: one pick per
  show, its earliest release and how many releases the show has in the
  window, soonest first, at most #{@coming_up_cap} — the rest wait behind
  the marquee's See all. Grouping happens over the whole window, so a show
  with many episodes never crowds out the shows after it.
  """
  @spec coming_up_picks([map()]) :: [%{release: map(), count: pos_integer()}]
  def coming_up_picks(releases) do
    releases
    |> Enum.group_by(& &1.item.id)
    |> Enum.map(fn {_item_id, show_releases} ->
      %{release: Enum.min_by(show_releases, & &1.air_date, Date), count: length(show_releases)}
    end)
    |> Enum.sort_by(& &1.release.item.name)
    |> Enum.sort_by(& &1.release.air_date, Date)
    |> Enum.take(@coming_up_cap)
  end

  @doc """
  Shape Coming Up's picks into marquee items, the lead tile first.

    * The lead's eyebrow carries the day and the episode ("Tonight ·
      S05E04"); its line is the rollup ("+ 6 more this season", "season
      premiere", or both).
    * A tile's eyebrow is the day alone; its line is "+ N more" or the
      episode label.
    * Day words are relative to `today`: "Tonight" / "Tomorrow" / weekday /
      "Mon DD". Movies say "Today" instead of "Tonight", and a theatrical
      date reads "In theaters · " — a bare day would promise a download for
      a date that is never grabbed. A movie's other dates never count as
      "+ N more".
  """
  @spec coming_up_items([%{release: map(), count: pos_integer()}], Date.t()) :: [
          Marquee.Item.t()
        ]
  def coming_up_items([], _today), do: []

  def coming_up_items([lead | tiles], today) do
    [
      build_marquee_item(lead, today, :lead)
      | Enum.map(tiles, &build_marquee_item(&1, today, :tile))
    ]
  end

  @doc "Shape Library entity rows into PosterRow items."
  @spec recently_added_items([map()]) :: [PosterRow.Item.t()]
  def recently_added_items(entities) do
    Enum.map(entities, fn entity ->
      %PosterRow.Item{
        id: entity.id,
        entity_id: entity.id,
        name: entity.name,
        year: format_year(entity.year),
        poster_url: entity.poster_url,
        available?: Map.get(entity, :available?, true)
      }
    end)
  end

  @hero_distinct_from 4

  @doc """
  The hero candidate to show: the rotation's pick
  (`MediaCentaurWeb.HeroRotation`), passing over any title among the first
  #{@hero_distinct_from} of Continue Watching — the row sits directly under
  the hero, and the same title twice in one view reads as a mistake. A
  passed-over pick yields to the next candidate in rotation order. When
  every candidate is passed over, the rotation's pick stands: a duplicate
  beats an empty hero.
  """
  @spec select_hero([map()], [ContinueWatchingRow.Item.t()], DateTime.t()) :: map() | nil
  def select_hero(candidates, continue_items, now \\ DateTime.utc_now()) do
    in_view = continue_items |> Enum.take(@hero_distinct_from) |> MapSet.new(& &1.entity_id)
    rotation = HeroRotation.rotate(candidates, now)

    Enum.find(rotation, List.first(rotation), &(not MapSet.member?(in_view, &1.id)))
  end

  @doc """
  Shape a single Library entity into the HeroCard item. Returns nil for
  nil input. A hero candidate is never offline (`Views.HeroCandidates`
  drops entries whose media directory is unreachable), so the item
  carries no availability.
  """
  @spec hero_card_item(map() | nil) :: HeroCard.Item.t() | nil
  def hero_card_item(nil), do: nil

  def hero_card_item(entity) do
    %HeroCard.Item{
      id: entity.id,
      entity_id: entity.id,
      name: entity.name,
      year: format_year(entity.year),
      runtime: format_runtime(entity.runtime_minutes),
      genre_label: format_genres(entity.genres),
      overview: entity.overview,
      backdrop_url: entity.backdrop_url,
      logo_url: Map.get(entity, :logo_url)
    }
  end

  # --- Private helpers ---

  defp build_marquee_item(%{release: release, count: count}, today, role) do
    kind = release_kind(release)
    # A movie's sibling releases are its other dates for the same film
    # (theatrical → digital → physical), not additional titles — never
    # advertise them as "+ N more".
    more_count = if kind == :episode, do: count - 1, else: 0
    episode_label = season_episode_label(release)
    day_part = day_part_for(release.air_date, today, kind)

    {eyebrow, line} =
      case role do
        :lead ->
          {[day_part, episode_label] |> Enum.reject(&is_nil/1) |> Enum.join(" · "),
           lead_line(release, more_count)}

        :tile ->
          {day_part, tile_line(more_count, episode_label)}
      end

    %Marquee.Item{
      entity_id: Map.get(release.item, :entity_id),
      ref: {Map.get(release.item, :tmdb_id), Map.get(release.item, :media_type)},
      name: release.item.name,
      eyebrow: eyebrow,
      badge: badge_for_status(release.status),
      backdrop_url: Map.get(release, :backdrop_url),
      logo_url: Map.get(release, :logo_url),
      line: line
    }
  end

  # An episode's date is when it airs and gets grabbed, so "Tonight" is
  # honest. A movie's dates are daytime availability windows ("Today"),
  # and a theatrical date is never grabbed at all — the eyebrow carries
  # the venue so "tonight" can't read as "expect the download tonight".
  defp release_kind(release) do
    cond do
      Map.get(release.item, :media_type) != :movie -> :episode
      Map.get(release, :release_type) == "theatrical" -> :theatrical
      true -> :movie
    end
  end

  defp day_part_for(nil, _today, _kind), do: nil

  defp day_part_for(%Date{} = date, today, :theatrical),
    do: "In theaters · " <> day_part_for(date, today, :movie)

  defp day_part_for(%Date{} = date, today, kind) do
    case Date.diff(date, today) do
      0 when kind == :episode -> "Tonight"
      0 -> "Today"
      1 -> "Tomorrow"
      n when n in 2..6 -> Calendar.strftime(date, "%a")
      _ -> Calendar.strftime(date, "%b %-d")
    end
  end

  defp lead_line(release, more_count) do
    premiere? = release.episode_number == 1

    cond do
      more_count > 0 and premiere? -> "+ #{more_count} more · season premiere"
      more_count > 0 -> "+ #{more_count} more this season"
      premiere? -> "season premiere"
      true -> nil
    end
  end

  defp tile_line(more_count, episode_label) do
    cond do
      more_count > 0 -> "+ #{more_count} more"
      episode_label -> episode_label
      true -> nil
    end
  end

  defp season_episode_label(%{season_number: season, episode_number: episode})
       when not is_nil(season) and not is_nil(episode) do
    "S#{String.pad_leading("#{season}", 2, "0")}E#{String.pad_leading("#{episode}", 2, "0")}"
  end

  defp season_episode_label(_), do: nil

  defp badge_for_status(:acquired), do: %{label: "Acquired", variant: :success}
  defp badge_for_status(:downloading), do: %{label: "Downloading", variant: :info}
  defp badge_for_status(:seeking), do: %{label: "Seeking", variant: :info}
  defp badge_for_status(:grabbing), do: %{label: "Grabbing", variant: :info}
  # Scheduled is the implicit baseline of every Coming Up tile — render no
  # badge for it. Reserve the badge for differentiating action states.
  defp badge_for_status(_), do: nil

  defp format_year(nil), do: nil
  defp format_year(year) when is_integer(year), do: Integer.to_string(year)
  defp format_year(year) when is_binary(year), do: year

  # Routes through the canonical `LibraryFormatters.format_human_duration/1`
  # (Library Schema v2 Phase 1 Task 3 consolidation). Hero candidates carry
  # `runtime_minutes` for historical reasons; convert at the call site so
  # the seconds-based formatter stays the single source of truth.
  defp format_runtime(nil), do: nil

  defp format_runtime(minutes) when is_integer(minutes) and minutes > 0,
    do: LibraryFormatters.format_human_duration(minutes * 60)

  defp format_runtime(_), do: nil

  defp format_genres(nil), do: nil
  defp format_genres([]), do: nil
  defp format_genres(genres) when is_list(genres), do: Enum.join(genres, " · ")
  defp format_genres(genres) when is_binary(genres), do: genres

  @doc """
  Map an inbound PubSub message to the home page sections that need reloading.
  Returns `[]` for messages the home page does not care about.

  Sections: `:hero`, `:continue_watching`, `:coming_up`, `:recently_added`.
  Hero is normally stable for the duration of a 7-hour rotation window;
  a drive mounting or unmounting reaches it, like every section, as the
  `:library_view_updated` its projection broadcasts after rebuilding.
  """
  @spec section_reloaders(term()) :: [atom()]
  # Source events that previously drove section reloads
  # (`:entities_changed`, `:watch_event_created`, `:entity_progress_updated`,
  # `:availability_changed`, `:releases_updated`, `:item_removed`)
  # now flow into the Library.Views and
  # ReleaseTracking.Views projections, which broadcast
  # `{:library_view_updated, view_id}` / `{:release_tracking_view_updated, view_id}`
  # after each ETS rebuild. The reloads happen via those broadcasts.
  def section_reloaders({:library_view_updated, :continue_watching}), do: [:continue_watching]
  def section_reloaders({:library_view_updated, :hero_candidates}), do: [:hero]
  def section_reloaders({:library_view_updated, :recently_added}), do: [:recently_added]
  def section_reloaders({:release_tracking_view_updated, :coming_up}), do: [:coming_up]

  # Playback-state changes don't alter the underlying continue-watching
  # data; they affect the in-LiveView pinning order (now-playing item
  # floats to the front via `Logic.continue_watching_items/2` reading the
  # page's playing set, `title_playback`). Continue to reload so the pinned order
  # re-applies.
  def section_reloaders({:playback_state_changed, _payload}), do: [:continue_watching]

  # `:availability_changed` deliberately does not appear here. Every
  # projection HomeLive reads from subscribes to `library:availability`
  # directly, re-resolves each row's `available?` and artwork, and
  # broadcasts `:library_view_updated` after refresh; the clauses above
  # drive the reloads. Home itself never hears the source event.

  def section_reloaders(_), do: []

  @doc """
  Why Home has nothing to show.

  Home used to assert one cause unconditionally ("no media directory has been
  scanned") and point at Settings, which is wrong the moment a directory *is*
  configured — the state every user is in the instant the setup tour finishes.
  The three reasons take different actions, so the page diagnoses before it
  renders.

    * `:no_media_dirs` — nothing to scan; the fix is in Settings.
    * `:importing` — files are in flight; the fix is to wait.
    * `:nothing_imported` — directories are set and idle but produced nothing;
      the fix is a scan.
  """
  @spec empty_reason(%{
          :media_dirs_configured? => boolean(),
          :pipeline_queue_depth => non_neg_integer()
        }) :: :no_media_dirs | :importing | :nothing_imported
  def empty_reason(%{media_dirs_configured?: false}), do: :no_media_dirs
  def empty_reason(%{pipeline_queue_depth: depth}) when depth > 0, do: :importing
  def empty_reason(_state), do: :nothing_imported
end
