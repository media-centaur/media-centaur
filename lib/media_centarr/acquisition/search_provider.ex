defmodule MediaCentarr.Acquisition.SearchProvider do
  @moduledoc """
  Behaviour for media search and grab providers.

  The only shipped implementation is `Acquisition.Prowlarr`. Future providers
  (e.g. Jackett) implement this behaviour without requiring changes to call sites.
  """

  alias MediaCentarr.Acquisition.{QueueItem, SearchResult}

  @doc """
  Searches for releases matching the given query.

  `opts` may include:
  - `:type` — `:movie` or `:tv` (default: search both)
  - `:year` — integer year to narrow results
  """
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [SearchResult.t()]} | {:error, term()}

  @doc """
  Submits a grab request for the given search result.

  Prowlarr routes the grab to whatever download client is configured.
  Returns `:ok` on success.
  """
  @callback grab(result :: SearchResult.t()) :: :ok | {:error, term()}

  @doc """
  Returns the current download queue from the provider's configured download
  client(s). Used by the Download page to surface live progress.
  """
  @callback queue() :: {:ok, [QueueItem.t()]} | {:error, term()}
end
