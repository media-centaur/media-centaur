defmodule MediaManagerWeb.Plugs.ImageServer do
  @moduledoc """
  Serves local entity images from the configured `media_images_dir`.

  Intercepts requests at `/media-images/*` and maps them to files on disk.
  The images directory is resolved at runtime via `MediaManager.Config`.
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
      images_dir = MediaManager.Config.get(:media_images_dir)
      file_path = Path.join([images_dir | rest])

      if File.regular?(file_path) do
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
