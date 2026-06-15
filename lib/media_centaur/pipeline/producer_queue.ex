defmodule MediaCentaur.Pipeline.ProducerQueue do
  @moduledoc """
  Shared demand-driven queue mechanics for the pipeline's GenStage
  producers (Discovery, Import, Image). Each producer keeps its own
  `dispatch/1` and telemetry (they differ — the image pipeline emits a
  distinct metric), but the `:queue` draining and Broadway-message
  wrapping are identical and live here.
  """

  @doc """
  Pulls up to `demand` items off the front of `queue`, returning
  `{items, remaining_queue, remaining_demand}`.
  """
  @spec dequeue(:queue.queue(), non_neg_integer(), list()) :: {list(), :queue.queue(), non_neg_integer()}
  def dequeue(queue, demand, acc \\ [])

  def dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue, 0}

  def dequeue(queue, remaining, acc) do
    case :queue.out(queue) do
      {{:value, item}, queue} -> dequeue(queue, remaining - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue, remaining}
    end
  end

  @doc "Wraps payloads as Broadway messages acknowledged by `ack_module`."
  @spec to_messages([term()], module()) :: [Broadway.Message.t()]
  def to_messages(payloads, ack_module) do
    Enum.map(payloads, fn payload ->
      %Broadway.Message{data: payload, acknowledger: {ack_module, :ack_id, :ack_data}}
    end)
  end
end
