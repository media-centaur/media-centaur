defmodule MediaCentaurWeb.Storybook.Title.RefreshFromTmdb do
  @moduledoc """
  The one control that asks TMDB about a title again (UIDR-044): on the
  Manage toolbar for an owned title, under the tracking switches for a
  tracked title the library does not own, and disabled while the check
  is in flight.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.RefreshFromTmdb.refresh_from_tmdb/1

  def variations do
    [
      %Variation{
        id: :toolbar,
        description: "On the Manage toolbar, beside Rematch and Refresh artwork.",
        attributes: %{id: "refresh-from-tmdb-toolbar", ref: "tv_series-1399", surface: :toolbar}
      },
      %Variation{
        id: :tracking,
        description: "Under the tracking switches of a tracked title the library does not own.",
        attributes: %{id: "refresh-from-tmdb-tracking", ref: "movie-1399", surface: :tracking}
      },
      %Variation{
        id: :checking,
        description: "The check is in flight: disabled, and says so.",
        attributes: %{
          id: "refresh-from-tmdb-checking",
          ref: "tv_series-1399",
          surface: :toolbar,
          checking?: true
        }
      }
    ]
  end
end
