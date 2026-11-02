defmodule MediaCentaur.NewReleases.Scheduler do
  @moduledoc """
  The Discovery feature's runtime child (ADR-081, `Features.Runtime`): the
  New Releases shelf's schedule, alive only while the flag is on. It
  enqueues one `RefreshJob` when it starts — at boot or at turn-on, so the
  shelf fills then — and one every day at #{"04:03"} UTC after that, the
  hour the retention sweep follows. Nothing of the shelf's is wired into
  Oban's cron: with the feature off, no job is inserted at all (the job
  itself still asks the flag, for a run already waiting when the flag
  flipped). The job is unique across available, scheduled and executing,
  so a start beside a scheduled run, or beside a snoozing one, is one run.
  """
  use GenServer

  alias MediaCentaur.NewReleases.RefreshJob

  @refresh_at ~T[04:03:00]

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Enqueues one refresh; a second call while one waits is a no-op."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> RefreshJob.new() |> Oban.insert()

  @doc """
  Milliseconds from `now` to the next #{"04:03"} UTC — later today when it
  is still ahead, else tomorrow's.
  """
  @spec delay_until_next_run(DateTime.t()) :: pos_integer()
  def delay_until_next_run(%DateTime{} = now) do
    today = DateTime.new!(DateTime.to_date(now), @refresh_at, "Etc/UTC")

    next =
      if DateTime.after?(today, now),
        do: today,
        else: DateTime.add(today, 1, :day)

    DateTime.diff(next, now, :millisecond)
  end

  @impl true
  def init(_opts) do
    _ = enqueue()
    {:ok, schedule(%{timer: nil})}
  end

  @impl true
  def handle_info(:refresh, state) do
    _ = enqueue()
    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    delay = delay_until_next_run(DateTime.utc_now())
    %{state | timer: Process.send_after(self(), :refresh, delay)}
  end
end
