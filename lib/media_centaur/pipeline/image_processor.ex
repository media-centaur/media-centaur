defmodule MediaCentaur.Pipeline.ImageProcessor do
  @moduledoc """
  Pure-function module for downloading and resizing images to spec.

  Wraps `Image` (libvips via Vix) for download + resize. No GenServer,
  no state, no side effects beyond file I/O.

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
  require MediaCentaur.Log, as: Log

  @target_dimensions %{
    "poster" => {:fit, 1120, 1680},
    "backdrop" => {:fit, 3360, 1890},
    "logo" => {:longest_edge, 1440},
    "thumb" => {:fit, 480, 270}
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
    dest_path |> Path.dirname() |> File.mkdir_p!()

    with {:ok, body} <- download(url),
         {:ok, image} <- open_image(body),
         {:ok, resized} <- resize(image, role),
         :ok <- write_image(resized, role, dest_path) do
      :ok
    else
      {:error, reason} -> {:error, categorize(reason), reason}
    end
  end

  @permanent_statuses [400, 401, 403, 404, 405, 410, 451]

  defp categorize({:http_error, status, _url}) when status in @permanent_statuses, do: :permanent
  defp categorize({:http_error, _status, _url}), do: :transient
  defp categorize({:download_failed, _url, _reason}), do: :transient
  defp categorize({:image_open_failed, _reason}), do: :permanent
  defp categorize({:resize_failed, _reason}), do: :permanent
  defp categorize({:write_failed, _path, _reason}), do: :transient

  @doc """
  Returns the output file extension for the given role.

  Logos use PNG (transparency). All others use JPEG.
  """
  @spec output_extension(String.t()) :: String.t()
  def output_extension("logo"), do: "png"
  def output_extension(_role), do: "jpg"

  # ---------------------------------------------------------------------------
  # Download
  # ---------------------------------------------------------------------------

  defp download(url) do
    case http_client().get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status, url}}

      {:error, reason} ->
        {:error, {:download_failed, url, reason}}
    end
  end

  defp http_client, do: Application.get_env(:media_centaur, :image_http_client, Req)

  # ---------------------------------------------------------------------------
  # Image operations
  # ---------------------------------------------------------------------------

  defp open_image(binary) do
    case Image.from_binary(binary) do
      {:ok, image} -> {:ok, image}
      {:error, reason} -> {:error, {:image_open_failed, reason}}
    end
  end

  defp resize(image, role) do
    {width, height, _bands} = Image.shape(image)
    target = Map.fetch!(@target_dimensions, role)

    if should_resize?(width, height, target) do
      do_resize(image, target)
    else
      {:ok, image}
    end
  end

  defp should_resize?(width, height, {:fit, target_w, target_h}) do
    width > target_w or height > target_h
  end

  defp should_resize?(width, height, {:longest_edge, max_edge}) do
    max(width, height) > max_edge
  end

  defp do_resize(image, {:fit, target_w, target_h}) do
    case Image.thumbnail(image, target_w, height: target_h, resize: :down) do
      {:ok, resized} -> {:ok, resized}
      {:error, reason} -> {:error, {:resize_failed, reason}}
    end
  end

  defp do_resize(image, {:longest_edge, max_edge}) do
    case Image.thumbnail(image, max_edge, resize: :down) do
      {:ok, resized} -> {:ok, resized}
      {:error, reason} -> {:error, {:resize_failed, reason}}
    end
  end

  defp write_image(image, role, dest_path) do
    opts = write_opts(role)

    case Image.write(image, dest_path, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:write_failed, dest_path, reason}}
    end
  end

  defp write_opts("logo"), do: [suffix: ".png"]
  defp write_opts(_role), do: [suffix: ".jpg", quality: 90]
end
