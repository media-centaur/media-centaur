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

  require MediaCentaur.Log, as: Log

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

  @doc false
  # Returns once the start-up enqueue has run (`handle_continue/2`).
  def __sync_for_test__(server \\ __MODULE__), do: GenServer.call(server, :sync)

  # No database write in `init/1`: the enqueue runs in `handle_continue/2`,
  # so a busy database at boot costs one logged miss, not the start.
  @impl true
  def init(_opts), do: {:ok, %{timer: nil}, {:continue, :start}}

  @impl true
  def handle_continue(:start, state) do
    enqueue_or_log()
    {:noreply, schedule(state)}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info(:refresh, state) do
    enqueue_or_log()
    {:noreply, schedule(state)}
  end

  defp enqueue_or_log do
    case enqueue() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Log.warning(:system, "could not enqueue the New Releases refresh: #{inspect(reason)}")
    end
  rescue
    error ->
      Log.warning(:system, "could not enqueue the New Releases refresh: #{Exception.message(error)}")
  end

  defp schedule(state) do
    delay = delay_until_next_run(DateTime.utc_now())
    %{state | timer: Process.send_after(self(), :refresh, delay)}
  end
end
