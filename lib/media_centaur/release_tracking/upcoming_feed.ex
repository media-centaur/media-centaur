defmodule MediaCentaur.ReleaseTracking.UpcomingFeed do
  @moduledoc """
  The view-model for the time-first Upcoming page.

  A pure transform from `ReleaseTracking.Release` structs (with `:item`
  preloaded) into a date-ordered forecast of release **events**, bucketed by
  relative time and tagged with a per-event status. The Iron Law applies — this
  is data and functions, no process — and it stays pure by taking every impure
  fact as injected `context`:

    * `:today` — `Date` to measure relative time against.
    * `:acquisition_ready?` — is Prowlarr/acquisition usable
      (`Capabilities.prowlarr_ready?/0`)? Gates the `:armed` status.
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
    * `:upcoming` — tracked and dated, but not auto-grabbing (neutral).
  """

  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  @bucket_order [:today, :this_week, :next_week, :later, :beyond]

  @empty_buckets Map.new(@bucket_order, &{&1, []})

  defstruct buckets: @empty_buckets, unscheduled: []

  @type t :: %UpcomingFeed{buckets: %{atom() => [Event.t()]}, unscheduled: [Event.t()]}

  defmodule Event do
    @moduledoc "One release event on the Upcoming rail."
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
      :backdrop_path,
      :logo_path,
      hero?: false
    ]

    @type t :: %Event{}
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
    events =
      releases
      |> collapse_season_drops()
      |> Enum.map(&to_event(&1, context))

    {unscheduled, scheduled} = Enum.split_with(events, &(&1.status == :unscheduled))

    bucketed =
      scheduled
      |> Enum.sort_by(& &1.air_date, Date)
      |> flag_heroes()
      |> bucketize(context.today)

    %UpcomingFeed{buckets: bucketed, unscheduled: unscheduled}
  end

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
      backdrop_path: item.backdrop_path,
      logo_path: item.logo_path
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
      will_auto_grab?(release.item, context) -> :armed
      true -> :upcoming
    end
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

  defp flag_heroes(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {event, index} -> %{event | hero?: index < 2} end)
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
end
