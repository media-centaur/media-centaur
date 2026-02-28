defmodule MediaCentaur.TMDB.RateLimiter do
  @moduledoc """
  Sliding window rate limiter for TMDB API requests.

  Enforces a maximum number of HTTP requests per time interval.
  The GenServer replies immediately — callers sleep on their own
  when rate-limited, so the mailbox is never blocked.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  @default_rate 30
  @default_interval 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Blocks until a request slot is available, then returns `:ok`.
  """
  def wait do
    case GenServer.call(__MODULE__, :acquire) do
      :ok ->
        :ok

      {:retry_after, ms} ->
        Log.info(:tmdb, "rate limited, waiting #{ms}ms")
        Process.sleep(ms)
        wait()
    end
  end

  @doc """
  Returns current rate limiter status for dashboard display.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(opts) do
    rate = opts[:rate] || @default_rate
    interval = opts[:interval] || @default_interval
    {:ok, %{rate: rate, interval: interval, timestamps: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, _from, state) do
    now = System.monotonic_time(:millisecond)
    timestamps = drop_expired(state.timestamps, now - state.interval)

    if :queue.len(timestamps) < state.rate do
      {:reply, :ok, %{state | timestamps: :queue.in(now, timestamps)}}
    else
      {{:value, oldest}, _} = :queue.out(timestamps)
      wait_ms = max(oldest + state.interval - now, 0)
      {:reply, {:retry_after, wait_ms}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    now = System.monotonic_time(:millisecond)
    timestamps = drop_expired(state.timestamps, now - state.interval)
    used = :queue.len(timestamps)

    {:reply, %{available: state.rate - used, total: state.rate, used: used}, state}
  end

  defp drop_expired(queue, cutoff) do
    case :queue.peek(queue) do
      {:value, ts} when ts < cutoff ->
        {_, queue} = :queue.out(queue)
        drop_expired(queue, cutoff)

      _ ->
        queue
    end
  end
end
