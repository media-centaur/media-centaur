defmodule MediaCentaur.ReleaseTracking.Differ do
  @moduledoc """
  Pure functions that compare stored releases against freshly extracted releases
  and produce change events.

  The comparison is split into two layers:

    * **Structural diff** (`diff/3`) — type-agnostic set math over release keys:
      which keys were added, removed, or had their air date change. It never
      reasons about "seasons" and never treats a `nil` field as a sentinel.
    * **Event presentation** (the `detect_*` helpers) — turns the structural
      diff into human-facing events. Additions are the only type-sensitive
      step, so `detect_additions/4` dispatches on `media_type`: a TV series
      groups additions into season / episode announcements, while a movie has
      no "season" to announce.

  `media_type` defaults to `:tv_series` so the structural-diff tests can call
  `diff/2`; the production caller (`Refresher.commit_refresh/3`) always passes
  the tracked item's `media_type` explicitly.
  """

  @doc """
  Compares old stored releases (Ecto structs) against new extracted releases (maps).
  Returns a list of event maps with `:event_type`, `:description`, and `:metadata`.
  """
  def diff(old_releases, new_releases, media_type \\ :tv_series) do
    old_by_key = index_by_key(old_releases)
    new_by_key = index_by_key(new_releases)

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    date_changes = detect_date_changes(common_keys, old_by_key, new_by_key)
    additions = detect_additions(media_type, added_keys, new_by_key, old_by_key)
    removals = detect_removals(removed_keys, old_by_key)

    date_changes ++ additions ++ removals
  end

  defp index_by_key(releases) do
    Map.new(releases, fn release ->
      # Include title in key to distinguish multiple movie releases (both nil/nil)
      key = {
        field(release, :season_number),
        field(release, :episode_number),
        field(release, :title)
      }

      {key, release}
    end)
  end

  defp field(%{} = map, key), do: Map.get(map, key)

  defp detect_date_changes(keys, old_by_key, new_by_key) do
    Enum.flat_map(keys, fn key ->
      old = old_by_key[key]
      new = new_by_key[key]
      old_date = field(old, :air_date)
      new_date = field(new, :air_date)

      if old_date == new_date do
        []
      else
        [
          %{
            event_type: :upcoming_release_date_changed,
            description: format_date_change(key, old_date, new_date),
            metadata: %{
              old_date: old_date,
              new_date: new_date,
              season_number: elem(key, 0),
              episode_number: elem(key, 1),
              title: elem(key, 2)
            }
          }
        ]
      end
    end)
  end

  # A movie has no seasons or episodes; its schedule is a set of dated
  # releases. An added movie release is just a date the user already learns
  # from `:began_tracking` (initial) or `:upcoming_release_date_changed`
  # (subsequent moves), so the addition path mints no event rather than a
  # phantom "new season."
  defp detect_additions(:movie, _keys, _new_by_key, _old_by_key), do: []

  defp detect_additions(:tv_series, keys, _new_by_key, old_by_key) do
    new_seasons =
      keys
      |> Enum.map(fn {season, _episode, _title} -> season end)
      |> Enum.uniq()
      |> Enum.reject(fn season ->
        Enum.any?(Map.keys(old_by_key), fn {old_season, _e, _t} -> old_season == season end)
      end)

    season_events =
      Enum.map(new_seasons, fn season ->
        count = Enum.count(keys, fn {key_season, _e, _t} -> key_season == season end)

        %{
          event_type: :new_season_announced,
          description: "Season #{season} announced (#{count} episode#{if count > 1, do: "s", else: ""})",
          metadata: %{season_number: season, episode_count: count}
        }
      end)

    episode_keys =
      MapSet.reject(keys, fn {season, _e, _t} -> season in new_seasons end)

    episode_events =
      if MapSet.size(episode_keys) > 0 do
        count = MapSet.size(episode_keys)

        [
          %{
            event_type: :new_episodes_announced,
            description: "#{count} new episode#{if count > 1, do: "s", else: ""} announced",
            metadata: %{count: count}
          }
        ]
      else
        []
      end

    season_events ++ episode_events
  end

  defp detect_removals(keys, old_by_key) do
    Enum.map(keys, fn key ->
      old = old_by_key[key]

      label =
        if elem(key, 0) do
          "S#{elem(key, 0)}E#{elem(key, 1)}"
        else
          field(old, :title) || "Unknown"
        end

      %{
        event_type: :removed_from_schedule,
        description: "#{label} removed from schedule",
        metadata: %{
          old_date: field(old, :air_date),
          new_date: nil,
          season_number: elem(key, 0),
          episode_number: elem(key, 1),
          title: elem(key, 2)
        }
      }
    end)
  end

  defp format_date_change(key, old_date, new_date) do
    label =
      if elem(key, 0) do
        "S#{elem(key, 0)}E#{elem(key, 1)}"
      else
        elem(key, 2) || "Unknown"
      end

    old_str = if old_date, do: Date.to_iso8601(old_date), else: "unannounced"
    new_str = if new_date, do: Date.to_iso8601(new_date), else: "unannounced"
    "#{label} moved from #{old_str} to #{new_str}"
  end
end
