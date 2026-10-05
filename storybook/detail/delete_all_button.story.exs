defmodule MediaCentaurWeb.Storybook.Detail.DeleteAllButton do
  @moduledoc """
  The title's primary delete — every file the library holds for it, as
  one click-twice gesture. Drawn on the Manage toolbar and in the finish
  prompt (plan 005); absent until the file list has loaded.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.WatchedFile

  def function, do: &MediaCentaurWeb.Components.Detail.DeleteAllButton.delete_all_button/1
  def render_source, do: :function

  defp file(id, name, size) do
    %{
      file: %WatchedFile{
        id: "ffffffff-ffff-ffff-ffff-ffffffffff0#{id}",
        file_path: "/media/movies/Sample Movie (1922)/#{name}",
        media_dir: "/media/movies"
      },
      size: size
    }
  end

  defp one_file, do: [file(1, "Sample.Movie.1922.1080p.WEB-DL.mkv", 2_254_857_830)]

  defp two_files, do: one_file() ++ [file(2, "Sample.Movie.1922.en.srt", 98_304)]

  def variations do
    [
      %Variation{
        id: :one_file,
        description: "A single file reads \"Delete this file\".",
        attributes: %{files: one_file(), files_status: :loaded}
      },
      %Variation{
        id: :many_files,
        description: "Several files read \"Delete all files\".",
        attributes: %{files: two_files()}
      },
      %Variation{
        id: :armed,
        description: "First press: armed, asking for the second.",
        attributes: %{files: one_file(), delete_confirm: :all}
      },
      %Variation{
        id: :deleting,
        description: "The delete is running.",
        attributes: %{files: one_file(), deleting: :all}
      },
      %Variation{
        id: :another_delete_running,
        description: "A file or folder delete is running elsewhere on the sheet: disabled.",
        attributes: %{
          files: two_files(),
          deleting: {:file, "/media/movies/Sample Movie (1922)/Sample.Movie.1922.en.srt"}
        }
      },
      %Variation{
        id: :loading,
        description: "Files still loading: nothing drawn.",
        attributes: %{files: [], files_status: :loading}
      },
      %Variation{
        id: :load_failed,
        description: "The file list failed to load: nothing drawn.",
        attributes: %{files: [], files_status: :failed}
      }
    ]
  end
end
