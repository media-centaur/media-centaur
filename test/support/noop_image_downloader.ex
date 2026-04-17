defmodule MediaCentarr.NoopImageDownloader do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  No-op HTTP client for tests. Replaces `Req` in the image pipeline
  to avoid real HTTP requests and file I/O during tests.

  Returns an empty response body on `get/1`.
  """

  def get(_url) do
    {:ok, %{status: 200, body: ""}}
  end
end
