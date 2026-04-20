defmodule MediaCentarr.Console do
  use Boundary,
    deps: [MediaCentarr.Settings, MediaCentarr.SelfUpdate],
    exports: [View, Filter, Buffer, Entry]

  @moduledoc """
  Bounded context for the in-browser log console: ring buffer, filter, rescan
  dispatch. All LiveViews and cross-context callers interact with the console
  through this module only — `Buffer` and `Handler` are internal.

  ## Persistence

  Console owns no database table. The filter state and buffer cap are
  persisted via `MediaCentarr.Settings.Entry`, the sanctioned ADR-029
  exception for shared key/value infrastructure (see the Bounded Contexts
  section of `CLAUDE.md`). No per-console table is justified.
  """

  alias MediaCentarr.Console.{Buffer, Entry, Filter, JournalSource, View}
  alias MediaCentarr.Topics

  # reads
  defdelegate snapshot(), to: Buffer
  defdelegate recent_entries(), to: Buffer, as: :recent
  defdelegate recent_entries(n), to: Buffer, as: :recent
  defdelegate get_filter(), to: Buffer
  defdelegate known_components(), to: View

  # writes
  defdelegate clear(), to: Buffer
  defdelegate resize(n), to: Buffer

  @doc "Updates the console filter. Persists asynchronously."
  @spec update_filter(Filter.t()) :: :ok
  def update_filter(%Filter{} = filter), do: Buffer.put_filter(filter)

  # pubsub helper
  @doc "Subscribe the caller to console log events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.console_logs())
  end

  # --- Systemd journal source ---
  #
  # A peer log source that tails `journalctl --user -u <unit> -f` via
  # `JournalSource`. Lifecycle is refcounted — journalctl is only running
  # while at least one subscriber is listening. See JournalSource docs.

  @doc "Subscribes the caller to the systemd journal tail. First subscriber spawns journalctl."
  @spec journal_subscribe() :: {:ok, [Entry.t()]} | {:error, :no_unit_detected}
  defdelegate journal_subscribe(), to: JournalSource, as: :subscribe

  @doc "Unsubscribes the caller. Port closes after a short debounce on refcount zero."
  @spec journal_unsubscribe() :: :ok
  defdelegate journal_unsubscribe(), to: JournalSource, as: :unsubscribe

  @doc "Force-respawns journalctl — the Reconnect button on the Systemd tab calls this."
  @spec journal_reconnect() :: :ok | {:error, :no_unit_detected | :no_subscribers}
  defdelegate journal_reconnect(), to: JournalSource, as: :reconnect

  @doc "True when a systemd unit has been detected — the Systemd tab only renders when true."
  @spec journal_available?() :: boolean()
  defdelegate journal_available?(), to: JournalSource, as: :available?

  @doc "Returns the current in-memory journal ring buffer (newest-last)."
  @spec journal_snapshot() :: [Entry.t()]
  defdelegate journal_snapshot(), to: JournalSource, as: :snapshot
end
