defmodule MediaCentaurWeb.Plugs.ImageServer do
  @moduledoc """
  Serves local entity images from per-media-directory image caches.

  Intercepts requests at `/media-images/*` and searches all configured
  media directories' image caches for the requested file. If the file
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

  alias MediaCentaur.Settings.Config

  # {width, height} in SVG units — the viewBox shape is what makes the
  # placeholder swap in seamlessly for the missing asset.
  @placeholder_dims %{
    "poster" => {200, 300},
    "backdrop" => {320, 180},
    "thumb" => {320, 180},
    "logo" => {400, 100},
    "banner" => {320, 150},
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
    media_dirs = Config.get(:media_dirs) || []

    Enum.find_value(media_dirs, fn dir ->
      candidate = Path.join(Config.images_dir_for(dir), relative)
      if File.regular?(candidate), do: candidate
    end) || find_in_data_dir(relative)
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

  defp send_placeholder(conn, relative) do
    role = role_from_filename(relative)

    # The same URL maps to either the placeholder OR the real artwork
    # depending on whether the media dir is mounted. Caching the placeholder
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
      "banner" -> "banner"
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
