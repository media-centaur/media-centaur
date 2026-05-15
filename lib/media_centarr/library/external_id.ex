defmodule MediaCentarr.Library.ExternalId do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Stored as `{source, external_id}` per row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_external_ids" do
    field :source, :string
    field :external_id, :string

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    belongs_to :movie_series, MediaCentarr.Library.MovieSeries
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :source,
      :external_id,
      :movie_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
    |> validate_required([:source, :external_id])
    # All four partial unique indexes — `*_movie_unique`,
    # `*_tv_series_unique`, `*_movie_series_unique`,
    # `*_video_object_unique` — are on the same column tuple
    # `(source, external_id)`. The SQLite Ecto adapter doesn't propagate
    # the specific index name from the constraint error; it only knows
    # which columns failed. A single `unique_constraint([:source,
    # :external_id])` (default name = `<table>_source_external_id_index`)
    # matches the error format Ecto synthesises and surfaces the
    # violation as a changeset error rather than `Ecto.ConstraintError`.
    # Race-loss recovery in `Library.Inbound.put_tmdb_id/3` matches on
    # `{:error, %Ecto.Changeset{}}` — this declaration is what makes
    # that branch reachable.
    |> unique_constraint([:source, :external_id])
  end
end
