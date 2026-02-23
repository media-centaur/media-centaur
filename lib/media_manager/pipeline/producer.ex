defmodule MediaManager.Pipeline.Producer do
  @moduledoc """
  GenStage producer that polls the database for detected files and claims
  them for processing by the Broadway pipeline.

  On init, reclaims files stuck in `:queued` state from a previous crash
  (older than 5 minutes) by including them in the claimable query.
  """
  use GenStage
  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Library.WatchedFile

  @poll_interval 2_000
  @stale_threshold_minutes 5

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    {:producer, %{demand: 0, poll_scheduled: false}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    state = ensure_poll_scheduled(state)
    {:noreply, [], state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = %{state | poll_scheduled: false}

    if state.demand > 0 do
      files = claim_files(state.demand)

      if files != [] do
        Log.info(:pipeline, "producer claimed #{length(files)} files (demand: #{state.demand})")
      end

      messages =
        Enum.map(files, fn file ->
          %Broadway.Message{data: file, acknowledger: {__MODULE__, :ack_id, :ack_data}}
        end)

      state = %{state | demand: state.demand - length(messages)}
      state = schedule_poll(state, @poll_interval)

      {:noreply, messages, state}
    else
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
      {:ok, []} ->
        []

      {:ok, files} ->
        result =
          Ash.bulk_update(files, :claim, %{},
            strategy: :stream,
            return_records?: true,
            return_errors?: true
          )

        if result.error_count > 0 do
          Logger.warning(
            "Pipeline producer: #{result.error_count} claim errors: #{inspect(Enum.take(result.errors, 3))}"
          )
        end

        claimed = result.records || []

        if claimed != [] do
          Phoenix.PubSub.broadcast(MediaManager.PubSub, "pipeline:updates", :pipeline_changed)
        end

        claimed

      {:error, reason} ->
        Logger.warning("Pipeline producer: failed to read claimable files: #{inspect(reason)}")
        []
    end
  end

  defp ensure_poll_scheduled(%{poll_scheduled: true} = state), do: state

  defp ensure_poll_scheduled(state), do: schedule_poll(state, 0)

  defp schedule_poll(state, interval) do
    Process.send_after(self(), :poll, interval)
    %{state | poll_scheduled: true}
  end
end
