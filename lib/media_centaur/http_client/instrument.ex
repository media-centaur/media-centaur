defmodule MediaCentaur.HttpClient.Instrument do
  @moduledoc """
  Req steps that emit one telemetry event per outbound HTTP request.

  `attach/2` prepends a request step that stamps the start time and
  prepends a response step and an error step that emit
  `[:media_centaur, :http, :request, :stop]`. Prepending puts the stop
  step ahead of Req's `retry` step, so a retried request emits once per
  attempt and never twice for the final response.

  ## Event

      [:media_centaur, :http, :request, :stop]

  Measurements: `%{duration: native_time}`.

  Metadata:

    * `:upstream` — `t:MediaCentaur.HttpClient.Upstream.id/0`
    * `:method` — `:get`, `:post`, ...
    * `:host`, `:path` — from the resolved request URL
    * `:status` — integer, or `nil` on a transport error
    * `:error` — the exception, or `nil`
    * `:cache` — what the response cache did for this request:
      `:uncached` (no cache attached), `:hit`, `:miss`, `:revalidate`
      (a stale entry was sent with `If-None-Match`), or `:reload`
    * `:rate_limit_wait` — native time spent waiting for a rate-limit
      slot, `0` when the client has no limiter

  The event is the whole observability contract of the HTTP layer:
  `MediaCentaur.HttpClient.Stats` folds it into the Status panel.
  """

  alias MediaCentaur.HttpClient.Upstream

  @stop_event [:media_centaur, :http, :request, :stop]

  @doc "Attaches the instrumentation steps for `upstream` to `request`."
  @spec attach(Req.Request.t(), Upstream.id()) :: Req.Request.t()
  def attach(%Req.Request{} = request, upstream) do
    request
    |> Req.Request.put_private(:http_upstream, upstream)
    |> Req.Request.prepend_request_steps(http_instrument_start: &start/1)
    |> Req.Request.prepend_response_steps(http_instrument_stop: &stop/1)
    |> Req.Request.prepend_error_steps(http_instrument_error: &error/1)
  end

  @doc "The stop event name."
  @spec stop_event() :: [atom()]
  def stop_event, do: @stop_event

  defp start(request) do
    Req.Request.put_private(request, :http_started_at, System.monotonic_time())
  end

  defp stop({request, %Req.Response{status: status} = response}) do
    emit(request, status, nil)
    {request, response}
  end

  defp error({request, exception}) do
    emit(request, nil, exception)
    {request, exception}
  end

  defp emit(request, status, error) do
    started_at = Req.Request.get_private(request, :http_started_at, System.monotonic_time())

    metadata = %{
      upstream: Req.Request.get_private(request, :http_upstream),
      method: request.method,
      host: request.url.host,
      path: request.url.path || "/",
      status: status,
      error: error,
      cache: Req.Request.get_private(request, :http_cache, :uncached),
      rate_limit_wait: Req.Request.get_private(request, :http_rate_limit_wait, 0)
    }

    :telemetry.execute(@stop_event, %{duration: System.monotonic_time() - started_at}, metadata)
  end
end
