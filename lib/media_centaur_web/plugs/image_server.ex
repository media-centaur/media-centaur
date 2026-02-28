defmodule MediaCentaurWeb.Plugs.ImageServer do
  @moduledoc """
  Serves local entity images from per-watch-directory image caches.

  Intercepts requests at `/media-images/*` and searches all configured
  watch directories' image caches for the requested file.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_info: ["media-images" | rest]} = conn, _opts) do
    if Enum.any?(rest, &(&1 == "..")) do
      conn |> send_resp(400, "Bad request") |> halt()
    else
      relative = Path.join(rest)
      watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

      file_path =
        Enum.find_value(watch_dirs, fn dir ->
          candidate = Path.join(MediaCentaur.Config.images_dir_for(dir), relative)
          if File.regular?(candidate), do: candidate
        end)

      if file_path do
        conn
        |> put_resp_content_type(MIME.from_path(file_path))
        |> send_file(200, file_path)
        |> halt()
      else
        conn |> send_resp(404, "Not found") |> halt()
      end
    end
  end

  def call(conn, _opts), do: conn
end
