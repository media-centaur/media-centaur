defmodule MediaCentaur.HttpClient.Cache do
  @moduledoc """
  A Req plugin that serves repeated GETs from an origin-freshness cache.

  Freshness comes from the origin's `Cache-Control: max-age`
  (`MediaCentaur.HttpClient.Cache.Freshness`); there is no policy table
  of our own. What the steps do per request:

    * **Fresh entry** — the request step answers from the table and
      never reaches the adapter. Reported as `cache: :hit`.
    * **Stale entry** — the caller claims the key with the coordinator.
      The leader sends `If-None-Match`; a 304 renews the entry and the
      caller sees a 200 with the stored body, a 200 replaces it.
      Reported as `:revalidate` (or `:miss` when the entry has no ETag).
    * **No entry** — the leader makes the request; a cacheable 200 is
      stored. Reported as `:miss`.
    * **`reload: true`** — a per-request option: fetch regardless and
      overwrite. Reported as `:reload`.
    * **Followers** — callers that claim a key already in flight wait
      for the leader's outcome and share it. Reported as `:hit`.

  Only GETs take part. Non-GET requests, and every request when the
  coordinator is not running (the test environment), pass through
  untouched and report `:uncached`.

  The store step is inserted ahead of Req's `decode_body` so the entry
  keeps the wire binary; a hit is a synthesized 200 carrying that binary
  and the stored content type, which the reader's own `decode_body`
  then decodes.

  ## Options for `attach/2`

    * `:name` — the coordinator / table name. Defaults to
      `MediaCentaur.HttpClient.Cache.Coordinator`.
    * `:exclude_params` — query params left out of the key (credentials).
  """

  alias MediaCentaur.HttpClient.Cache.{Coordinator, Entry, Key}

  @doc "Attaches the cache steps to `request`."
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts) do
    config = %{
      name: Keyword.get(opts, :name, Coordinator),
      exclude_params: Keyword.get(opts, :exclude_params, [])
    }

    request
    |> Req.Request.register_options([:reload])
    |> Req.Request.put_private(:http_cache_config, config)
    |> Req.Request.append_request_steps(http_cache_lookup: &lookup/1)
    |> insert_before_decode(http_cache_store: &store/1)
    |> Req.Request.append_error_steps(http_cache_release: &release/1)
  end

  @doc "Table statistics for the default coordinator, or for a client's."
  @spec stats(Req.Request.t() | Coordinator.name()) :: %{entries: non_neg_integer()}
  def stats(target \\ Coordinator)

  def stats(%Req.Request{} = request) do
    stats(Req.Request.get_private(request, :http_cache_config).name)
  end

  def stats(name) when is_atom(name), do: %{entries: Coordinator.entry_count(name)}

  # --- Request step ---

  defp lookup(%Req.Request{method: :get} = request) do
    config = Req.Request.get_private(request, :http_cache_config)

    if Coordinator.running?(config.name) do
      key = Key.build(request.url, config.exclude_params)
      request = Req.Request.put_private(request, :http_cache_key, key)
      entry = Coordinator.lookup(config.name, key)
      now = System.monotonic_time(:millisecond)

      cond do
        request.options[:reload] == true -> lead_or_follow(request, config, :reload, nil)
        entry == nil -> lead_or_follow(request, config, :miss, nil)
        Entry.fresh?(entry, now) -> hit(request, entry)
        entry.etag == nil -> lead_or_follow(request, config, :miss, nil)
        true -> lead_or_follow(request, config, :revalidate, entry)
      end
    else
      request
    end
  end

  defp lookup(request), do: request

  defp hit(request, entry) do
    {Req.Request.put_private(request, :http_cache, :hit), Entry.to_response(entry)}
  end

  defp lead_or_follow(request, config, outcome, stale_entry) do
    key = Req.Request.get_private(request, :http_cache_key)

    case Coordinator.claim(config.name, key) do
      :leader ->
        request
        |> Req.Request.put_private(:http_cache, outcome)
        |> Req.Request.put_private(:http_cache_leader, true)
        |> Req.Request.put_private(:http_cache_stale, stale_entry)
        |> put_if_none_match(stale_entry)

      {:done, response} ->
        {Req.Request.put_private(request, :http_cache, :hit), response}

      {:failed, exception} ->
        {Req.Request.put_private(request, :http_cache, :miss), exception}
    end
  end

  defp put_if_none_match(request, %Entry{etag: etag}) when is_binary(etag) do
    Req.Request.put_header(request, "if-none-match", etag)
  end

  defp put_if_none_match(request, _entry), do: request

  # --- Response step (leader only) ---

  defp store({request, response}) do
    if Req.Request.get_private(request, :http_cache_leader) do
      config = Req.Request.get_private(request, :http_cache_config)
      key = Req.Request.get_private(request, :http_cache_key)
      stale = Req.Request.get_private(request, :http_cache_stale)
      {response, entry} = outcome(key, response, stale, System.monotonic_time(:millisecond))
      Coordinator.done(config.name, key, response, entry)
      {request, response}
    else
      {request, response}
    end
  end

  defp outcome(_key, %Req.Response{status: 304} = response, %Entry{} = stale, now) do
    renewed = Entry.renew(stale, response, now)
    {Entry.to_response(renewed), renewed}
  end

  defp outcome(key, response, _stale, now) do
    {response, Entry.from_response(key, response, now)}
  end

  # --- Error step (leader only) ---

  defp release({request, exception}) do
    if Req.Request.get_private(request, :http_cache_leader) do
      config = Req.Request.get_private(request, :http_cache_config)
      Coordinator.failed(config.name, Req.Request.get_private(request, :http_cache_key), exception)
    end

    {request, exception}
  end

  # The entry must hold the wire binary, so the store step runs before
  # Req decodes the body.
  defp insert_before_decode(request, step) do
    {ahead, rest} =
      Enum.split_while(request.response_steps, fn {name, _step} -> name != :decode_body end)

    %{request | response_steps: ahead ++ step ++ rest}
  end
end
