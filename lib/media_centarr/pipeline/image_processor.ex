defmodule MediaCentarr.Pipeline.ImageProcessor do
  @moduledoc """
  Thin wrapper around `MediaCentarr.Images` for the pipeline's image roles.

  Maps role names to resize dimensions and output formats, then delegates
  to the shared image service. No GenServer, no state.

  ## Target dimensions

  Derived from 4K render sizes + 25% headroom (see IMAGE-SIZING spec):

  | Role     | Strategy     | Target       |
  |----------|-------------|--------------|
  | poster   | fit         | 1120 × 1680 |
  | backdrop | fit         | 3360 × 1890 |
  | logo     | longest_edge| 1440         |
  | thumb    | fit         | 480 × 270   |

  Logos are saved as PNG (preserving transparency). All others as JPEG.
  Images at or below target size are written as-is — never upscaled.
  """

  alias MediaCentarr.Images

  @role_config %{
    "poster" => [resize: {:fit, 1120, 1680}, format: :jpg],
    "backdrop" => [resize: {:fit, 3360, 1890}, format: :jpg],
    "logo" => [resize: {:longest_edge, 1440}, format: :png],
    "thumb" => [resize: {:fit, 480, 270}, format: :jpg]
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
    opts = Map.fetch!(@role_config, role)

    case Images.download(url, dest_path, opts) do
      {:ok, _path} -> :ok
      {:error, category, reason} -> {:error, category, reason}
    end
  end

  @doc """
  Returns the output file extension for the given role.

  Logos use PNG (transparency). All others use JPEG.
  """
  @spec output_extension(String.t()) :: String.t()
  def output_extension("logo"), do: "png"
  def output_extension(_role), do: "jpg"
end
