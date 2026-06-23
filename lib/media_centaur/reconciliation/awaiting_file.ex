defmodule MediaCentaur.Reconciliation.AwaitingFile do
  @moduledoc """
  A file diverted out of ingest because its parsed season is not in TMDB's
  season list — the cour/absolute-numbering case (reconciliation campaign).
  Rather than fabricate a phantom season to hold it, the pipeline parks the
  file here and the show-scoped mapping review reconciles it onto the
  canonical spine.

  This is the **second review dimension** — identity (`Review.PendingFile`,
  "which show?") is already settled upstream, so this record trusts
  `tmdb_id` and only carries the artifact's **claims** (`claimed_season/
  episode/title`) for the engine to interpret. It is the durable divert
  target; proposals and confidence are re-derived each run, never stored.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "reconciliation_awaiting_files" do
    field :file_path, :string
    field :media_dir, :string

    # Identity (settled upstream by the search stage's confidence gate).
    field :tmdb_id, :integer
    field :series_title, :string

    # The artifact's untrusted claims about itself.
    field :claimed_season, :integer
    field :claimed_episode, :integer
    field :claimed_title, :string

    field :status, Ecto.Enum, values: [:pending, :resolved, :dismissed], default: :pending

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for parking a freshly diverted file."
  def changeset(awaiting_file, attrs) do
    awaiting_file
    |> cast(attrs, [
      :file_path,
      :media_dir,
      :tmdb_id,
      :series_title,
      :claimed_season,
      :claimed_episode,
      :claimed_title,
      :status
    ])
    |> validate_required([:file_path, :media_dir, :tmdb_id])
    |> unique_constraint(:file_path)
  end
end
