defmodule MediaManager.TMDB.RateLimiter do
  @moduledoc """
  Sliding window rate limiter for TMDB API requests.

  Enforces a maximum number of HTTP requests per time interval.
  Callers block until a slot is available, ensuring we stay within
  TMDB's rate limits even under high concurrency.
  """
  use GenServer

  @default_rate 30
  @default_interval 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Blocks until a request slot is available, then returns `:ok`.
  """
  def wait do
    GenServer.call(__MODULE__, :acquire, :infinity)
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
      Process.sleep(wait_ms)

      now = System.monotonic_time(:millisecond)
      timestamps = drop_expired(state.timestamps, now - state.interval)
      {:reply, :ok, %{state | timestamps: :queue.in(now, timestamps)}}
    end
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
