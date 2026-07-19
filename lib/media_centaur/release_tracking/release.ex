defmodule MediaCentaur.ReleaseTracking.Release do
  @moduledoc """
  An individual upcoming release event — one row per episode or movie.

  `released` is **derived, not stored** — a release has aired iff it has an
  `air_date` that is today or earlier (`released?/2`). It used to be a stored
  boolean re-freshened by a midnight sweep, which went stale across midnight;
  computing it on read removes that bug class (complexity-retirement W3-1).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_releases" do
    field :air_date, :date
    field :title, :string
    field :season_number, :integer
    field :episode_number, :integer
    field :in_library, :boolean, default: false
    field :in_library_at, :utc_datetime
    field :release_type, :string
    # The film's own TMDB id for movie/collection rows (nil for TV rows) —
    # the unit identity the want ledger keys movie wants on (ADR-056).
    field :part_tmdb_id, :integer

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :air_date,
      :title,
      :season_number,
      :episode_number,
      :in_library,
      :release_type,
      :part_tmdb_id,
      :item_id
    ])
    |> validate_required([:item_id])
    |> unique_constraint(:item_id,
      name: :release_tracking_releases_identity_index,
      message: "duplicate release for this item/season/episode/type"
    )
  end

  @doc """
  Whether a release has aired: it has an `air_date` that is today or earlier.
  Derived on read — there is no stored `released` flag. Accepts a `Release`
  struct or any map/struct exposing `:air_date` (extracted release maps,
  view-model rows). `today` defaults to `Date.utc_today/0`.
  """
  @spec released?(map(), Date.t()) :: boolean()
  def released?(release, today \\ Date.utc_today())
  def released?(%{air_date: nil}, _today), do: false
  def released?(%{air_date: %Date{} = air_date}, today), do: Date.compare(air_date, today) != :gt
  def released?(_release, _today), do: false
end
