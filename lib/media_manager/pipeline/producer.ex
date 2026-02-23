defmodule MediaManager.Pipeline.Producer do
  @moduledoc """
  GenStage producer that polls the database for detected files and claims
  them for processing by the Broadway pipeline.

  On init, reclaims files stuck in `:queued` state from a previous crash
  (older than 5 minutes) by including them in the claimable query.
  """
  use GenStage
  require Logger

  alias MediaManager.Library.WatchedFile

  @idle_interval 20_000
  @active_interval 1_000
  @stale_threshold_minutes 5

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    poll_interval = opts[:poll_interval] || @idle_interval
    schedule_poll(poll_interval)
    {:producer, %{poll_interval: poll_interval, demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    {:noreply, [], %{state | demand: state.demand + incoming_demand}}
  end

  @impl true
  def handle_info(:poll, state) do
    if state.demand > 0 do
      files = claim_files(state.demand)

      messages =
        Enum.map(files, fn file ->
          %Broadway.Message{data: file, acknowledger: {__MODULE__, :ack_id, :ack_data}}
        end)

      next_interval = if files != [], do: @active_interval, else: @idle_interval
      schedule_poll(next_interval)

      {:noreply, messages,
       %{state | demand: state.demand - length(messages), poll_interval: next_interval}}
    else
      schedule_poll(state.poll_interval)
      {:noreply, [], state}
    end
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  defp claim_files(limit) do
    stale_threshold =
      DateTime.utc_now() |> DateTime.add(-@stale_threshold_minutes, :minute)

    query =
      Ash.Query.for_read(WatchedFile, :claimable_files, %{
        limit: limit,
        stale_threshold: stale_threshold
      })

    case Ash.read(query) do
      {:ok, files} ->
        files
        |> Enum.reduce([], fn file, claimed ->
          case Ash.update(file, %{}, action: :claim) do
            {:ok, claimed_file} -> [claimed_file | claimed]
            {:error, _} -> claimed
          end
        end)
        |> Enum.reverse()

      {:error, reason} ->
        Logger.warning("Pipeline producer: failed to read claimable files: #{inspect(reason)}")
        []
    end
  end

  defp schedule_poll(interval), do: Process.send_after(self(), :poll, interval)
end
