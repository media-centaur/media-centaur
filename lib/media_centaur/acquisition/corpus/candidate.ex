defmodule MediaCentaur.Acquisition.Corpus.Candidate do
  @moduledoc """
  Schema for one corpus candidate — a release a search discovered,
  durable so pivots can re-resolve among already-known alternatives
  without re-hitting indexers (the living-intent fallback, ADR-055).

  Carries every `Search.SearchResult` field so a candidate can be
  rehydrated into the exact struct `Prowlarr.grab/1` accepts. Mutable
  health facts (`seeders`, `leechers`, `grabs`, `size_bytes`) refresh on
  every re-observation; `first_seen_at` is write-once provenance.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_corpus_candidates" do
    field :search_key, :string
    field :guid, :string
    field :title, :string
    field :indexer_id, :integer
    field :indexer_name, :string
    field :quality, :string
    field :size_bytes, :integer
    field :seeders, :integer
    field :leechers, :integer
    field :grabs, :integer
    field :publish_date, :string
    field :protocol, :string
    field :info_hash, :string
    field :magnet_url, :string
    field :download_url, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @cast_fields ~w(
    search_key guid title indexer_id indexer_name quality size_bytes
    seeders leechers grabs publish_date protocol info_hash magnet_url
    download_url first_seen_at last_seen_at
  )a

  @doc "Builds an upsertable row for one discovered release."
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @cast_fields)
    |> validate_required([:search_key, :guid, :title, :first_seen_at, :last_seen_at])
    |> unique_constraint([:search_key, :guid])
  end
end
