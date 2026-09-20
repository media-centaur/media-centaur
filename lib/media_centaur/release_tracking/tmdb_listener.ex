defmodule MediaCentaur.ReleaseTracking.TmdbListener do
  @moduledoc """
  Subscribes to `MediaCentaur.Topics.tmdb_titles/0` and hands a changed
  stored title to `ReleaseTracking.title_changed/1`, which rebuilds the
  tracked calendar from the store (ADR-071 §2). Subscribe-and-dispatch
  only. Skipped in `:test`; tests call the function directly.
  """
  use GenServer

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.tmdb_titles())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:tmdb_title_changed, ref}, state) do
    ReleaseTracking.title_changed(ref)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
