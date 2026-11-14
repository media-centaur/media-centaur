defmodule MediaCentaur.Library.SeriesWatchPosition do
  @moduledoc """
  Where one profile is in one series (a TV series or a movie collection):
  the order key of the last item playback finished there, and when.

  Written only by playback finishing an item
  (`MediaCentaur.Library.SeriesWatchPositions.record_finish/3`). The
  watched controls never move it. It stores the item's order key, not its
  id, so it survives the item's deletion; it is removed with its series or
  its profile. The order key is a list, compared in Elixir and never in
  SQL. The profile is a plain id, not an association — `Profiles` is
  another context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "library_series_watch_positions" do
    field :profile_id, Ecto.UUID
    field :series_type, Ecto.Enum, values: [:tv_series, :movie_series]
    field :series_id, Ecto.UUID
    field :order_key, {:array, :string}
    field :finished_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "The one changeset: every field is set at each finish."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(position \\ %__MODULE__{}, attrs) do
    # `empty_values: []`: an undated collection movie's order key opens with
    # an empty date (`MovieOrder.order_key/1`), and `cast/4` would otherwise
    # drop that element from the list.
    position
    |> cast(attrs, [:profile_id, :series_type, :series_id, :order_key, :finished_at], empty_values: [])
    |> validate_required([:profile_id, :series_type, :series_id, :order_key, :finished_at])
    |> unique_constraint([:profile_id, :series_id])
  end
end
