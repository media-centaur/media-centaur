defmodule MediaCentarr.Pipeline.Stage do
  @moduledoc """
  Telemetry-instrumented stage runner shared by Discovery and Import pipelines.

  Wraps each stage call with `:start`, `:stop`, and `:exception` telemetry events
  under `[:media_centarr, :pipeline, :stage, ...]`.
  """

  @spec run(atom(), module(), struct()) ::
          {:ok, struct()} | {:needs_review, struct()} | {:error, term()}
  def run(stage_name, stage_module, payload) do
    metadata = %{stage: stage_name, file_path: payload.file_path}

    :telemetry.execute(
      [:media_centarr, :pipeline, :stage, :start],
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
        [:media_centarr, :pipeline, :stage, :stop],
        %{duration: duration},
        stop_metadata
      )

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:media_centarr, :pipeline, :stage, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: Exception.message(exception)})
        )

        reraise exception, __STACKTRACE__
    end
  end
end
