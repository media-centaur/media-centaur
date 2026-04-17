defmodule MediaCentarr.Console do
  use Boundary, deps: [MediaCentarr.Settings], exports: [View, Filter, Buffer, Entry]

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
end
