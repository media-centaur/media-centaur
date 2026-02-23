defmodule MediaManager.NoopImageDownloader do
  @moduledoc """
  No-op image downloader for tests. Replaces `Pipeline.ImageDownloader`
  to avoid real HTTP requests and file I/O during pipeline tests.
  """

  def download_all(_entity), do: :ok
end
