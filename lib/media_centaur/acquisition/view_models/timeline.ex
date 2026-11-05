defmodule MediaCentaur.Acquisition.ViewModels.Timeline do
  @moduledoc """
  Display contract for History: a pursuit's events as runs, newest first.

  Built by `build/3` from the persisted events and a `Resolver`
  (`Pursuits.detail_for/1` hands both over). Consecutive entries that read
  the same fold into one `Run`; the newest `@recent` runs are `recent`,
  always drawn; everything older is `rest`, drawn behind a disclosure a
  page at a time (`page/0`), so the DOM holds a bounded number of rows
  however long the history is. Pure — no DB, no I/O.
  """

  alias MediaCentaur.Acquisition.Pursuits.Event
  alias MediaCentaur.Acquisition.ViewModels.Timeline.{Resolver, Run}
  alias MediaCentaur.Acquisition.ViewModels.TimelineEntry

  @recent 6
  @page 50

  @enforce_keys [:pursuit_id]
  defstruct [:pursuit_id, total_events: 0, total_runs: 0, recent: [], rest: []]

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          total_events: non_neg_integer(),
          total_runs: non_neg_integer(),
          recent: [Run.t()],
          rest: [Run.t()]
        }

  @doc "How many older runs one Show more reveals."
  @spec page() :: pos_integer()
  def page, do: @page

  @doc "Builds the timeline from events (any order) and the window's resolver."
  @spec build(Ecto.UUID.t(), [Event.t()], Resolver.t()) :: t()
  def build(pursuit_id, events, %Resolver{} = resolver) when is_list(events) do
    # Newest first; within one second, by kind — a sweep writes "abandoned,
    # switched, abandoned, switched" for three episodes in the same second,
    # and the order inside that second carries nothing, so the three
    # abandonments read as one row rather than six alternating ones.
    runs =
      events
      |> Enum.sort_by(&{-DateTime.to_unix(&1.occurred_at), &1.kind})
      |> Enum.map(&TimelineEntry.from_event(&1, resolver))
      |> Enum.chunk_by(&Run.key/1)
      |> Enum.map(&Run.from_entries/1)

    {recent, rest} = Enum.split(runs, @recent)

    %__MODULE__{
      pursuit_id: pursuit_id,
      total_events: length(events),
      total_runs: length(runs),
      recent: recent,
      rest: rest
    }
  end
end
