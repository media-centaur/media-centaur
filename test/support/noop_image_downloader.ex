defmodule MediaCentaur.NoopImageDownloader do
  @moduledoc """
  No-op image downloader for tests. Replaces `Pipeline.ImageDownloader`
  to avoid real HTTP requests and file I/O during pipeline tests.
  """

  def download_all(_entity), do: :ok

  def download(_url, local_path) do
    local_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(local_path, "")
    :ok
  end
end
