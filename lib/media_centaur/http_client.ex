defmodule MediaCentaur.HttpClient do
  use Boundary,
    top_level?: true,
    deps: [MediaCentaur.ErrorReports],
    exports: [Cache, Cache.Coordinator, IncidentContext, Instrument, Stats, Supervisor, Upstream]

  @moduledoc """
  The one seam every outbound HTTP request passes through.

  `new/2` builds the `Req` client an upstream is talked to with, and
  attaches the concerns that are the same for every upstream:

    * **Upstream tagging** — `opts[:upstream]` names the remote party
      (`MediaCentaur.HttpClient.Upstream`); required, so no request can
      be built that the Status panel cannot attribute.
    * **Instrumentation** — `MediaCentaur.HttpClient.Instrument` emits
      one telemetry event per request.
    * **Response cache** — `opts[:cache]` attaches
      `MediaCentaur.HttpClient.Cache`, an origin-freshness cache with
      ETag revalidation. Off unless asked for.
    * **Stub routing** — in the test environment the client for
      `module` is routed through the `Req.Test` stub registered for it
      under `config :media_centaur, :req_test_stubs, %{module => stub}`,
      so no test reaches the network and no test has to smuggle a
      stubbed client into a cache: a client is built from its settings
      on every call. A caller may also pass `plug:` directly.

  Anything HTTP that bypasses this function is invisible to the panel,
  which is why the Credo check MC0029 (`OutboundHttpSeam`) forbids
  `Req.new/1` and URL-form `Req.get/2` outside this module.

  `module` is the calling module, used only for stub routing. It is
  not the upstream: one upstream may be spoken to by several modules
  (the self-update checker and downloader both talk to GitHub).
  """

  alias MediaCentaur.HttpClient.{Cache, Instrument, Upstream}

  @doc """
  A `Req` client for `module` talking to `opts[:upstream]`.

  Options other than `:upstream` and `:cache` are `Req.new/1` options.
  `cache: true` attaches the response cache with defaults;
  `cache: keyword` passes `MediaCentaur.HttpClient.Cache.attach/2`
  options.
  """
  @spec new(module(), keyword()) :: Req.Request.t()
  def new(module, opts) when is_atom(module) and is_list(opts) do
    {upstream, opts} = Keyword.pop(opts, :upstream)
    {cache, opts} = Keyword.pop(opts, :cache, false)

    if !Upstream.known?(upstream) do
      raise ArgumentError,
            "HttpClient.new/2 needs an upstream from #{inspect(Upstream.ids())}, got #{inspect(upstream)}"
    end

    opts
    |> stub_route(module)
    |> Req.new()
    |> Instrument.attach(upstream)
    |> attach_cache(cache)
  end

  # A stubbed client also gets Req's retry step switched off: a retry
  # against an in-process stub is pure backoff sleep (1s + 2s + 4s per
  # stubbed 5xx), and the stub returns the same answer every time.
  defp stub_route(opts, module) do
    case Application.get_env(:media_centaur, :req_test_stubs, %{}) do
      %{^module => stub_name} ->
        opts
        |> Keyword.put_new(:plug, {Req.Test, stub_name})
        |> Keyword.put_new(:retry, false)

      _ ->
        opts
    end
  end

  defp attach_cache(request, false), do: request
  defp attach_cache(request, true), do: Cache.attach(request, [])
  defp attach_cache(request, opts) when is_list(opts), do: Cache.attach(request, opts)
end
