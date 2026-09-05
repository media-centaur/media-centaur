defmodule MediaCentaur.Cache.Worker do
  @moduledoc """
  Generic GenServer that wires a `MediaCentaur.Cache` behaviour
  implementation to its PubSub source. Subscribes via the context's
  `subscribe/0`, primes the cache by calling `refresh_cache/0` once,
  then re-runs `refresh_cache/0` for every PubSub message the
  context's `relevant?/1` accepts.

  Workers are anonymous — their supervisor child id is
  `{__MODULE__, context}` so multiple instances coexist without
  colliding. Pass `:name` to register the process (tests do this
  to send messages directly to the worker).

  ## Options

    * `:context` (required) — the `MediaCentaur.Cache` implementation.
    * `:refresh_interval_ms` — when set, also refresh on a periodic
      tick. For caches whose truth drifts without a PubSub event
      (disk measurements, aggregate counts fed by many sources).
      Ticks are scheduled after each completed refresh, so a slow
      refresh never lets ticks pile up.
    * `:prime` — `:sync` (default) primes in `init/1`, guaranteeing
      the cache is warm when the supervisor proceeds. `:async` primes
      via `handle_continue/2` so a refresh that can block on slow I/O
      (a `df` against a sleeping drive) never blocks application
      boot. Subscription still happens in `init/1`, so events
      arriving during an async prime queue behind it rather than
      being lost.
  """
  use GenServer

  @interval_tick {__MODULE__, :interval_refresh}

  def child_spec(opts) do
    context = Keyword.fetch!(opts, :context)

    %{
      id: {__MODULE__, context},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    context = Keyword.fetch!(opts, :context)
    gen_opts = Keyword.take(opts, [:name])

    state = %{
      context: context,
      refresh_interval_ms: Keyword.get(opts, :refresh_interval_ms),
      prime: Keyword.get(opts, :prime, :sync)
    }

    GenServer.start_link(__MODULE__, state, gen_opts)
  end

  @impl true
  def init(state) do
    state.context.subscribe()

    case state.prime do
      :async ->
        {:ok, state, {:continue, :prime}}

      :sync ->
        state.context.refresh_cache()
        schedule_tick(state)
        {:ok, state, :hibernate}
    end
  end

  # Every refresh builds the whole view in this process's heap and hands
  # the result to ETS; the garbage stays resident until the next GC. With
  # seven workers that was tens of MB of dead rebuild data at idle.
  # Hibernating after each refresh releases it — the next message wakes
  # the process at the cost of one small heap allocation (audit P7).
  @impl true
  def handle_continue(:prime, state) do
    state.context.refresh_cache()
    schedule_tick(state)
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info(@interval_tick, state) do
    state.context.refresh_cache()
    schedule_tick(state)
    {:noreply, state, :hibernate}
  end

  def handle_info(message, state) do
    if state.context.relevant?(message), do: dispatch(state.context, message)
    {:noreply, state, :hibernate}
  end

  # If the context implements the optional `handle_message/1` callback,
  # route the message there so it can do targeted per-row refreshes.
  # Otherwise fall back to the broad-stroke `refresh_cache/0`.
  defp dispatch(context, message) do
    if function_exported?(context, :handle_message, 1) do
      context.handle_message(message)
    else
      context.refresh_cache()
    end
  end

  defp schedule_tick(%{refresh_interval_ms: nil}), do: :ok

  defp schedule_tick(%{refresh_interval_ms: interval_ms}) do
    Process.send_after(self(), @interval_tick, interval_ms)
    :ok
  end
end
