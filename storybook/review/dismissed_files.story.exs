defmodule MediaCentaurWeb.Storybook.Review.DismissedFiles do
  @moduledoc """
  Story for a review queue's dismissed files — the disclosure both review
  surfaces render under their list, each file with Restore.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.DismissedFiles.dismissed_files/1
  def render_source, do: :function

  # Both pages render it in a list pane about 300px wide.
  def template, do: ~s|<div class="w-[300px]"><.psb-variation/></div>|

  defp files do
    [
      %{id: "a", path: "Sample Show (2001)/Season 1/Sample.Show.S01E01.1080p.WEB-DL.mkv"},
      %{id: "b", path: "Movie A (2010)/Movie.A.2010.1080p.BluRay.x264-GRP.mkv"},
      %{
        id: "c",
        path:
          "Very Long Release Folder Name.2019.2160p.UHD.BluRay.REMUX.HDR.HEVC/Featurettes/Making Of.mkv"
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed: the head and its count",
        attributes: %{id: "dismissed-closed", open: false, files: files(), hint: hint()}
      },
      %Variation{
        id: :open,
        description: "Open: each file with Restore; a long path truncates from the start",
        attributes: %{id: "dismissed-open", open: true, files: files(), hint: hint()}
      },
      %Variation{
        id: :none,
        description: "No dismissed files: renders nothing",
        attributes: %{id: "dismissed-none", open: false, files: [], hint: hint()}
      }
    ]
  end

  defp hint, do: "Dismissed files are skipped on every scan. Restore one to review it again."
end
