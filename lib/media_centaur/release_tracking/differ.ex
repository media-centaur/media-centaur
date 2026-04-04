defmodule MediaCentaur.ReleaseTracking.Differ do
  @moduledoc """
  Pure functions that compare stored releases against freshly extracted releases
  and produce change events.
  """

  @doc """
  Compares old stored releases (Ecto structs) against new extracted releases (maps).
  Returns a list of event maps with `:event_type`, `:description`, and `:metadata`.
  """
  def diff(old_releases, new_releases) do
    old_by_key = index_by_key(old_releases)
    new_by_key = index_by_key(new_releases)

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    date_changes = detect_date_changes(common_keys, old_by_key, new_by_key)
    additions = detect_additions(added_keys, new_by_key, old_by_key)
    removals = detect_removals(removed_keys, old_by_key)

    date_changes ++ additions ++ removals
  end

  defp index_by_key(releases) do
    Map.new(releases, fn release ->
      # Include title in key to distinguish multiple movie releases (both nil/nil)
      key = {
        get_field(release, :season_number),
        get_field(release, :episode_number),
        get_field(release, :title)
      }

      {key, release}
    end)
  end

  defp get_field(%{} = map, field), do: Map.get(map, field)

  defp detect_date_changes(keys, old_by_key, new_by_key) do
    Enum.flat_map(keys, fn key ->
      old = old_by_key[key]
      new = new_by_key[key]
      old_date = get_field(old, :air_date)
      new_date = get_field(new, :air_date)

      if old_date != new_date do
        [
          %{
            event_type: :date_changed,
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
      else
        []
      end
    end)
  end

  defp detect_additions(keys, _new_by_key, old_by_key) do
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
          description:
            "Season #{season} announced (#{count} episode#{if count > 1, do: "s", else: ""})",
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
          get_field(old, :title) || "Unknown"
        end

      %{
        event_type: :date_changed,
        description: "#{label} removed from schedule",
        metadata: %{
          old_date: get_field(old, :air_date),
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
