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

  # Whitelist guards the atom conversion: a job persisted with a legacy or
  # typo'd entity_type cancels cleanly instead of raising ArgumentError and
  # retrying forever.
  @entity_types ~w(movie tv_series movie_series video_object episode)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entity_id" => entity_id, "entity_type" => type}})
      when type in @entity_types do
    case ImageRefresh.refresh_entity(entity_id, String.to_existing_atom(type)) do
      {:ok, _count} -> :ok
      {:error, :no_tmdb_id} -> {:cancel, :no_tmdb_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"entity_type" => type}}) do
    {:cancel, {:bad_entity_type, type}}
  end
end
