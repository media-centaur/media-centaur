defmodule MediaCentaur.Pipeline do
  @moduledoc """
  Broadway pipeline that processes video files through search,
  metadata fetch, and image download stages.

  Processing flow: parse → search → fetch_metadata → ingest.
  Low-confidence matches stop at needs_review for human approval.

  The Producer delivers `%Payload{}` structs via PubSub events. This module
  processes them and creates WatchedFile records (`:link_file`) on completion
  or PendingFile records on needs_review.

  Broadway config: 1 producer (PubSub subscriber), 15 processors (partitioned
  by file path), 1 batcher (serialises PubSub broadcasts, batch size 10,
  timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.Payload

  alias MediaCentaur.Pipeline.Stages.{
    Parse,
    Search,
    FetchMetadata,
    Ingest
  }

  alias MediaCentaur.Review
  alias MediaCentaur.Review.Intake
  alias MediaCentaur.Storage

  @processor_concurrency 15
  @min_disk_bytes 100 * 1024 * 1024

  def processor_concurrency, do: @processor_concurrency

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentaur.Pipeline.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: @processor_concurrency, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    payload = message.data
    Log.info(:pipeline, "processing #{Path.basename(payload.file_path)}")

    case process_payload(payload) do
      {:ok, payload} ->
        Log.info(:pipeline, "completed #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:error, reason} ->
        Log.warning(
          :pipeline,
          "failed for #{Path.basename(payload.file_path)}: #{inspect(reason)}"
        )

        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    completed =
      Enum.filter(messages, fn message ->
        message.data.entity_id != nil and message.data.watch_directory != nil
      end)

    entity_ids =
      completed
      |> Enum.map(fn message -> message.data.entity_id end)
      |> Enum.uniq()

    if entity_ids != [] do
      Log.info(:pipeline, "batch complete, broadcasting #{length(entity_ids)} entity changes")
      Helpers.broadcast_entities_changed(entity_ids)
    end

    # Trigger image pipeline for entities that need images
    completed
    |> Enum.uniq_by(fn message -> message.data.entity_id end)
    |> Enum.each(fn message ->
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        "pipeline:images",
        {:images_pending,
         %{entity_id: message.data.entity_id, watch_dir: message.data.watch_directory}}
      )
    end)

    messages
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc false
  def process_payload(%Payload{entry_point: :file_detected} = payload) do
    if already_linked?(payload.file_path) do
      Log.info(:pipeline, "skipping already-linked file: #{Path.basename(payload.file_path)}")
      {:ok, payload}
    else
      case run_pipeline(payload) do
        {:ok, payload} -> handle_complete(payload)
        {:needs_review, payload} -> handle_needs_review(payload)
        {:error, reason} -> handle_error(payload, reason)
      end
    end
  end

  def process_payload(%Payload{entry_point: :review_resolved} = payload) do
    payload = %{payload | parsed: Parser.parse(payload.file_path)}

    case run_post_search(payload) do
      {:ok, payload} -> handle_complete(payload)
      {:error, reason} -> handle_error(payload, reason)
    end
  end

  defp run_pipeline(payload) do
    with {:ok, payload} <- run_stage(:parse, Parse, payload),
         result <- run_stage(:search, Search, payload) do
      case result do
        {:ok, payload} -> run_post_search(payload)
        {:needs_review, _} = needs_review -> needs_review
        {:error, _} = error -> error
      end
    end
  end

  defp run_post_search(payload) do
    with :ok <- check_disk_space(payload.watch_directory),
         {:ok, payload} <- run_stage(:fetch_metadata, FetchMetadata, payload) do
      run_stage(:ingest, Ingest, payload)
    end
  end

  defp check_disk_space(watch_directory) do
    images_dir = MediaCentaur.Config.images_dir_for(watch_directory)
    # df works on parent even if images_dir doesn't exist yet
    path = if File.dir?(images_dir), do: images_dir, else: watch_directory

    case Storage.available_bytes(path) do
      {:ok, avail} when avail < @min_disk_bytes ->
        Log.warning(
          :pipeline,
          "insufficient disk space: #{div(avail, 1_048_576)} MB available"
        )

        {:error, :insufficient_disk_space}

      _ ->
        :ok
    end
  end

  defp run_stage(stage_name, stage_module, payload) do
    metadata = %{stage: stage_name, file_path: payload.file_path}

    :telemetry.execute(
      [:media_centaur, :pipeline, :stage, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time = System.monotonic_time()

    try do
      result = stage_module.run(payload)

      duration = System.monotonic_time() - start_time

      stop_metadata =
        case result do
          {:ok, _} -> Map.put(metadata, :result, :ok)
          {:needs_review, _} -> Map.put(metadata, :result, :needs_review)
          {:error, reason} -> Map.merge(metadata, %{result: :error, error_reason: reason})
        end

      :telemetry.execute(
        [:media_centaur, :pipeline, :stage, :stop],
        %{duration: duration},
        stop_metadata
      )

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:media_centaur, :pipeline, :stage, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: Exception.message(exception)})
        )

        reraise exception, __STACKTRACE__
    end
  end

  defp handle_complete(payload) do
    Library.link_file!(%{
      file_path: payload.file_path,
      watch_dir: payload.watch_directory,
      entity_id: payload.entity_id
    })

    if payload.pending_file_id do
      case Review.get_pending_file(payload.pending_file_id) do
        {:ok, pending_file} ->
          Review.destroy_pending_file!(pending_file)

          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            "review:updates",
            {:file_reviewed, payload.pending_file_id}
          )

        {:error, _} ->
          :ok
      end
    end

    {:ok, payload}
  end

  defp handle_needs_review(payload) do
    :telemetry.execute([:media_centaur, :pipeline, :needs_review], %{}, %{
      file_path: payload.file_path
    })

    case Intake.create_from_payload(payload) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Log.warning(:pipeline, "failed to create pending file: #{inspect(reason)}")
    end

    {:ok, payload}
  end

  defp handle_error(_payload, reason) do
    {:error, reason}
  end

  defp already_linked?(file_path) do
    case Library.list_files_by_paths!([file_path]) do
      [%{entity_id: entity_id}] when not is_nil(entity_id) -> true
      _ -> false
    end
  end
end
