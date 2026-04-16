defmodule MediaCentarr.Console do
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

  alias MediaCentarr.Console.{Buffer, Filter, View}
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

  # commands
  @doc """
  Dispatch a library rescan via the Watcher context. Non-blocking — the actual
  scan runs in a supervised task so the caller (typically a LiveView event
  handler) returns immediately.

  Any logs emitted by the scan will flow through the console buffer via the
  logger handler, providing closed-loop feedback to the user.
  """
  @spec rescan_library() :: :ok
  def rescan_library do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      MediaCentarr.Watcher.Supervisor.scan()
    end)

    :ok
  end
end
