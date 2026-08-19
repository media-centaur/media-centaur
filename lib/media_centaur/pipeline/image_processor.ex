defmodule MediaCentaur.Pipeline.ImageProcessor do
  @moduledoc """
  Thin wrapper around `MediaCentaur.ImageFiles` for the pipeline's image roles.

  Maps role names to resize dimensions and output formats, then delegates
  to the shared image service. No GenServer, no state.

  ## Target dimensions

  | Role     | Strategy     | Target                          |
  |----------|-------------|----------------------------------|
  | poster   | fit         | 1120 × 1680                     |
  | backdrop | fit         | 3840 × 2160 (4K) / 1920 × 1080 (1080p) |
  | logo     | longest_edge| 1440                            |
  | thumb    | fit         | 480 × 270                       |

  Backdrops are the only artwork shown full-bleed, so their master resolution
  follows the user's `:image_resolution` preference (Settings → Pipeline): 4K
  renders sharply on UHD displays, 1080p halves the dimensions (≈4× smaller
  files) for standard displays / smaller disks. Every other role is sized for
  how it's displayed and right-sized further on demand by `ImageServer` (`?w=`).

  Logos are saved as PNG (preserving transparency). All others as JPEG.
  Images at or below target size are written as-is — never upscaled.
  """

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.ImageFiles

  @role_config %{
    "poster" => [resize: {:fit, 1120, 1680}, format: :jpg],
    "logo" => [resize: {:longest_edge, 1440}, format: :png],
    "thumb" => [resize: {:fit, 480, 270}, format: :jpg]
  }

  @backdrop_config %{
    "4k" => [resize: {:fit, 3840, 2160}, format: :jpg],
    "1080p" => [resize: {:fit, 1920, 1080}, format: :jpg]
  }

  @doc """
  Downloads an image from `url`, resizes it to the spec for `role`,
  and writes it to `dest_path`.

  Returns `:ok` on success or `{:error, category, reason}` on failure,
  where `category` is `:permanent` (will never succeed) or `:transient`
  (might work later).
  """
  @spec download_and_resize(String.t(), String.t(), String.t()) ::
          :ok | {:error, :permanent | :transient, term()}
  def download_and_resize(url, role, dest_path) do
    case ImageFiles.download(url, dest_path, role_opts(role)) do
      {:ok, _path} -> :ok
      {:error, category, reason} -> {:error, category, reason}
    end
  end

  # Backdrop spec follows the runtime resolution preset; every other role is
  # fixed.
  defp role_opts("backdrop"), do: Map.fetch!(@backdrop_config, Config.image_resolution())
  defp role_opts(role), do: Map.fetch!(@role_config, role)

  @doc """
  Returns the output file extension for the given role.

  Logos use PNG (transparency). All others use JPEG.
  """
  @spec output_extension(String.t()) :: String.t()
  def output_extension("logo"), do: "png"
  def output_extension(_role), do: "jpg"
end
