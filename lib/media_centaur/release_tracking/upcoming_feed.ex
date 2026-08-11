defmodule MediaCentaur.ReleaseTracking.UpcomingFeed do
  @moduledoc """
  The release-forecast view-model behind the Incoming page's Coming up shelf
  and per-title detail timeline.

  A pure transform from `ReleaseTracking.Release` structs (with `:item`
  preloaded) into a date-ordered forecast of release **events**, bucketed by
  relative time and tagged with a per-event status. The Iron Law applies — this
  is data and functions, no process — and it stays pure by taking every impure
  fact as injected `context`:

    * `:today` — `Date` to measure relative time against.
    * `:acquisition_ready?` — can a grab actually fire (indexer + download
      client; `Capabilities.acquisition_ready?/0`)? Gates the `:armed` status.
    * `:auto_grab_default_mode` — the global auto-grab default
      (`AutoGrabSettings.load/0` → `default_mode`) that an item's `"global"`
      mode inherits.
    * `:grab_status_by_key` — `%{release_key => %{pursuit_id: uuid}}` for
      releases currently under an active pursuit (built by the caller from
      `Acquisition.statuses_for_releases/1`). Presence ⇒ `:under_pursuit`.

  The LiveView does the reads and passes plain values in; keeping the
  classification here makes it unit-testable without a DB, a network, or a
  render (ADR-030).

  ## Status

  Per event, in precedence order:

    * `:in_library` — already landed (the closure beat).
    * `:theatrical_info` — a movie's theatrical date; informational, never
      auto-grabbed.
    * `:unscheduled` — tracked but no air date yet (lives in `unscheduled`, not
      a time bucket).
    * `:under_pursuit` — released and being acquired now; carries `pursuit_id`
      so the UI can deep-link to Downloads.
    * `:armed` — a future release that **will** auto-grab when it drops (only
      when acquisition is ready AND the effective auto-grab mode is
      `"all_releases"`). Honest: never shown when a grab won't actually fire.
    * `:armed_fallback` — a movie's later acquirable date (its physical
      release after the digital one). The want ledger opens a single want per
      film, anchored on the earliest acquirable date, so only that date's
      release actually fires a grab; a later date matters only if the film is
      still missing when it arrives. Shown neutral so the page never promises
      two grabs for one film.
    * `:upcoming` — tracked and dated, but not auto-grabbing (neutral).
  """

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Straggler

  @bucket_order [:today, :this_week, :next_week, :later, :beyond]

  @empty_buckets Map.new(@bucket_order, &{&1, []})

  defstruct buckets: @empty_buckets, unscheduled: []

  @type t :: %UpcomingFeed{buckets: %{atom() => [Event.t()]}, unscheduled: [Event.t()]}

  defmodule Event do
    @moduledoc "One release event in the forecast."
    defstruct [
      :id,
      :item_id,
      :item_name,
      :media_type,
      :title,
      :air_date,
      :season_number,
      :episode_number,
      :release_type,
      :status,
      :pursuit_id,
      :kind,
      :episode_count,
      :backdrop_url,
      :logo_url
    ]

    @type t :: %Event{}
  end

  defmodule Straggler do
    @moduledoc """
    A tracked title with no dated release yet. Carries enough identity
    (name, media type, backdrop) for the shelf to render it as a
    first-class agenda row (UIDR-017).
    """
    defstruct [:item_id, :name, :media_type, :backdrop_url]

    @type t :: %Straggler{}
  end

  @doc "The fixed relative-time bucket order (soonest first)."
  @spec bucket_order() :: [atom()]
  def bucket_order, do: @bucket_order

  @doc """
  The acquisition lookup key for a release — `{tmdb_id, tmdb_type, season,
  episode}`. The single source of truth for keying `grab_status_by_key`; both
  this module and the LiveView use it so the keys agree.
  """
  @spec release_key(Release.t()) :: {String.t(), String.t(), integer() | nil, integer() | nil}
  def release_key(%Release{item: item} = release) do
    {to_string(item.tmdb_id), tmdb_type(item.media_type), release.season_number, release.episode_number}
  end

  defp tmdb_type(:movie), do: "movie"
  defp tmdb_type(:tv_series), do: "tv"

  @doc """
  Build the feed from releases (with `:item` preloaded) and an injected context.
  """
  @spec build([Release.t()], map()) :: t()
  def build(releases, context) do
    context = Map.put(context, :fallback_release_ids, fallback_release_ids(releases))

    events =
      releases
      |> collapse_season_drops()
      |> Enum.map(&to_event(&1, context))

    {unscheduled, scheduled} = Enum.split_with(events, &(&1.status == :unscheduled))

    bucketed =
      scheduled
      |> Enum.filter(&forecast_worthy?(&1, context.today))
      |> Enum.sort_by(& &1.air_date, Date)
      |> bucketize(context.today)

    %UpcomingFeed{buckets: bucketed, unscheduled: unscheduled}
  end

  @doc """
  The "Tracking — nothing scheduled yet" stragglers: watching items with no
  dated release (hiatus shows, movies with no announced date). Items must have
  `:releases` preloaded.
  """
  @spec stragglers([map()]) :: [Straggler.t()]
  def stragglers(watching_items) do
    watching_items
    |> Enum.filter(&no_dated_release?/1)
    |> Enum.map(fn item ->
      %Straggler{
        item_id: item.id,
        name: item.name,
        media_type: item.media_type,
        backdrop_url: MediaCentaur.TmdbArtwork.urls(item.media_type, item.tmdb_id).backdrop_url
      }
    end)
  end

  @doc """
  The Incoming shelf: scheduled events flattened nearness-first (bucket order,
  date-ascending within each bucket), **one card per title** — a title's later
  releases (a movie's physical date after its digital one, a weekly show's
  following episodes) collapse into its soonest event, since the title
  modal carries the full timeline. Capped at `cap`;
  `{items, overflow_count}` counts hidden TITLES so a capped shelf never
  silently truncates the forecast.
  """
  @spec shelf_items(t(), pos_integer() | :all) :: {[Event.t()], non_neg_integer()}
  def shelf_items(%UpcomingFeed{} = feed, :all) do
    {feed |> scheduled_events() |> Enum.uniq_by(& &1.item_id), 0}
  end

  def shelf_items(%UpcomingFeed{} = feed, cap) do
    titles = feed |> scheduled_events() |> Enum.uniq_by(& &1.item_id)
    {Enum.take(titles, cap), max(length(titles) - cap, 0)}
  end

  @doc """
  The shelf card's date badge, graduating in explicitness with distance: an
  arrived theatrical date → "Now"; today → "Tonight" (episodes) / "Today"
  (movies); under a week → "Tue"; under a month → "Wed Jun 24"; beyond →
  "Jul 24". A bare weekday is only unambiguous inside the coming week, hence
  the `< 7` cutoff.
  """
  @spec shelf_date_label(Event.t(), Date.t()) :: String.t()
  def shelf_date_label(%Event{air_date: date} = event, today) do
    diff = Date.diff(date, today)

    cond do
      event.status == :theatrical_info and diff <= 0 -> "Now"
      diff <= 0 and event.kind == :movie -> "Today"
      diff <= 0 -> "Tonight"
      diff < 7 -> weekday_abbr(date)
      diff <= 30 -> "#{weekday_abbr(date)} #{month_day(date)}"
      true -> month_day(date)
    end
  end

  defp weekday_abbr(date), do: Calendar.strftime(date, "%a")

  # Manual day interpolation — Calendar.strftime has no unpadded-day directive.
  defp month_day(date), do: "#{Calendar.strftime(date, "%b")} #{date.day}"

  # Same-(item, season, air_date) episodes are one drop, not N rail entries.
  # Movies and undated/episode-less TV rows pass through untouched.
  defp collapse_season_drops(releases) do
    {collapsible, rest} =
      Enum.split_with(releases, fn release ->
        release.item.media_type == :tv_series and not is_nil(release.season_number) and
          not is_nil(release.air_date)
      end)

    collapsed =
      collapsible
      |> Enum.group_by(&{&1.item_id, &1.season_number, &1.air_date})
      |> Enum.flat_map(fn
        {_key, [single]} -> [single]
        {_key, [first | _] = group} -> [{:season_drop, first, group}]
      end)

    rest ++ collapsed
  end

  defp to_event({:season_drop, representative, group}, context) do
    %{
      event_from(representative, context)
      | kind: :season_drop,
        episode_number: nil,
        episode_count: length(group)
    }
  end

  defp to_event(%Release{} = release, context) do
    %{event_from(release, context) | kind: kind_for(release), episode_count: 1}
  end

  defp event_from(%Release{item: item} = release, context) do
    status = derive_status(release, context)
    artwork = MediaCentaur.TmdbArtwork.urls(item.media_type, item.tmdb_id)

    %Event{
      id: release.id,
      item_id: release.item_id,
      item_name: item.name,
      media_type: item.media_type,
      title: release.title,
      air_date: release.air_date,
      season_number: release.season_number,
      episode_number: release.episode_number,
      release_type: release.release_type,
      status: status,
      pursuit_id: pursuit_id_for(release, context, status),
      backdrop_url: artwork.backdrop_url,
      logo_url: artwork.logo_url
    }
  end

  defp kind_for(%Release{item: %{media_type: :movie}}), do: :movie
  defp kind_for(%Release{}), do: :episode

  defp derive_status(%Release{} = release, context) do
    cond do
      release.in_library -> :in_library
      release.release_type == "theatrical" -> :theatrical_info
      is_nil(release.air_date) -> :unscheduled
      Map.has_key?(context.grab_status_by_key, release_key(release)) -> :under_pursuit
      will_auto_grab?(release.item, context) -> armed_status(release, context)
      true -> :upcoming
    end
  end

  defp armed_status(release, context) do
    if MapSet.member?(context.fallback_release_ids, release.id),
      do: :armed_fallback,
      else: :armed
  end

  # One grab per film: the want ledger opens a single want per movie, anchored
  # on its earliest acquirable date (`Wants.want_candidates/2`), so only that
  # date's release actually fires the auto-grab. Every later acquirable date of
  # the same film is a fallback — it matters only if the film is still missing.
  # Same-day ties break on release type ("digital" sorts before "physical").
  defp fallback_release_ids(releases) do
    releases
    |> Enum.filter(fn release ->
      release.item.media_type == :movie and not is_nil(release.air_date) and
        not release.in_library and
        ReleaseTracking.acquirable_release_type?(release.release_type)
    end)
    |> Enum.group_by(&{&1.item_id, &1.part_tmdb_id || &1.item.tmdb_id})
    |> Enum.flat_map(fn {_film, film_releases} ->
      film_releases
      |> Enum.sort_by(&{Date.to_iso8601(&1.air_date), &1.release_type || ""})
      |> Enum.drop(1)
      |> Enum.map(& &1.id)
    end)
    |> MapSet.new()
  end

  defp pursuit_id_for(%Release{} = release, context, :under_pursuit) do
    case Map.get(context.grab_status_by_key, release_key(release)) do
      %{pursuit_id: pursuit_id} -> pursuit_id
      _ -> nil
    end
  end

  defp pursuit_id_for(_release, _context, _status), do: nil

  # Honest "armed": a grab only fires when acquisition is live AND the effective
  # auto-grab mode is the full-auto posture. Anything else reads as :upcoming.
  defp will_auto_grab?(item, context) do
    context.acquisition_ready? and
      effective_mode(item.auto_grab_mode, context.auto_grab_default_mode) == "all_releases"
  end

  defp effective_mode(mode, default) when mode in [nil, "global"], do: default
  defp effective_mode(mode, _default) when is_binary(mode), do: mode

  # A forecast is about the future. A *past* release earns a spot only as a
  # meaningful beat: it just landed (closure), it's actively being grabbed, or
  # it's armed to grab. Past theatrical dates (released, never enter the library,
  # never grabbed) would otherwise linger forever as "Today" — drop them; the
  # future digital date carries the title.
  defp forecast_worthy?(%Event{air_date: date, status: status}, today) do
    is_nil(date) or Date.compare(date, today) != :lt or
      status in [:in_library, :under_pursuit, :armed]
  end

  defp bucketize(events, today) do
    grouped = Enum.group_by(events, &bucket_for(&1.air_date, today))
    Map.new(@bucket_order, fn bucket -> {bucket, Map.get(grouped, bucket, [])} end)
  end

  defp bucket_for(date, today) do
    case Date.diff(date, today) do
      diff when diff <= 0 -> :today
      diff when diff <= 7 -> :this_week
      diff when diff <= 14 -> :next_week
      diff when diff <= 30 -> :later
      _ -> :beyond
    end
  end

  defp scheduled_events(%UpcomingFeed{buckets: buckets}) do
    Enum.flat_map(@bucket_order, &Map.get(buckets, &1, []))
  end

  defp no_dated_release?(%{releases: releases}) when is_list(releases) do
    Enum.all?(releases, &is_nil(&1.air_date))
  end

  defp no_dated_release?(_item), do: true
end
