defmodule MediaCentaur.Console.Handler do
  @moduledoc """
  Erlang `:logger` handler that funnels all log events into `MediaCentaur.Console.Buffer`.

  Installed once in `Application.start/2` via `:logger.add_handler/3`. Runs in the
  *caller's* process context for each log call, so it must be cheap and crash-free.

  The handler never broadcasts directly — it casts to the Buffer GenServer, which
  owns the PubSub broadcast. This avoids reentrancy if PubSub logs during broadcast.

  Entry construction (level normalization, component classification, message
  rendering, metadata pruning) lives in `Console.Entry.from_log_event/3` so the
  durable `ErrorReports.LogHandler` — an independent peer handler — builds
  entries identically. This handler owns only the volatile Buffer hand-off.
  """

  @behaviour :logger_handler

  alias MediaCentaur.Console.Entry

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    try do
      if meta[:mc_log_source] != :buffer do
        entry = Entry.from_log_event(level, msg, meta)
        MediaCentaur.Console.Buffer.append(entry)
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

  # --- Public for testing ---
  # Retained as a delegate: existing tests exercise build_entry/3 here. The
  # implementation now lives on the shared Console.Entry.from_log_event/3.
  @doc false
  @spec build_entry(atom(), term(), map()) :: Entry.t()
  defdelegate build_entry(level, msg, meta), to: Entry, as: :from_log_event
end
