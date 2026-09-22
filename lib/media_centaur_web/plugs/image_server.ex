defmodule MediaCentaurWeb.Plugs.ImageServer do
  @moduledoc """
  Serves local entity images from per-media-directory image caches.

  Intercepts requests at `/media-images/*` and searches all configured
  media directories' image caches, then the app data directory, for the
  requested file. A file that is not on disk is a 404.

  The plug never stands in for a missing file. Whether an entry's artwork
  can be shown is decided in the read models (`Library.Views.ItemAvailability`)
  from the availability of the entry's media directory, so a page never
  emits a URL this plug cannot serve while a drive is unmounted, and the
  URL appears — a DOM change the browser fetches — when the drive returns.
  The only way a page reaches a 404 here is a file missing while its volume
  is up, which is a data defect `Library.ImageHealth` reports and image
  repair fixes.
  """
  @behaviour Plug
  import Plug.Conn

  alias MediaCentaur.Settings.Config

  alias MediaCentaur.Library.ImageCache

  @impl true
  def init(opts), do: opts

  @impl true
  # Bare `/media-images` with nothing after it (path_info `["media-images"]`,
  # so `rest == []`): an `<img src>` built from an empty path, or a crawler
  # poking the mount point. `Path.join([])` raises, so answer 404 directly.
  def call(%{path_info: ["media-images"]} = conn, _opts) do
    send_not_found(conn)
  end

  def call(%{path_info: ["media-images" | rest]} = conn, _opts) do
    if Enum.any?(rest, &(&1 == "..")) do
      conn |> send_resp(400, "Bad request") |> halt()
    else
      relative = Path.join(rest)

      case locate_file(relative) do
        nil -> send_not_found(conn)
        master_path -> serve_image(conn, master_path)
      end
    end
  end

  def call(conn, _opts), do: conn

  # A `?w=<px>` request is served a width-constrained derivative (generated
  # and cached on first hit); without it, the full-resolution master. The
  # derivative protects paint latency for small display boxes — a calendar
  # tile that's 120px wide should not block on decoding a 3360px backdrop.
  # Large/full-bleed surfaces simply omit `?w=` and keep the master, so 4K
  # quality is untouched. Generation failure falls back to the master.
  defp serve_image(conn, master_path) do
    case requested_width(conn) do
      nil ->
        send_file_response(conn, master_path)

      width ->
        case MediaCentaur.ImageFiles.derivative(master_path, width) do
          {:ok, served_path} -> send_file_response(conn, served_path)
          {:error, _reason} -> send_file_response(conn, master_path)
        end
    end
  end

  defp requested_width(conn) do
    conn
    |> fetch_query_params()
    |> Map.fetch!(:query_params)
    |> Map.get("w")
    |> case do
      raw when is_binary(raw) ->
        case Integer.parse(raw) do
          {width, ""} when width > 0 and width <= 4096 -> width
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp locate_file(relative) do
    ImageCache.resolve_path(relative) || find_in_data_dir(relative)
  end

  # Configured app-data root — covers tracking-item images written by
  # `MediaCentaur.ReleaseTracking.ImageStore`. Independent of cwd.
  defp find_in_data_dir(relative) do
    case Config.get(:data_dir) do
      nil ->
        nil

      data_dir ->
        candidate = Path.join(data_dir, relative)
        if File.regular?(candidate), do: candidate
    end
  end

  defp send_file_response(conn, file_path) do
    conn
    |> put_resp_content_type(MIME.from_path(file_path))
    |> put_cache_headers(file_path, conn.query_string)
    |> send_file(200, file_path)
    |> halt()
  end

  # Immutable caching is keyed on an explicit `?v=` cache-buster — the only
  # param that guarantees a new URL when the bytes change (the LiveView bumps
  # it to invalidate). A bare `?w=` derivative request must NOT be treated as
  # immutable: the derivative is regenerated in place when its master is
  # re-scraped, so it needs the same revalidatable max-age + ETag a plain
  # master URL gets.
  defp put_cache_headers(conn, file_path, query) do
    if versioned?(query) do
      put_resp_header(conn, "cache-control", "public, max-age=31536000, immutable")
    else
      conn
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> put_etag(file_path)
    end
  end

  defp versioned?(query) do
    query
    |> Kernel.||("")
    |> URI.decode_query()
    |> Map.has_key?("v")
  end

  defp put_etag(conn, file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size, mtime: mtime}} ->
        seconds = :calendar.datetime_to_gregorian_seconds(mtime)
        put_resp_header(conn, "etag", ~s("#{size}-#{seconds}"))

      _ ->
        conn
    end
  end

  # Uncached: the same URL serves the file the moment it is on disk.
  defp send_not_found(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(404, "Not found")
    |> halt()
  end
end
