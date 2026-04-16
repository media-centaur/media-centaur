defmodule MediaCentarr.Acquisition.Grab do
  @moduledoc """
  Tracks an automated acquisition attempt for a TMDB item.

  One row per TMDB item (enforced by unique index on tmdb_id + tmdb_type).
  Status transitions: "searching" → "grabbed".

  While status is "searching", the `SearchAndGrab` Oban job retries every
  4 hours. Once "grabbed", no further retries are scheduled.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_grabs" do
    field :tmdb_id, :string
    field :tmdb_type, :string
    field :title, :string
    field :status, :string, default: "searching"
    field :quality, :string
    field :attempt_count, :integer, default: 0
    field :grabbed_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:tmdb_id, :tmdb_type, :title])
    |> validate_required([:tmdb_id, :tmdb_type, :title])
    |> unique_constraint([:tmdb_id, :tmdb_type])
  end

  def grabbed_changeset(grab, quality) do
    grab
    |> change(status: "grabbed", quality: quality, grabbed_at: DateTime.utc_now(:second))
  end

  def increment_attempt_changeset(grab) do
    grab
    |> change(attempt_count: grab.attempt_count + 1)
  end
end
