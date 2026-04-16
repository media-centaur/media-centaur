defmodule MediaCentarr.Images do
  @moduledoc """
  Shared image download and storage service.

  Any context can call this to download an image from a URL, optionally
  resize it, and write it to disk. Does not own queuing, retry scheduling,
  or database records — those stay in their respective contexts.
  """

  @doc """
  Downloads an image from `url`, optionally resizes it, and writes to `dest_path`.

  Options:
  - `:resize` — `{:fit, width, height}` or `{:longest_edge, max}`. Skipped if image is already smaller.
  - `:format` — `:jpg` (default) or `:png`. Determines write options.

  Returns `{:ok, dest_path}` on success, `{:error, category, reason}` on failure.
  Category is `:permanent` (will never succeed) or `:transient` (might work later).
  """
  def download(url, dest_path, opts \\ []) do
    dest_path |> Path.dirname() |> File.mkdir_p!()

    resize = Keyword.get(opts, :resize)
    format = Keyword.get(opts, :format, :jpg)

    with {:ok, body} <- fetch(url),
         {:ok, image} <- open(body),
         {:ok, resized} <- maybe_resize(image, resize),
         :ok <- write(resized, dest_path, format) do
      {:ok, dest_path}
    else
      {:error, reason} -> {:error, categorize(reason), reason}
    end
  end

  @doc """
  Downloads raw bytes from `url` and writes directly to `dest_path`.
  No image processing — just HTTP fetch + disk write.

  Returns `{:ok, dest_path}` or `{:error, category, reason}`.
  """
  def download_raw(url, dest_path) do
    dest_path |> Path.dirname() |> File.mkdir_p!()

    case fetch(url) do
      {:ok, body} when is_binary(body) and byte_size(body) > 0 ->
        File.write!(dest_path, body)
        {:ok, dest_path}

      {:ok, _} ->
        {:error, :permanent, {:empty_body, url}}

      {:error, reason} ->
        {:error, categorize(reason), reason}
    end
  end

  # --- HTTP ---

  defp fetch(url) do
    case http_client().get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status, url}}

      {:error, reason} ->
        {:error, {:download_failed, url, reason}}
    end
  rescue
    _ -> {:error, {:download_failed, url, :unavailable}}
  end

  defp http_client, do: Application.get_env(:media_centarr, :image_http_client, Req)

  # --- Image operations ---

  defp open(binary) do
    case Image.from_binary(binary) do
      {:ok, image} -> {:ok, image}
      {:error, reason} -> {:error, {:image_open_failed, reason}}
    end
  end

  defp maybe_resize(image, nil), do: {:ok, image}

  defp maybe_resize(image, target) do
    {width, height, _bands} = Image.shape(image)

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

  # --- Write ---

  defp write(image, dest_path, format) do
    case Image.write(image, dest_path, write_opts(format)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:write_failed, dest_path, reason}}
    end
  end

  defp write_opts(:png), do: [suffix: ".png"]
  defp write_opts(:jpg), do: [suffix: ".jpg", quality: 90]

  # --- Error categorization ---

  @permanent_statuses [400, 401, 403, 404, 405, 410, 451]

  defp categorize({:http_error, status, _url}) when status in @permanent_statuses, do: :permanent
  defp categorize({:http_error, _status, _url}), do: :transient
  defp categorize({:download_failed, _url, _reason}), do: :transient
  defp categorize({:empty_body, _url}), do: :permanent
  defp categorize({:image_open_failed, _reason}), do: :permanent
  defp categorize({:resize_failed, _reason}), do: :permanent
  defp categorize({:write_failed, _path, _reason}), do: :transient
end
