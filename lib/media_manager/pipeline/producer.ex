defmodule MediaManager.Pipeline.Producer do
  @moduledoc """
  GenStage producer that polls the database for detected files and claims
  them for processing by the Broadway pipeline.
  """
  use GenStage
  require Logger

  alias MediaManager.Library.WatchedFile

  @poll_interval 1_000

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    poll_interval = opts[:poll_interval] || @poll_interval
    schedule_poll(poll_interval)
    {:producer, %{poll_interval: poll_interval, demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    {:noreply, [], %{state | demand: state.demand + incoming_demand}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll(state.poll_interval)

    if state.demand > 0 do
      files = claim_detected_files(state.demand)

      messages =
        Enum.map(files, fn file ->
          %Broadway.Message{data: file, acknowledger: {__MODULE__, :ack_id, :ack_data}}
        end)

      {:noreply, messages, %{state | demand: state.demand - length(messages)}}
    else
      {:noreply, [], state}
    end
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  defp claim_detected_files(limit) do
    query = Ash.Query.for_read(WatchedFile, :detected_files, %{limit: limit})

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
        Logger.warning("Pipeline producer: failed to read detected files: #{inspect(reason)}")
        []
    end
  end

  defp schedule_poll(interval), do: Process.send_after(self(), :poll, interval)
end
