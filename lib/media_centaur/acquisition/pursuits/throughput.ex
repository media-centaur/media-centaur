defmodule MediaCentaur.Acquisition.Pursuits.Throughput do
  @moduledoc """
  Lifetime pursuit-outcome aggregate for the Downloads status tile: how many
  acquisitions have succeeded, failed, and are in flight, plus a success rate.
  Pure read-shaping over `acquisition_pursuits` — one grouped count, folded
  through `State.bucket/1`. `StatusLive` calls `stats/0` on mount and on
  acquisition refresh; `empty/0` serves the disconnected mount.

  ## Shape

      %{acquired: non_neg_integer(), failed: non_neg_integer(),
        active: non_neg_integer(), success_rate: 0..100 | nil}

  `success_rate` is `nil` when no pursuit has reached a terminal state.
  """
  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Repo

  @spec empty() :: map()
  def empty, do: %{acquired: 0, failed: 0, active: 0, success_rate: nil}

  @spec stats() :: map()
  def stats do
    counts =
      from(p in "acquisition_pursuits", group_by: p.state, select: {p.state, count(p.id)})
      |> Repo.all()
      |> Enum.reduce(%{acquired: 0, failed: 0, active: 0}, fn {state, n}, acc ->
        case State.bucket(state) do
          :terminal_success -> %{acc | acquired: acc.acquired + n}
          :terminal_failure -> %{acc | failed: acc.failed + n}
          :in_flight -> %{acc | active: acc.active + n}
        end
      end)

    Map.put(counts, :success_rate, success_rate(counts.acquired, counts.failed))
  end

  defp success_rate(0, 0), do: nil
  defp success_rate(acquired, failed), do: round(100 * acquired / (acquired + failed))
end
