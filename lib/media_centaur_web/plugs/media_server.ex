defmodule MediaCentaurWeb.Plugs.MediaServer do
  @moduledoc """
  Serves one playable file to a remote player: `GET`/`HEAD /media/:presence_id?t=<token>`.

  Ahead of the gate in the endpoint, admitted by the `MediaToken` alone
  (the device's session never travels with media bytes). The id is the
  file's `Library.FilePresence` row; the token must name that same file.
  The row's path is confined to the configured media directories, then
  served with `Plug.Conn.send_file/5`, which Bandit hands to the kernel
  (`sendfile`): the BEAM never copies media bytes.

  | Request | Answer |
  |---|---|
  | no or bad token, or a token for another file | `403` |
  | unknown id, a path outside every media directory, or a file gone from disk | `404` |
  | the file's media directory is unavailable (drive unmounted) | `503`, retryable |
  | no `Range` | `200`, the whole file |
  | one satisfiable `Range` | `206` with `Content-Range` |
  | an unsatisfiable `Range` | `416` with `Content-Range: bytes */size` |

  Every answer carries `Accept-Ranges: bytes`, `Content-Type` from the
  extension, `Last-Modified` and `ETag` from the file's mtime and size,
  and `Cache-Control: private, no-store`. `HEAD` gets the headers and no
  body. Range parsing is `MediaServer.Range`'s.
  """

  @behaviour Plug

  import Plug.Conn

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Library.MediaFileAvailability
  alias MediaCentaur.Settings.Config
  alias MediaCentaurWeb.MediaToken
  alias MediaCentaurWeb.Plugs.MediaServer.Range

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["media", presence_id], method: method} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn = fetch_query_params(conn)

    with {:ok, {_player_id, ^presence_id}} <- MediaToken.verify(conn.query_params["t"]),
         {:ok, presence} <- fetch_presence(presence_id),
         :ok <- confined?(presence.file_path),
         :ok <- available?(presence.media_dir),
         {:ok, stat} <- File.stat(presence.file_path, time: :posix) do
      serve(conn, presence.file_path, stat)
    else
      {:ok, {_player_id, _other_file}} -> refuse(conn, 403)
      {:error, reason} when reason in [:invalid, :expired, :missing] -> refuse(conn, 403)
      {:error, :unavailable} -> refuse(conn, 503)
      {:error, _not_found} -> refuse(conn, 404)
    end
  end

  def call(%Plug.Conn{path_info: ["media" | _rest]} = conn, _opts), do: refuse(conn, 405)
  def call(conn, _opts), do: conn

  defp fetch_presence(presence_id) do
    case FilePresence.fetch(presence_id) do
      {:ok, presence} -> {:ok, presence}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # The row's path must lie under a configured media directory: a presence
  # row names what the watcher saw, and only those directories are ours to
  # serve from.
  defp confined?(file_path) do
    expanded = Path.expand(file_path)

    inside? =
      Enum.any?(Config.get(:media_dirs) || [], fn dir ->
        String.starts_with?(expanded, Path.expand(dir) <> "/")
      end)

    if inside?, do: :ok, else: {:error, :outside_media_dirs}
  end

  defp available?(media_dir) do
    case Map.get(MediaFileAvailability.dir_status(), media_dir) do
      :unavailable -> {:error, :unavailable}
      _state -> :ok
    end
  end

  defp serve(conn, path, %File.Stat{size: size, mtime: mtime}) do
    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-type", MIME.from_path(path))
      |> put_resp_header("last-modified", http_date(mtime))
      |> put_resp_header("etag", ~s("#{Integer.to_string(mtime, 16)}-#{Integer.to_string(size, 16)}"))

    case Range.parse(List.first(get_req_header(conn, "range")), size) do
      :whole ->
        conn
        |> put_resp_header("content-length", Integer.to_string(size))
        |> send_body(200, path, 0, size)

      {:partial, offset, length} ->
        conn
        |> put_resp_header("content-range", "bytes #{offset}-#{offset + length - 1}/#{size}")
        |> put_resp_header("content-length", Integer.to_string(length))
        |> send_body(206, path, offset, length)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
        |> halt()
    end
  end

  defp send_body(%Plug.Conn{method: "HEAD"} = conn, status, _path, _offset, _length) do
    conn |> send_resp(status, "") |> halt()
  end

  defp send_body(conn, status, path, offset, length) do
    conn |> send_file(status, path, offset, length) |> halt()
  end

  defp refuse(conn, status) do
    conn
    |> put_resp_header("accept-ranges", "bytes")
    |> send_resp(status, "")
    |> halt()
  end

  defp http_date(posix_seconds) do
    posix_seconds
    |> DateTime.from_unix!()
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end
end
