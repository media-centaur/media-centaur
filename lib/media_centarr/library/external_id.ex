defmodule MediaCentarr.Library.ExternalId do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Stored as `{source, external_id}` per row.

  The owner is identified by the discriminator pair `(owner_type,
  owner_id)`. `owner_type` is one of `:movie`, `:tv_series`,
  `:movie_series`, `:video_object`. The `(source, external_id,
  owner_type)` tuple is unique — TMDB Movie #12345 and TMDB TVSeries
  #12345 are legitimately different namespaces.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @owner_types [:movie, :tv_series, :movie_series, :video_object]

  schema "library_external_ids" do
    field :source, :string
    field :external_id, :string
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, Ecto.UUID

    timestamps()
  end

  def owner_types, do: @owner_types

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:source, :external_id, :owner_type, :owner_id])
    |> validate_required([:source, :external_id, :owner_type, :owner_id])
    # Discriminator-aware uniqueness — `(source, external_id,
    # owner_type)`. A Movie and a TVSeries can both have TMDB id 12345
    # (different TMDB namespaces); two Movies with the same TMDB id is
    # a conflict.
    #
    # The SQLite Ecto adapter does NOT receive the actual constraint
    # name from the database — it synthesises one from the failing
    # column tuple: `<table>_<col1>_<col2>_..._index`. The
    # `unique_constraint` `:name` must match that synthesised string
    # exactly, even though the physical index in the migration is named
    # differently for readability.
    #
    # Race-loss recovery in `Library.Inbound.put_tmdb_id/3` matches on
    # `{:error, %Ecto.Changeset{}}` — this declaration is what makes
    # that branch reachable.
    |> unique_constraint([:source, :external_id, :owner_type],
      name: :library_external_ids_source_external_id_owner_type_index
    )
  end
end
