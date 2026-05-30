defmodule MediaCentaurWeb.Plugs.ImageServer do
  @moduledoc """
  Serves local entity images from per-watch-directory image caches.

  Intercepts requests at `/media-images/*` and searches all configured
  watch directories' image caches for the requested file. If the file
  is not present on disk, responds 200 with an inline SVG placeholder
  whose viewBox matches the requested role's aspect ratio, so every
  `<img src="/media-images/…">` in the UI has a graceful fallback
  without per-call-site JS or extra binary assets.

  Role is inferred from the filename's stem — `poster.jpg` / `backdrop.jpg`
  / `thumb.jpg` / `logo.png` each produce a differently-shaped placeholder;
  anything else falls through to a generic square.
  """
  @behaviour Plug
  import Plug.Conn

  # {width, height} in SVG units — the viewBox shape is what makes the
  # placeholder swap in seamlessly for the missing asset.
  @placeholder_dims %{
    "poster" => {200, 300},
    "backdrop" => {320, 180},
    "thumb" => {320, 180},
    "logo" => {400, 100},
    "unknown" => {200, 200}
  }

  @impl true
  def init(opts), do: opts

  @impl true
  # Bare `/media-images` with nothing after it (path_info `["media-images"]`,
  # so `rest == []`). Reached when an `<img src>` is built from an empty/nil
  # image path (`/media-images/#{""}`) or a crawler pokes the mount point.
  # `Path.join([])` raises, so short-circuit to the same graceful placeholder
  # a missing file gets — there's no filename to look up, role is "unknown".
  def call(%{path_info: ["media-images"]} = conn, _opts) do
    send_placeholder(conn, "")
  end

  def call(%{path_info: ["media-images" | rest]} = conn, _opts) do
    if Enum.any?(rest, &(&1 == "..")) do
      conn |> send_resp(400, "Bad request") |> halt()
    else
      relative = Path.join(rest)

      case locate_file(relative) do
        nil -> send_placeholder(conn, relative)
        file_path -> send_file_response(conn, file_path)
      end
    end
  end

  def call(conn, _opts), do: conn

  defp locate_file(relative) do
    watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

    Enum.find_value(watch_dirs, fn dir ->
      candidate = Path.join(MediaCentaur.Config.images_dir_for(dir), relative)
      if File.regular?(candidate), do: candidate
    end) || find_in_data_dir(relative) || find_in_legacy_data(relative)
  end

  # Configured app-data root — covers tracking-item images written by
  # `MediaCentaur.ReleaseTracking.ImageStore`. Independent of cwd.
  defp find_in_data_dir(relative) do
    case MediaCentaur.Config.get(:data_dir) do
      nil ->
        nil

      data_dir ->
        candidate = Path.join(data_dir, relative)
        if File.regular?(candidate), do: candidate
    end
  end

  # Legacy cwd-relative fallback — kept so installs that wrote images
  # before `:data_dir` was introduced continue to serve them without a
  # manual move.
  defp find_in_legacy_data(relative) do
    candidate = Path.join("data", relative)
    if File.regular?(candidate), do: candidate
  end

  defp send_file_response(conn, file_path) do
    conn
    |> put_resp_content_type(MIME.from_path(file_path))
    |> put_cache_headers(file_path, conn.query_string)
    |> send_file(200, file_path)
    |> halt()
  end

  # Versioned URLs (`?v=<n>` or any query string) are the cache key:
  # the LiveView bumps the version to invalidate, which produces a new
  # URL. The file at the unversioned path is effectively immutable for
  # *this* URL, so a far-future + `immutable` directive lets the browser
  # skip even the conditional revalidation roundtrip.
  defp put_cache_headers(conn, _file_path, query) when query != "" do
    put_resp_header(conn, "cache-control", "public, max-age=31536000, immutable")
  end

  # Plain URLs don't carry a cache-buster, so the same URL can legally
  # return new bytes after a TMDB re-scrape. A short max-age + ETag keeps
  # repeat views instant while bounding staleness to an hour.
  defp put_cache_headers(conn, file_path, "") do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> put_etag(file_path)
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

  defp send_placeholder(conn, relative) do
    role = role_from_filename(relative)

    # The same URL maps to either the placeholder OR the real artwork
    # depending on whether the watch dir is mounted. Caching the placeholder
    # would shadow the real file once the drive comes back, so the browser
    # would keep serving stale placeholders. `no-store` is the only correct
    # directive for a response whose body can flip on the next request
    # without the URL changing.
    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, placeholder_svg(role))
    |> halt()
  end

  defp role_from_filename(relative) do
    stem =
      relative
      |> Path.basename()
      |> Path.rootname()
      |> String.downcase()

    case stem do
      "poster" -> "poster"
      "backdrop" -> "backdrop"
      "thumb" -> "thumb"
      "thumbnail" -> "thumb"
      "logo" -> "logo"
      _ -> "unknown"
    end
  end

  defp placeholder_svg(role) do
    {w, h} = Map.fetch!(@placeholder_dims, role)
    icon_size = trunc(min(w, h) * 0.24)
    icon_x = div(w - icon_size, 2)
    icon_y = div(h - icon_size, 2)

    ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{w} #{h}" preserveAspectRatio="xMidYMid slice">) <>
      ~s(<rect width="#{w}" height="#{h}" fill="#0c0d11"/>) <>
      ~s(<svg x="#{icon_x}" y="#{icon_y}" width="#{icon_size}" height="#{icon_size}" viewBox="0 0 24 24" fill="none" stroke="#2a2d38" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round">) <>
      ~s(<path d="M7.5 6 9 4.5h6L16.5 6m-9 0h9M7.5 6v12M16.5 6v12m-9 0L6 19.5h12L16.5 18m-9 0h9m-9-6h9M7.5 9h9"/>) <>
      ~s(</svg></svg>)
  end
end
