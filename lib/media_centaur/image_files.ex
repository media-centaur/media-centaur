defmodule MediaCentaur.ImageFiles do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared image download and storage service.

  Any context can call this to download an image from a URL, optionally
  resize it, and write it to disk. Does not own queuing, retry scheduling,
  or database records — those stay in their respective contexts. Requests
  go through `MediaCentaur.HttpClient` without Req's own retries, since
  the image pipeline schedules retries itself.

  Images come from more than one upstream (the TMDB image CDN, the Steam
  CDN), so every download names its `:upstream` — the caller knows, this
  module does not.
  """

  alias MediaCentaur.HttpClient

  @doc """
  Downloads an image from `url`, optionally resizes it, and writes to `dest_path`.

  Options:
  - `:upstream` — required; the `MediaCentaur.HttpClient.Upstream` id the URL belongs to.
  - `:resize` — `{:fit, width, height}` or `{:longest_edge, max}`. Skipped if image is already smaller.
  - `:format` — `:jpg` (default) or `:png`. Determines write options.

  Returns `{:ok, dest_path}` on success, `{:error, category, reason}` on failure.
  Category is `:permanent` (will never succeed) or `:transient` (might work later).
  """
  def download(url, dest_path, opts \\ []) do
    dest_path |> Path.dirname() |> File.mkdir_p!()

    resize = Keyword.get(opts, :resize)
    format = Keyword.get(opts, :format, :jpg)

    with {:ok, body} <- fetch(url, Keyword.fetch!(opts, :upstream)),
         {:ok, image} <- open(body),
         {:ok, resized} <- maybe_resize(image, resize),
         :ok <- write(resized, dest_path, format) do
      {:ok, dest_path}
    else
      {:error, reason} -> {:error, categorize(reason), reason}
    end
  end

  # Smallest legitimate image we expect to see on the wire. Logo PNGs
  # land in the 3-30 KB range; even a 16x16 favicon is well over 1 KB.
  # Anything under this is overwhelmingly an error envelope (TMDB JSON
  # error ~200B), an HTML 4xx page, or a placeholder GIF (43B). We
  # treat them as permanent failures so they never land on disk.
  @raw_min_bytes 1024

  @doc """
  Downloads raw bytes from `url` and writes directly to `dest_path`.
  No image processing — just HTTP fetch + disk write.

  Rejects responses smaller than #{@raw_min_bytes} bytes (no real
  image we serve is that small) with
  `{:error, :permanent, {:body_too_small, url, byte_size}}` so partial
  / error-envelope downloads can't masquerade as valid images.

  Options: `:upstream` — required, as for `download/3`.

  Returns `{:ok, dest_path}` or `{:error, category, reason}`.
  """
  def download_raw(url, dest_path, opts) do
    dest_path |> Path.dirname() |> File.mkdir_p!()

    case fetch(url, Keyword.fetch!(opts, :upstream)) do
      {:ok, body} when is_binary(body) and byte_size(body) >= @raw_min_bytes ->
        File.write!(dest_path, body)
        {:ok, dest_path}

      {:ok, body} when is_binary(body) ->
        {:error, :permanent, {:body_too_small, url, byte_size(body)}}

      {:error, reason} ->
        {:error, categorize(reason), reason}
    end
  end

  # Fixed ladder of derivative widths. A requested width snaps UP to the
  # nearest tier, bounding the number of cached variants per image (max one
  # file per tier) while still giving `srcset`/DPR enough granularity. Tiers
  # cover thumbnail tiles (160) through near-full backdrops (1920); anything
  # wider is served from the master untouched.
  @derivative_widths [160, 240, 320, 480, 640, 960, 1280, 1920]

  @doc """
  Returns a path to a width-constrained JPEG/PNG derivative of a local master
  image, generating and caching it on first request.

  `requested_width` snaps UP to the fixed width ladder. The derivative is
  cached to disk and reused until the master is rewritten (a TMDB re-scrape
  bumps the master's mtime, which invalidates the cache). The output format
  matches the master's (so transparent logos keep their alpha).

  Two cases return the master path **unchanged** rather than a derivative —
  both protect quality by never upscaling:

  - the snapped width is at or above the master's own width, or
  - the requested width exceeds the ladder ceiling (caller wants full res).

  Returns `{:ok, path}` (a derivative or the master) or `{:error, reason}`;
  callers should fall back to the master on error so the image always renders.
  """
  def derivative(master_path, requested_width)
      when is_binary(master_path) and is_integer(requested_width) and requested_width > 0 do
    case snap_width(requested_width) do
      :full ->
        {:ok, master_path}

      width ->
        cache_path = derivative_cache_path(master_path, width)

        if derivative_fresh?(cache_path, master_path) do
          {:ok, cache_path}
        else
          build_derivative(master_path, width, cache_path)
        end
    end
  end

  @doc """
  Deletes every cached width derivative of `master_path` and returns the count
  removed. Used when a master is re-fetched at a new resolution — the stale
  derivatives are reclaimed immediately rather than waiting for the lazy
  mtime-based regeneration to overwrite them. Safe to call when none exist.
  """
  @spec purge_derivatives_for(String.t()) :: non_neg_integer()
  def purge_derivatives_for(master_path) when is_binary(master_path) do
    key = derivative_key(master_path)
    root = derivative_root()

    for width <- @derivative_widths, ext <- [".jpg", ".png"], reduce: 0 do
      acc ->
        case File.rm(Path.join(root, "#{key}-w#{width}#{ext}")) do
          :ok -> acc + 1
          _ -> acc
        end
    end
  end

  defp snap_width(requested) do
    Enum.find(@derivative_widths, :full, &(&1 >= requested))
  end

  defp derivative_cache_path(master_path, width) do
    ext =
      master_path
      |> Path.extname()
      |> String.downcase()
      |> case do
        ".png" -> ".png"
        _ -> ".jpg"
      end

    Path.join(derivative_root(), "#{derivative_key(master_path)}-w#{width}#{ext}")
  end

  defp derivative_key(master_path) do
    Base.url_encode64(:crypto.hash(:sha256, master_path), padding: false)
  end

  # Derivatives live under the app data dir so they survive restarts and never
  # touch the (possibly read-only / network-mounted) media image caches. The
  # per-process override lets async tests redirect the cache into a tmp dir
  # without mutating global config.
  defp derivative_root do
    base =
      Process.get(:image_derivative_root) ||
        MediaCentaur.Settings.Config.get(:data_dir) ||
        System.tmp_dir!()

    Path.join(base, "image-derivatives")
  end

  defp derivative_fresh?(cache_path, master_path) do
    with {:ok, %{mtime: cache_mtime}} <- File.stat(cache_path),
         {:ok, %{mtime: master_mtime}} <- File.stat(master_path) do
      cache_mtime >= master_mtime
    else
      _ -> false
    end
  end

  defp build_derivative(master_path, width, cache_path) do
    with {:ok, image} <- open_file(master_path),
         {master_width, _height, _bands} <- Image.shape(image) do
      if master_width <= width do
        {:ok, master_path}
      else
        cache_path |> Path.dirname() |> File.mkdir_p!()

        with {:ok, thumb} <- Image.thumbnail(image, width, resize: :down),
             {:ok, _} <- Image.write(thumb, cache_path, derivative_write_opts(cache_path)) do
          {:ok, cache_path}
        end
      end
    end
  end

  defp open_file(path) do
    case Image.open(path) do
      {:ok, image} -> {:ok, image}
      {:error, reason} -> {:error, {:image_open_failed, reason}}
    end
  end

  defp derivative_write_opts(cache_path) do
    case Path.extname(cache_path) do
      ".png" -> [suffix: ".png"]
      _ -> [suffix: ".jpg", quality: 82]
    end
  end

  # --- HTTP ---

  defp fetch(url, upstream) do
    client = HttpClient.new(__MODULE__, upstream: upstream, retry: false, decode_body: false)

    case Req.get(client, url: url) do
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
  defp categorize({:image_open_failed, _reason}), do: :permanent
  defp categorize({:resize_failed, _reason}), do: :permanent
  defp categorize({:write_failed, _path, _reason}), do: :transient
end
