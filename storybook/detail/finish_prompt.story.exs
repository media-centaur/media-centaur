defmodule MediaCentaurWeb.Storybook.Detail.FinishPrompt do
  @moduledoc """
  The row the title detail shows after a title was finished in mpv
  (plans 005 and 006, UIDR-052). Finished: Review, the delete, Done.
  Caught up on a show still airing: Review, Track release dates, Done.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.WatchedFile

  def function, do: &MediaCentaurWeb.Components.Detail.FinishPrompt.finish_prompt/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-[760px]">
      <.psb-variation/>
    </div>
    """
  end

  @files [
    %{
      file: %WatchedFile{
        id: "ffffffff-ffff-ffff-ffff-ffffffffff01",
        file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.WEB-DL.mkv",
        media_dir: "/media/movies"
      },
      size: 2_254_857_830
    }
  ]

  def variations do
    [
      %Variation{
        id: :reviewable,
        description: "A movie with a TMDB identity and the friend network on.",
        attributes: %{name: "Sample Movie", review?: true, files: @files, files_status: :loaded}
      },
      %Variation{
        id: :not_reviewable,
        description: "No TMDB identity, or the friend network off: Delete and Done only.",
        attributes: %{name: "Sample Movie", review?: false, files: @files}
      },
      %Variation{
        id: :delete_armed,
        description: "Delete pressed once.",
        attributes: %{name: "Sample Movie", review?: true, files: @files, delete_confirm: :all}
      },
      %Variation{
        id: :deleting,
        description: "The delete is running.",
        attributes: %{name: "Sample Movie", review?: true, files: @files, deleting: :all}
      },
      %Variation{
        id: :files_loading,
        description: "The file list has not loaded yet: no Delete.",
        attributes: %{name: "Sample Movie", review?: true, files: [], files_status: :loading}
      },
      %Variation{
        id: :collection_movie,
        description: "A movie in a collection: the delete covers that movie's files only.",
        attributes: %{
          name: "Movie A",
          review?: true,
          files: @files,
          delete_target: {:member, "movie-1"}
        }
      },
      %Variation{
        id: :series_finished,
        description: "The finale of an ended show: Review, Delete all files, Done.",
        attributes: %{name: "Sample Show", kind: :finished, review?: true, files: @files}
      },
      %Variation{
        id: :caught_up,
        description:
          "The latest episode of a show still airing, not on the list: Track release dates off.",
        attributes: %{
          name: "Sample Show",
          kind: :caught_up,
          review?: true,
          files: @files,
          ref: "tv_series-1399",
          rung: nil
        }
      },
      %Variation{
        id: :caught_up_tracking,
        description: "Caught up on a show already tracked: the switch is on.",
        attributes: %{
          name: "Sample Show",
          kind: :caught_up,
          review?: true,
          files: @files,
          ref: "tv_series-1399",
          rung: :follow
        }
      },
      %Variation{
        id: :files_failed,
        description: "The file list failed to load: Review and Done only.",
        attributes: %{name: "Sample Movie", review?: true, files: [], files_status: :failed}
      }
    ]
  end
end
