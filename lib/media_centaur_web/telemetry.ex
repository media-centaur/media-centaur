defmodule MediaCentaurWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("media_centaur.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("media_centaur.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("media_centaur.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("media_centaur.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("media_centaur.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Pipeline Stage Metrics
      summary("media_centaur.pipeline.stage.stop.duration",
        tags: [:stage],
        unit: {:native, :millisecond},
        description: "Pipeline stage processing duration"
      ),
      counter("media_centaur.pipeline.stage.exception.duration",
        tags: [:stage],
        description: "Pipeline stage exceptions"
      ),

      # TMDB API Metrics
      summary("media_centaur.tmdb.request.stop.duration",
        tags: [:endpoint],
        unit: {:native, :millisecond},
        description: "TMDB API request duration"
      ),
      summary("media_centaur.tmdb.rate_limit_wait.duration",
        unit: {:native, :millisecond},
        description: "Time spent waiting for TMDB rate limiter"
      ),

      # Image Download Metrics
      summary("media_centaur.pipeline.image_download.stop.duration",
        tags: [:role],
        unit: {:native, :millisecond},
        description: "Image download duration per role"
      ),

      # Watcher Metrics
      summary("media_centaur.watcher.scan.stop.duration",
        unit: {:native, :millisecond},
        description: "Directory scan duration"
      ),

      # Periodic Gauges
      last_value("media_centaur.library.size.count",
        description: "Total entity count in the library"
      ),
      last_value("media_centaur.pipeline.queue.depth",
        description: "Current pipeline queue depth"
      )
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_library_size, []},
      {__MODULE__, :measure_pipeline_queue, []}
    ]
  end

  @doc false
  def measure_library_size do
    case Ash.count(MediaCentaur.Library.Entity) do
      {:ok, count} ->
        :telemetry.execute([:media_centaur, :library, :size], %{count: count})

      _ ->
        :ok
    end
  end

  @doc false
  def measure_pipeline_queue do
    snapshot = MediaCentaur.Pipeline.Stats.get_snapshot()
    :telemetry.execute([:media_centaur, :pipeline, :queue], %{depth: snapshot.queue_depth})
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
