defmodule MediaCentaur.NewReleases.Member do
  @moduledoc """
  One place on the New Releases shelf: a TMDB movie id, its position in
  the shelf's order and the US digital release date it qualified with.
  The shelf is movies only, so a member's ref is always `{tmdb_id,
  :movie}`. Rows are written whole by `MediaCentaur.NewReleases.replace/1`
  and never edited one by one.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tmdb_id: pos_integer(),
          position: non_neg_integer(),
          digital_date: Date.t()
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "new_release_members" do
    field :tmdb_id, :integer
    field :position, :integer
    field :digital_date, :date

    timestamps()
  end

  @doc "The member's store ref."
  @spec ref(t()) :: MediaCentaur.TMDB.Store.ref()
  def ref(%__MODULE__{tmdb_id: tmdb_id}), do: {tmdb_id, :movie}
end
