defmodule MediaCentaur.Repo.Migrations.CorpusCandidatesDropQuality do
  use Ecto.Migration

  # Quality is a pure function of the release title and is derived on
  # read (`Search.SearchResult.from_map/1`), so a stored copy only goes
  # stale when the quality rules change.
  def change do
    alter table(:acquisition_corpus_candidates) do
      remove :quality, :string
    end
  end
end
