defmodule MediaCentarr.Cache.Worker do
  @moduledoc """
  Generic GenServer that wires a `MediaCentarr.Cache` behaviour
  implementation to its PubSub source. Subscribes via the context's
  `subscribe/0`, primes the cache by calling `refresh_cache/0` once,
  then re-runs `refresh_cache/0` for every PubSub message the
  context's `relevant?/1` accepts.

  Workers are anonymous — their supervisor child id is
  `{__MODULE__, context}` so multiple instances coexist without
  colliding. Pass `:name` to register the process (tests do this
  to send messages directly to the worker).
  """
  use GenServer

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
    GenServer.start_link(__MODULE__, context, gen_opts)
  end

  @impl true
  def init(context) do
    context.subscribe()
    context.refresh_cache()
    {:ok, context}
  end

  @impl true
  def handle_info(message, context) do
    if context.relevant?(message), do: dispatch(context, message)
    {:noreply, context}
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
end
