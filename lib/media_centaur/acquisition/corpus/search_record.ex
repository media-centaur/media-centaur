defmodule MediaCentaur.Acquisition.Corpus.SearchRecord do
  @moduledoc """
  Schema for one corpus search — "this search key was last run against
  the indexers at T and returned N results".

  The freshness gate reads `last_searched_at`; an empty result set is
  recorded too (negative knowledge is still knowledge — it's what stops
  an automated system from hammering indexers for something that isn't
  there). `search_key` is the term plus result-affecting options, built
  by `Corpus.search_key/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_corpus_searches" do
    field :search_key, :string
    field :term, :string
    field :last_searched_at, :utc_datetime
    field :result_count, :integer, default: 0

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Builds an upsertable row for a completed search."
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:search_key, :term, :last_searched_at, :result_count])
    |> validate_required([:search_key, :term, :last_searched_at])
    |> unique_constraint(:search_key)
  end
end
