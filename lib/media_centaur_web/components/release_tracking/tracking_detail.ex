defmodule MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail do
  @moduledoc """
  The tracked-title half of a title's detail: its tracking mode, its
  release timeline, recent per-title activity, the per-title quality
  acceptance and when tracking began. `nil` for a title that has never
  been tracked.

  Loaded by `load/2` for any host that mounts the shared tracking
  components (`ReleaseTimeline`, `TrackingModeControl`) — the title
  detail modal now, the library detail panel from Phase 3 of the
  watchlist-and-release-tracking campaign (UIDR-035). The reads are
  local and cheap (ADR-051): the item, its releases, its recent events,
  and — only when acquisition is ready — which of those releases are
  under an active pursuit.
  """

  alias MediaCentaur.Acquisition
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Item, UpcomingFeed}
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  defstruct [
    :item_id,
    :mode,
    :tracking_since,
    lower_quality_accepted?: false,
    timeline: [],
    activity: []
  ]

  @type activity_entry :: %{text: String.t(), at: String.t()}

  @type t :: %__MODULE__{
          item_id: Ecto.UUID.t(),
          mode: Item.tracking_mode(),
          tracking_since: DateTime.t() | nil,
          lower_quality_accepted?: boolean(),
          timeline: [Event.t()],
          activity: [activity_entry()]
        }

  @typedoc """
  The impure facts the timeline classification needs, resolved by the
  host: `today`, `acquisition_ready?` (`Capabilities.acquisition_ready?/0`)
  and `auto_grab_default_mode` (`AutoGrabSettings.load/0`).
  """
  @type context :: %{
          today: Date.t(),
          acquisition_ready?: boolean(),
          auto_grab_default_mode: String.t()
        }

  @recent_activity 8

  @doc "The tracking detail for a title ref, or nil when it is not tracked."
  @spec load({integer(), Item.media_type()}, context()) :: t() | nil
  def load({tmdb_id, media_type}, context) do
    case ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type) do
      nil -> nil
      %Item{} = item -> build(item, context)
    end
  end

  defp build(%Item{} = item, context) do
    releases = item.id |> ReleaseTracking.list_releases_for_item() |> Enum.map(&%{&1 | item: item})

    feed =
      UpcomingFeed.build(releases, %{
        today: context.today,
        acquisition_ready?: context.acquisition_ready?,
        auto_grab_default_mode: context.auto_grab_default_mode,
        grab_status_by_key: grab_status_by_key(releases, context.acquisition_ready?)
      })

    %__MODULE__{
      item_id: item.id,
      mode: item.tracking_mode,
      tracking_since: item.inserted_at,
      lower_quality_accepted?: Item.lower_quality_accepted?(item),
      timeline: flatten(feed),
      activity: activity(item.id)
    }
  end

  # Nearness-first: bucket order, date-ascending within, undated last.
  defp flatten(%UpcomingFeed{buckets: buckets, unscheduled: unscheduled}) do
    Enum.flat_map(UpcomingFeed.bucket_order(), &Map.get(buckets, &1, [])) ++ unscheduled
  end

  defp activity(item_id) do
    item_id
    |> ReleaseTracking.list_events_for_item(@recent_activity)
    |> Enum.map(&%{text: &1.description, at: MediaCentaur.Format.relative_ago(&1.inserted_at)})
  end

  # `statuses_for_releases/1` also returns cancelled and complete pursuits;
  # only an ACTIVE one means the release is being grabbed right now.
  defp grab_status_by_key(_releases, false), do: %{}

  defp grab_status_by_key(releases, true) do
    releases
    |> Enum.map(&UpcomingFeed.release_key/1)
    |> Enum.uniq()
    |> Acquisition.statuses_for_releases()
    |> Enum.filter(fn {_key, {pursuit, _target}} -> pursuit.state == "active" end)
    |> Map.new(fn {key, {pursuit, _target}} -> {key, %{pursuit_id: pursuit.id}} end)
  end
end
