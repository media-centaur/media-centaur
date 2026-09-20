defmodule MediaCentaur.TMDB.Store.SeasonRecord do
  @moduledoc """
  One season of a stored series: TMDB's `season/{n}` answer with its
  appended credits, the `etag` to revalidate it with, and when it was
  fetched and last changed. A season has no schedule of its own — it is
  checked with its series while
  `MediaCentaur.TMDB.Schedule.open_season?/3` says it is open. Written
  only by `MediaCentaur.TMDB.Store`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "tmdb_seasons" do
    field :tmdb_id, :integer
    field :season_number, :integer
    field :payload, :map
    field :etag, :string
    field :fetched_at, :utc_datetime
    field :changed_at, :utc_datetime

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:tmdb_id, :season_number, :payload, :etag, :fetched_at, :changed_at])
    |> validate_required([:tmdb_id, :season_number, :payload, :fetched_at, :changed_at])
    |> unique_constraint([:tmdb_id, :season_number])
  end
end
