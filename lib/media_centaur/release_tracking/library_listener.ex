defmodule MediaCentaur.ReleaseTracking.LibraryListener do
  @moduledoc """
  Reacts to library change broadcasts on behalf of release tracking:

  - `{:entities_changed, %{entity_ids: ids}}` → `ReleaseTracking.library_entities_changed/1`
  - `{:containers_deleted, %{container_ids: ids}}` → `ReleaseTracking.detach_library_containers/1`

  Skipped in `:test`; tests call those functions directly.
  """
  use GenServer

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.library_updates())
    Topics.subscribe(Topics.library_deletions())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:entities_changed, %{entity_ids: entity_ids}}, state) do
    ReleaseTracking.library_entities_changed(entity_ids)
    {:noreply, state}
  end

  def handle_info({:containers_deleted, %{container_ids: container_ids}}, state) do
    ReleaseTracking.detach_library_containers(container_ids)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
