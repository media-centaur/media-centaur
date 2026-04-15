defmodule MediaCentaur.Acquisition.Prowlarr do
  @moduledoc """
  `SearchProvider` implementation backed by the Prowlarr indexer aggregator API.

  Uses Prowlarr's search endpoint to find releases and its grab endpoint to
  submit a chosen release to the configured download client.

  The HTTP client is cached in `:persistent_term` and built lazily from config.
  Pass an explicit `client` argument in tests to inject a `Req.Test` stub.
  """

  @behaviour MediaCentaur.Acquisition.SearchProvider

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.SearchResult

  @doc "Returns a Req client configured for Prowlarr. Cached in `:persistent_term`."
  def default_client do
    case :persistent_term.get({__MODULE__, :client}, nil) do
      nil ->
        client = build_client()
        :persistent_term.put({__MODULE__, :client}, client)
        client

      client ->
        client
    end
  end

  defp build_client do
    url = MediaCentaur.Config.get(:prowlarr_url)
    api_key = MediaCentaur.Config.get(:prowlarr_api_key)
    Req.new(base_url: url, headers: [{"x-api-key", api_key}])
  end

  @impl true
  def search(query, opts \\ [], client \\ default_client()) do
    params = [query: query, type: "search"] ++ maybe_year(opts)
    Log.info(:library, "prowlarr search — #{query}")

    case Req.get(client, url: "/api/v1/search", params: params) do
      {:ok, %{status: 200, body: results}} when is_list(results) ->
        search_results = Enum.map(results, &SearchResult.from_prowlarr/1)
        Log.info(:library, "prowlarr found #{length(search_results)} results for #{query}")
        {:ok, search_results}

      {:ok, %{status: status, body: body}} ->
        Log.warning(:library, "prowlarr search failed — status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:library, "prowlarr search error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def grab(result, client \\ default_client()) do
    Log.info(:library, "prowlarr grab — #{result.title}")

    payload = %{"guid" => result.guid, "indexerId" => result.indexer_id}

    case Req.post(client, url: "/api/v1/release", json: payload) do
      {:ok, %{status: 200}} ->
        Log.info(:library, "prowlarr grab submitted — #{result.title}")
        :ok

      {:ok, %{status: status, body: body}} ->
        Log.warning(:library, "prowlarr grab failed — status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:library, "prowlarr grab error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_year(opts) do
    case Keyword.get(opts, :year) do
      nil -> []
      year -> [year: year]
    end
  end
end
