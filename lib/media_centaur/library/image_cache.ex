defmodule MediaCentaur.Library.ImageCache do
  @moduledoc """
  Where the library's artwork files live on disk.

  Every media directory has an image cache — `{media_dir}/.media-centaur/images`
  unless the directory's `media_dirs` entry sets `images_dir` — holding one
  `{owner_id}/{role}.{extension}` file per `Library.Image` row plus a
  `partial-downloads` staging area for in-flight fetches. This module owns
  that layout and the lookup of a row's `content_url` back to a file;
  `Settings.Config` only stores the per-directory override.
  """

  alias MediaCentaur.Settings.Config

  @default_subdir ".media-centaur/images"
  @staging_subdir "partial-downloads"

  @doc "The image cache directory for a media directory — its configured override, else the default."
  @spec dir_for(String.t()) :: String.t()
  def dir_for(media_dir) do
    Map.get(Config.get(:media_dir_images) || %{}, media_dir) || default_dir_for(media_dir)
  end

  @doc "Where a media directory's image cache lives when no `images_dir` override is set."
  @spec default_dir_for(String.t()) :: String.t()
  def default_dir_for(media_dir), do: Path.join(media_dir, @default_subdir)

  @doc "The staging directory for in-progress image downloads under a media directory's cache."
  @spec staging_dir_for(String.t()) :: String.t()
  def staging_dir_for(media_dir), do: Path.join(dir_for(media_dir), @staging_subdir)

  @doc """
  `{media_dir, image_dir}` pairs whose image cache is **not** inside its
  media directory — a cache on another drive is not covered by the media
  directory's watcher and needs its own availability monitor.
  """
  @spec dirs_outside_media_dir() :: [{String.t(), String.t()}]
  def dirs_outside_media_dir do
    Enum.flat_map(Config.get(:media_dirs) || [], fn media_dir ->
      image_dir = dir_for(media_dir)

      if String.starts_with?(image_dir, media_dir <> "/") do
        []
      else
        [{media_dir, image_dir}]
      end
    end)
  end

  @doc """
  The absolute path of the file an `Image` row's `content_url` names,
  searching every media directory's cache; `nil` when no file exists
  (or for a `nil` url).
  """
  @spec resolve_path(String.t() | nil) :: String.t() | nil
  def resolve_path(nil), do: nil

  def resolve_path(content_url) do
    Enum.find_value(Config.get(:media_dirs) || [], fn media_dir ->
      candidate = Path.join(dir_for(media_dir), content_url)
      if File.regular?(candidate), do: candidate
    end)
  end
end
