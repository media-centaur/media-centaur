defmodule MediaCentarrWeb.Storybook.LibraryCards.StorageOfflineBanner do
  @moduledoc """
  Persistent top-of-page banner shown on the Library page when one or
  more configured watch directories are offline.

  ## Contract shape

      attr :summary, :string, required: true

  Pre-formatted by `MediaCentarrWeb.LibraryAvailability.offline_summary/2`,
  so the banner is purely presentational. Fixtures below match the two
  shapes that helper produces (single-dir vs multi-dir) plus a long
  path edge case.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.LibraryCards.storage_offline_banner/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :single_dir,
        description: "One watch directory offline — single-item phrasing.",
        attributes: %{
          summary: "/mnt/media/movies is offline — 1 item temporarily unavailable."
        }
      },
      %Variation{
        id: :single_dir_many_items,
        description: "One directory offline, many items affected.",
        attributes: %{
          summary: "/mnt/media/tv is offline — 247 items temporarily unavailable."
        }
      },
      %Variation{
        id: :multiple_dirs,
        description: "Multiple directories offline — count phrasing.",
        attributes: %{
          summary: "3 storage locations offline — 412 items temporarily unavailable."
        }
      },
      %Variation{
        id: :long_path,
        description:
          "Stress test — long path should wrap inside the banner without breaking the layout.",
        attributes: %{
          summary:
            "/mnt/very/long/storage/path/that/definitely/wraps/onto/multiple/lines/movies " <>
              "is offline — 12 items temporarily unavailable."
        }
      }
    ]
  end
end
