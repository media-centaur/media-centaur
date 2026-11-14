defmodule MediaCentaur.Library.TitleProgress do
  @moduledoc """
  Where a profile stands in a title: the derived reading every "where am
  I" surface shows — Play and its label, the bars, Continue Watching, the
  detail page's scroll. Never stored.

  ## The rule

  Given the title's ordered set, the profile's
  `MediaCentaur.Library.SeriesWatchPosition` (nil for a single-item title
  or a series nothing was finished in) and its item progress rows:

    1. A viewing in flight that counts
       (`MediaCentaur.Library.ProgressRecords.viewing?/1`) and is newer
       than the position — or there is no position — is resumed. With
       several, the newest.
    2. Otherwise, with a position, next is the first item whose order key
       is after it. None: complete.
    3. Otherwise next is the first item with no watched mark. None:
       complete.

  Next starts at its own viewing's offset when it has one that counts,
  else from the start.

  Play therefore continues from the last item playback finished. Watched
  marks are a checklist: they decide next only where nothing has been
  finished by playback (step 3).

  ## The state

  `:complete` when there is no next; `:unstarted` when there is no
  position, no watched mark and no viewing that counts; otherwise
  `:in_progress`.

  ## What follows from the rule

    * A rewatch continues: with every item marked, next is the item after
      the position, and the title is in progress until the position
      reaches the final item.
    * Finishing an earlier item again moves next to the item after it.
    * An item skipped over is not returned to; the title is complete when
      the position reaches the final item, whatever is unmarked.
    * The position stores an order key, so deleting finished items does
      not move next. `before_next` and `total` count the items in the
      ordered set — those with a file — so with finished items deleted the
      measure reads near the start of what remains.
    * A viewing older than the position is not resumed by step 1, but it
      still gives next its offset when next reaches that item.
    * A single-item title has no position: it is in progress while its
      row has a viewing that counts, and complete when it is marked and
      has none.

  ## Readers

  Callers do not assemble the inputs. One title:
  `MediaCentaur.Library.ProgressRecords.title_progress/2`. Many:
  `title_progresses/2` and `title_progresses_by_kind/2`. Both read the
  item rows at the live offset of a session in flight.
  """

  alias MediaCentaur.Library.{EpisodeOrder, MovieOrder, ProgressRecords}

  @enforce_keys [:state, :before_next, :total]
  defstruct [:state, :next, :before_next, :total, :last_watched_at]

  @type item :: %{id: Ecto.UUID.t(), key: [String.t()]}
  @type next :: %{item_id: Ecto.UUID.t(), offset_seconds: float(), duration_seconds: float()}
  @type t :: %__MODULE__{
          state: :unstarted | :in_progress | :complete,
          next: next() | nil,
          before_next: non_neg_integer(),
          total: non_neg_integer(),
          last_watched_at: DateTime.t() | nil
        }

  @doc """
  The ordered set of an entity view: a series' or collection's items with
  a file, or the single item of a leaf title.
  """
  @spec ordered_set(map()) :: [item()]
  def ordered_set(%{type: :tv_series} = entity), do: EpisodeOrder.ordered_items(entity)
  def ordered_set(%{type: :movie_series} = entity), do: MovieOrder.ordered_items(entity)
  def ordered_set(%{id: id, content_url: url}) when is_binary(url), do: [%{id: id, key: []}]
  def ordered_set(_entity), do: []

  @doc "The title progress of an entity view; see `compute/3`."
  @spec for_entity(map(), map() | nil, [map()]) :: t()
  def for_entity(entity, position, rows), do: compute(ordered_set(entity), position, rows)

  @doc "Applies the rule. Rows for items outside `items` are ignored."
  @spec compute([item()], map() | nil, [map()]) :: t()
  def compute([], _position, _rows),
    do: %__MODULE__{state: :unstarted, next: nil, before_next: 0, total: 0}

  def compute(items, position, rows) do
    rows_by_id = rows_by_item_id(items, rows)
    viewings = resumable_viewings(items, position, rows_by_id)
    next_item = next_item(items, position, rows_by_id, viewings)

    %__MODULE__{
      state: state(next_item, position, rows_by_id),
      next: next_item && next(next_item, rows_by_id),
      before_next: before_next(items, next_item),
      total: length(items),
      last_watched_at: last_watched_at(position, viewings)
    }
  end

  @doc """
  The one measure every bar shows, 0..100: place in the ordered set plus
  the fraction of next already viewed.
  """
  @spec percent(t() | nil) :: 0..100
  def percent(nil), do: 0
  def percent(%__MODULE__{total: 0}), do: 0
  def percent(%__MODULE__{state: :complete}), do: 100

  def percent(%__MODULE__{next: next, before_next: before_next, total: total}) do
    min(trunc((before_next + viewed_fraction(next)) / total * 100), 100)
  end

  defp viewed_fraction(%{duration_seconds: duration, offset_seconds: offset}) when duration > 0,
    do: min(1.0, offset / duration)

  defp viewed_fraction(_next), do: 0.0

  defp rows_by_item_id(items, rows) do
    ids = MapSet.new(items, & &1.id)

    for row <- rows,
        id = ProgressRecords.progress_container_id(row),
        MapSet.member?(ids, id),
        into: %{},
        do: {id, row}
  end

  # `{item, row}` for every viewing step 1 may resume, newest first.
  defp resumable_viewings(items, position, rows_by_id) do
    viewings =
      for item <- items,
          row = rows_by_id[item.id],
          ProgressRecords.viewing?(row),
          newer?(row, position),
          do: {item, row}

    Enum.sort_by(viewings, fn {_item, row} -> row.last_watched_at end, &newest_first?/2)
  end

  defp newer?(_row, nil), do: true
  defp newer?(%{last_watched_at: nil}, _position), do: false
  defp newer?(row, position), do: DateTime.after?(row.last_watched_at, position.finished_at)

  # A viewing with no timestamp is the oldest.
  defp newest_first?(_first, nil), do: true
  defp newest_first?(nil, _second), do: false
  defp newest_first?(first, second), do: DateTime.compare(first, second) != :lt

  defp next_item(_items, _position, _rows_by_id, [{item, _row} | _older]), do: item

  defp next_item(items, %{order_key: key}, _rows_by_id, []), do: Enum.find(items, &(&1.key > key))

  defp next_item(items, nil, rows_by_id, []), do: Enum.find(items, &(not marked?(rows_by_id[&1.id])))

  defp marked?(%{completed: true}), do: true
  defp marked?(_row), do: false

  defp state(nil, _position, _rows_by_id), do: :complete

  defp state(_next_item, nil, rows_by_id) do
    started? =
      Enum.any?(rows_by_id, fn {_id, row} -> marked?(row) or ProgressRecords.viewing?(row) end)

    if started?, do: :in_progress, else: :unstarted
  end

  defp state(_next_item, _position, _rows_by_id), do: :in_progress

  defp next(item, rows_by_id) do
    row = rows_by_id[item.id]

    %{
      item_id: item.id,
      offset_seconds: if(ProgressRecords.viewing?(row), do: row.position_seconds / 1, else: 0.0),
      duration_seconds: ((row && row.duration_seconds) || 0.0) / 1
    }
  end

  defp before_next(items, nil), do: length(items)
  defp before_next(items, item), do: Enum.find_index(items, &(&1.id == item.id))

  defp last_watched_at(position, viewings) do
    [position && position.finished_at | Enum.map(viewings, fn {_item, row} -> row.last_watched_at end)]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end
end
