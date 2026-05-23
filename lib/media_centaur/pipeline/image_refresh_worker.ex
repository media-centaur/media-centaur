defmodule MediaCentaur.Pipeline.ImageRefreshWorker do
  @moduledoc """
  Oban worker that runs a per-entity artwork refresh
  (`ImageRefresh.refresh_entity/2`) off the LiveView lifecycle.

  Unique per `entity_id` for a short window so rapid double-clicks
  coalesce. `:no_tmdb_id` cancels (the entity needs a Rematch first, not
  a retry); transient TMDB errors return `{:error, _}` so Oban retries
  with backoff.
  """
  use Oban.Worker, queue: :images, unique: [period: 60, keys: [:entity_id]]

  alias MediaCentaur.Pipeline.ImageRefresh

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entity_id" => entity_id, "entity_type" => type}}) do
    case ImageRefresh.refresh_entity(entity_id, String.to_existing_atom(type)) do
      {:ok, _count} -> :ok
      {:error, :no_tmdb_id} -> {:cancel, :no_tmdb_id}
      {:error, reason} -> {:error, reason}
    end
  end
end
