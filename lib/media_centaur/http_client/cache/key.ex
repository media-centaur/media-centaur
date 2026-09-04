defmodule MediaCentaur.HttpClient.Cache.Key do
  @moduledoc """
  The cache key of a GET request: host, path, and its query with the
  excluded params removed and the rest sorted.

  Sorting makes `?a=1&b=2` and `?b=2&a=1` one entry. Excluding params
  keeps credentials (TMDB's `api_key`) out of the key, so a key change
  does not orphan every entry and the key never carries a secret.
  """

  @type t :: {host :: String.t() | nil, path :: String.t(), query :: [{String.t(), String.t()}]}

  @doc "Builds the key for a resolved request URL."
  @spec build(URI.t(), [String.t()]) :: t()
  def build(%URI{} = url, exclude_params) do
    query =
      (url.query || "")
      |> URI.decode_query()
      |> Map.drop(exclude_params)
      |> Enum.sort()

    {url.host, url.path || "/", query}
  end
end
