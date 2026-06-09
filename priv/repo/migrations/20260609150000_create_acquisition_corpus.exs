defmodule MediaCentaur.Repo.Migrations.CreateAcquisitionCorpus do
  @moduledoc """
  The search corpus (ADR-055 / media-search campaign): a durable record
  of what acquisition searches have found, keyed by search term +
  result-affecting options. Serves two masters — indexer citizenship
  (consult-first with a freshness gate before automated re-searches)
  and current-alternative fallback (pivots re-resolve among
  already-known candidates). Additive; no backfill.
  """
  use Ecto.Migration

  def change do
    create table(:acquisition_corpus_searches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :search_key, :string, null: false
      add :term, :string, null: false
      add :last_searched_at, :utc_datetime, null: false
      add :result_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:acquisition_corpus_searches, [:search_key])
    create index(:acquisition_corpus_searches, [:last_searched_at])

    create table(:acquisition_corpus_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :search_key, :string, null: false
      add :guid, :string, null: false
      add :title, :string, null: false
      add :indexer_id, :integer
      add :indexer_name, :string
      add :quality, :string
      add :size_bytes, :bigint
      add :seeders, :integer
      add :leechers, :integer
      add :publish_date, :string
      add :info_hash, :string
      add :magnet_url, :string
      add :download_url, :string
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:acquisition_corpus_candidates, [:search_key, :guid])
    create index(:acquisition_corpus_candidates, [:last_seen_at])
  end
end
