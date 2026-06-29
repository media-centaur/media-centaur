defmodule MediaCentaur.ErrorReports.LogHandler do
  @moduledoc """
  An independent Erlang `:logger` handler that feeds the durable diagnostics
  path — a **peer** of `Console.Handler`, never downstream of it.

  Both handlers are attached to `:logger` directly, so they receive every log
  event independently. This one keeps `warning`/`error`-tier events, builds an
  `%Console.Entry{}` via the shared `Console.Entry.from_log_event/3`, and casts
  it to `Buckets` (which persists + caches). Because it hangs off the logger
  rather than off `Console.Buffer`'s PubSub broadcast, durable capture survives
  a crashed or backed-up Console buffer — the independence the observability
  subsystem requires.

  Runs in the caller's process per log call, so it stays cheap and crash-free:
  it only builds an entry and casts (the DB write happens later, in `Buckets`).
  The `mc_log_source: :buffer` guard drops the Buffer's own self-logs; the
  `mc_incident: :skip` guard drops logs whose incident a subsystem `assess/0`
  already owns (ADR-054 — they stay in the console but must not mint a duplicate
  `:log` incident); the level guard is belt-and-suspenders behind the
  `level: :warning` filter configured at install time.

  The target `Buckets` server is read from the handler config (`config.buckets`),
  defaulting to the named global — which lets tests drive `log/2` against an
  isolated `Buckets` instance.
  """
  @behaviour :logger_handler

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Buckets

  # Raw `:logger` levels that normalize to `:warning`/`:error` (see
  # `Console.Entry.from_log_event/3`). `:notice`/`:info`/`:debug` are excluded.
  @captured_levels [:warning, :warn, :error, :critical, :alert, :emergency]

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, config) do
    try do
      if meta[:mc_log_source] != :buffer and meta[:mc_incident] != :skip and
           level in @captured_levels and not transport_disconnect?(meta) and
           not req_retry?(meta) do
        entry = Entry.from_log_event(level, msg, meta)
        Buckets.ingest(buckets_target(config), entry)
      end
    catch
      _kind, _reason -> :ok
    end

    :ok
  end

  # A `Bandit.TransportError` with a client-gone reason (`:timeout` = the client
  # stopped reading/writing; `:closed` = it dropped the socket) is web-server
  # connection lifecycle, not an application fault — so it must not mint a `:log`
  # incident. Matched by Bandit's typed `crash_reason` metadata (not message
  # text). The line still reaches the console via the peer `Console.Handler`;
  # this only keeps it out of the durable/incident path. Any *other* transport
  # reason (e.g. `:emfile`) still mints, so a genuinely unusual socket condition
  # isn't hidden.
  defp transport_disconnect?(%{crash_reason: {%Bandit.TransportError{error: reason}, _stacktrace}})
       when reason in [:timeout, :closed], do: true

  # The HTTP-layer twin: Bandit raises `%Bandit.HTTPError{plug_status:
  # :request_timeout}` ("Read timeout") when a client opens a connection and
  # then stalls mid-request. Same client-gone family as the transport timeout
  # above. Other HTTPError statuses (e.g. `:bad_request`) still mint.
  defp transport_disconnect?(%{
         crash_reason: {%Bandit.HTTPError{plug_status: :request_timeout}, _stacktrace}
       }), do: true

  defp transport_disconnect?(_meta), do: false

  # Req logs every retry attempt from `Req.Steps.log_retry/5` — the caught
  # exception ("** (Req.HTTPError) http2 error: :pool_not_available") plus a
  # "will retry in N, attempts left" line. A retry-in-progress is transient by
  # definition: Req is recovering on its own, and if it ultimately gives up the
  # *caller* logs a terminal error (e.g. "plan search failed") that mints a real
  # incident. Minting on the intermediate retry lines produces false-positive
  # `:log` incidents that self-heal but then sit "open" until the next deploy
  # (the `:log` track has no recovery signal). The lines still reach the console
  # via the peer `Console.Handler`; this only keeps them off the durable path.
  defp req_retry?(%{mfa: {Req.Steps, :log_retry, _arity}}), do: true
  defp req_retry?(_meta), do: false

  # :logger handler lifecycle callbacks
  @doc false
  def adding_handler(config), do: {:ok, config}

  @doc false
  def removing_handler(_config), do: :ok

  @doc false
  def changing_config(_op, _old, new), do: {:ok, new}

  defp buckets_target(config) when is_map(config) do
    case config do
      %{config: %{buckets: name}} when not is_nil(name) -> name
      _ -> Buckets
    end
  end

  defp buckets_target(_), do: Buckets
end
