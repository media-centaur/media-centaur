defmodule MediaCentaur.Review.Rematch do
  @moduledoc """
  Rematches an entity: its files go back to Review for a person to match
  again. The request is recorded as a `Review.RematchJob`, which releases
  the entity (`Library.Rematch.release/1`) and adds its files to the queue
  in one transaction — so the files are never left unlinked and in no
  queue (campaign durable-work, F9). Releasing removes cached artwork from
  disk, which is why it is not done in the caller's handler.
  """

  alias MediaCentaur.Review.RematchJob

  @spec rematch_entity(String.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def rematch_entity(entity_id) do
    with {:ok, _job} <- Oban.insert(RematchJob.new(%{"entity_id" => entity_id})), do: :ok
  end
end
