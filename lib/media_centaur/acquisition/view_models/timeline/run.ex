defmodule MediaCentaur.Acquisition.ViewModels.Timeline.Run do
  @moduledoc """
  One row of History: a run of consecutive events that read the same —
  one kind, one summary, one detail — drawn once with its count and span.
  Three releases abandoned in the same sweep are one row, "×3"; the
  Sample Title Eo case folds 971 events into about three hundred rows.

  `entry` is the newest member's `TimelineEntry`; `first_at`/`last_at` span
  the run (oldest to newest); `subjects` are the episode labels the
  members named, in first-seen order, without repeats; `release` is the
  one release every member named, nil when they named none or several
  (three abandonments of three releases carry no single release line).
  """

  alias MediaCentaur.Acquisition.ViewModels.TimelineEntry

  @enforce_keys [:entry, :count, :first_at, :last_at]
  defstruct [:entry, :count, :first_at, :last_at, :release, subjects: []]

  @type t :: %__MODULE__{
          entry: TimelineEntry.t(),
          count: pos_integer(),
          first_at: DateTime.t(),
          last_at: DateTime.t(),
          subjects: [String.t()],
          release: String.t() | nil
        }

  @doc "Folds a newest-first list of entries that share a key into one run."
  @spec from_entries([TimelineEntry.t(), ...]) :: t()
  def from_entries([newest | _] = entries) do
    %__MODULE__{
      entry: newest,
      count: length(entries),
      first_at: List.last(entries).occurred_at,
      last_at: newest.occurred_at,
      subjects: entries |> Enum.flat_map(& &1.subjects) |> Enum.uniq(),
      release: shared_release(entries)
    }
  end

  defp shared_release(entries) do
    entries
    |> Enum.map(& &1.release)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [release] -> release
      _none_or_several -> nil
    end
  end

  @doc "The key two entries must share to fold into one run."
  @spec key(TimelineEntry.t()) :: {String.t(), String.t(), String.t() | nil}
  def key(%TimelineEntry{kind: kind, summary: summary, detail: detail}), do: {kind, summary, detail}
end
