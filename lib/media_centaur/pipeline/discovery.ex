defmodule MediaCentaur.Pipeline.Discovery do
  @moduledoc """
  Broadway pipeline that identifies what a file is — parses the filename,
  searches TMDB, and determines if it's a match or needs review.

  Processing flow: dedup check → parse → search.
  High-confidence matches emit `{:file_matched, ...}` to `"pipeline:matched"`.
  Low-confidence matches stop at needs_review for human approval.

  Broadway config: 1 producer (PubSub subscriber), 10 processors (partitioned
  by file path), 1 batcher (serialises match broadcasts, batch size 10,
  timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Pipeline.{Payload, Stage}
  alias MediaCentaur.Pipeline.Stages.{Parse, Search}
  alias MediaCentaur.Review.Intake

  @processor_concurrency 10

  def processor_concurrency, do: @processor_concurrency

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentaur.Pipeline.Discovery.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: @processor_concurrency, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    payload = message.data
    Log.info(:pipeline, "discovery — processing #{Path.basename(payload.file_path)}")

    case process(payload) do
      {:matched, payload} ->
        Log.info(:pipeline, "discovery — matched #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      :skipped ->
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:needs_review, payload} ->
        Log.info(:pipeline, "discovery — needs review #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:error, reason} ->
        Log.warning(
          :pipeline,
          "discovery — failed for #{Path.basename(payload.file_path)}: #{inspect(reason)}"
        )

        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    matched =
      Enum.filter(messages, fn message ->
        message.data.tmdb_id != nil and message.data.confidence != nil
      end)

    Enum.each(matched, fn message ->
      payload = message.data

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.pipeline_matched(),
        {:file_matched,
         %{
           file_path: payload.file_path,
           watch_dir: payload.watch_directory,
           tmdb_id: payload.tmdb_id,
           tmdb_type: payload.tmdb_type,
           pending_file_id: nil
         }}
      )
    end)

    if matched != [] do
      Log.info(:pipeline, "discovery — broadcast #{length(matched)} matches")
    end

    messages
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc """
  Processes a single payload through the Discovery pipeline.

  Returns:
  - `{:matched, payload}` — high-confidence TMDB match found
  - `{:needs_review, payload}` — low confidence or no results
  - `:skipped` — file already linked to an entity
  - `{:error, reason}` — TMDB failure or parse error
  """
  def process(%Payload{} = payload) do
    if already_linked?(payload.file_path) do
      Log.info(:pipeline, "skipped #{Path.basename(payload.file_path)} — already linked")
      :skipped
    else
      case run_discovery(payload) do
        {:ok, payload} -> {:matched, payload}
        {:needs_review, payload} -> handle_needs_review(payload)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp run_discovery(payload) do
    with {:ok, payload} <- Stage.run(:parse, Parse, payload),
         result <- Stage.run(:search, Search, payload) do
      result
    end
  end

  defp handle_needs_review(payload) do
    :telemetry.execute([:media_centaur, :pipeline, :needs_review], %{}, %{
      file_path: payload.file_path
    })

    case Intake.create_from_payload(payload) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Log.warning(:pipeline, "failed to create pending file — #{inspect(reason)}")
    end

    {:needs_review, payload}
  end

  defp already_linked?(file_path) do
    case Library.list_files_by_paths!([file_path]) do
      [%{entity_id: entity_id}] when not is_nil(entity_id) -> true
      _ -> false
    end
  end
end
