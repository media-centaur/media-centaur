defmodule MediaCentaurWeb.Storybook.Detail.MoreInfo.FileDetails do
  @moduledoc "Probed file facts in the More-info pane — the container's own title next to the matched metadata, plus duration/codec/audio."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Views.DetailItem

  def function, do: &MediaCentaurWeb.Components.Detail.MoreInfo.FileDetails.file_details/1
  def render_source, do: :function

  defp file(media_info) do
    %DetailItem.WatchedFile{
      path: "/media/Sample.Movie.2024.2160p.WEB-DL.mkv",
      media_dir: "/media",
      media_info: media_info
    }
  end

  def template do
    """
    <div class="max-w-xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :full,
        description: "Everything probed — title tag, duration, video, audio",
        attributes: %{
          files: [
            file(%{
              container_title: "Sample.Movie.2024.2160p.WEB-DL.DDP5.1-GRP",
              duration_seconds: 6073,
              video_codec: "HEVC",
              width: 3840,
              height: 2160,
              audio_summary: "TrueHD 7.1 · AC3 5.1"
            })
          ]
        }
      },
      %Variation{
        id: :mismatched_title,
        description:
          "The reason this section exists: the container was authored as a different movie than the filename claims (a renamed fake release)",
        attributes: %{
          files: [
            file(%{
              container_title: "Some.Other.Movie.1997.2160p.BluRay-GRP",
              duration_seconds: 6073,
              video_codec: "HEVC",
              width: 3840,
              height: 2160,
              audio_summary: "DTS 5.1 ×2"
            })
          ]
        }
      },
      %Variation{
        id: :no_title_tag,
        description: "No container title (common for WEB-DLs) — only the tech line renders",
        attributes: %{
          files: [
            file(%{
              container_title: nil,
              duration_seconds: 5432,
              video_codec: "H.264",
              width: 1920,
              height: 1080,
              audio_summary: "DDP 5.1"
            })
          ]
        }
      },
      %Variation{
        id: :unprobed,
        description: "File never probed (no ffprobe / pre-feature import) — renders nothing",
        attributes: %{files: [file(nil)]}
      },
      %Variation{
        id: :no_files,
        description: "Series-level entries have no backing files — renders nothing",
        attributes: %{files: []}
      }
    ]
  end
end
