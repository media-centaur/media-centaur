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
           level in @captured_levels do
        entry = Entry.from_log_event(level, msg, meta)
        Buckets.ingest(buckets_target(config), entry)
      end
    catch
      _kind, _reason -> :ok
    end

    :ok
  end

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
