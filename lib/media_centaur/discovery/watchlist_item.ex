defmodule MediaCentaur.Discovery.WatchlistItem do
  @moduledoc """
  Title-level "I want to watch this" intent — a snapshot of a TMDB
  title plus provenance.

  Identity is `(tmdb_id, media_type)` — TMDB's movie and TV id spaces
  overlap, same convention as `ReleaseTracking.Item` and the TmdbArtwork
  cache. The remaining TMDB fields are a *snapshot* cached at add time so
  the item renders without TMDB reachability; the library is never
  referenced from here — presence is derived at read time via
  `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:friend`, `:import`, …); directed recommendations later add nullable
  sender/recipient columns — no dead columns until then.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watchlist_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :year, :string
    field :release_date, :date
    field :poster_path, :string
    field :overview, :string
    field :source, Ecto.Enum, values: [:manual], default: :manual
    field :note, :string

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :media_type,
      :name,
      :year,
      :release_date,
      :poster_path,
      :overview,
      :source,
      :note
    ])
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type])
  end
end
