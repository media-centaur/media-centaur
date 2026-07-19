defmodule MediaCentaurWeb.Storybook.Status.WatcherWidget do
  @moduledoc "Storybook coverage for the Watcher Activity widget (media dirs + storage headroom + activity narrative)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Watcher.watcher_widget/1

  # A watcher_statuses entry in the enriched Supervisor.statuses/0 shape.
  defp watcher(dir, state, opts \\ []) do
    %{
      dir: dir,
      state: state,
      reason: Keyword.get(opts, :reason),
      settling_count: Keyword.get(opts, :settling_count, 0),
      pending_deletions: Keyword.get(opts, :pending_deletions, 0)
    }
  end

  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  def variations do
    [
      %Variation{
        id: :empty,
        attributes: %{
          dir_health: [],
          watcher_statuses: [],
          scan_stats: %{},
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      },
      %Variation{
        id: :populated,
        attributes: %{
          dir_health: [
            %{dir: "/media/shows", dir_exists: true, image_dir_exists: true},
            %{dir: "/media/movies", dir_exists: false, image_dir_exists: false}
          ],
          watcher_statuses: [],
          scan_stats: %{},
          storage_drives: [
            %{
              used_bytes: 750_000_000_000,
              total_bytes: 1_000_000_000_000,
              usage_percent: 75,
              roles: [%{label: "Media", path: "/media/shows"}]
            }
          ],
          at_risk_summary: %{},
          ttl_days: 30
        }
      },
      %Variation{
        id: :last_scan,
        attributes: %{
          dir_health: [%{dir: "/media/movies", dir_exists: true, image_dir_exists: true}],
          watcher_statuses: [watcher("/media/movies", :watching)],
          scan_stats: %{
            "/media/movies" => %{at: seconds_ago(120), total: 1_432, new: 3, relinked: 1}
          },
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      },
      %Variation{
        id: :settling,
        attributes: %{
          dir_health: [%{dir: "/media/movies", dir_exists: true, image_dir_exists: true}],
          watcher_statuses: [watcher("/media/movies", :watching, settling_count: 2)],
          scan_stats: %{
            "/media/movies" => %{at: seconds_ago(45), total: 1_432, new: 0, relinked: 0}
          },
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      },
      %Variation{
        id: :unavailable_unmounted,
        attributes: %{
          dir_health: [%{dir: "/media/archive", dir_exists: true, image_dir_exists: true}],
          watcher_statuses: [watcher("/media/archive", :unavailable, reason: :unmounted)],
          scan_stats: %{},
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      }
    ]
  end
end
