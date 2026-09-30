defmodule MediaCentaur.Review.RematchJob do
  @moduledoc """
  Carries out a rematch (`Review.Rematch.rematch_entity/1`): releases the
  entity and puts its files back in the review queue, in one transaction.
  An entity already released releases nothing, so a retry is harmless.
  """

  # One rematch per entity among jobs not yet started (ADR-077, rule 6).
  use Oban.Worker,
    queue: :maintenance,
    unique: [period: :infinity, keys: [:entity_id], states: [:available, :scheduled, :retryable]]

  alias MediaCentaur.Library.Rematch
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entity_id" => entity_id}}) do
    {:ok, _added} =
      Repo.transaction(fn ->
        {:ok, files} = Rematch.release(entity_id)
        {:ok, added} = Review.add_files_for_review(files)
        added
      end)

    :ok
  end
end
