defmodule MediaCentaurWeb.Storybook.Status.WatcherWidget do
  @moduledoc "Storybook coverage for the Watcher Activity widget (watch dirs + storage headroom)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.HealthComponents.watcher_widget/1

  def variations do
    [
      %Variation{
        id: :empty,
        attributes: %{
          dir_health: [],
          watcher_statuses: [],
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
      }
    ]
  end
end
