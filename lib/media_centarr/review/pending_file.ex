defmodule MediaCentarr.Review.PendingFile do
  @moduledoc """
  A file awaiting human review before library ingestion.

  Created when the pipeline's Search stage returns `{:needs_review, payload}`
  (low confidence or no TMDB match). Stores everything the reviewer needs to
  make a decision — parsed file info, best TMDB match, and all scored candidates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "review_pending_files" do
    # File info
    field :file_path, :string
    field :watch_directory, :string

    # Parsed info (from Parser.Result)
    field :parsed_title, :string
    field :parsed_year, :integer
    field :parsed_type, :string
    field :season_number, :integer
    field :episode_number, :integer

    # Best TMDB match (from Search stage)
    field :tmdb_id, :integer
    field :tmdb_type, :string
    field :confidence, :float
    field :match_title, :string
    field :match_year, :string
    field :match_poster_path, :string

    # All scored candidates (JSON array of maps)
    field :candidates, {:array, :map}

    # Error if search failed
    field :error_message, :string

    # Workflow status
    field :status, Ecto.Enum, values: [:pending, :approved, :dismissed], default: :pending

    timestamps()
  end

  @create_fields [
    :file_path,
    :watch_directory,
    :parsed_title,
    :parsed_year,
    :parsed_type,
    :season_number,
    :episode_number,
    :tmdb_id,
    :tmdb_type,
    :confidence,
    :match_title,
    :match_year,
    :match_poster_path,
    :candidates,
    :error_message
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create_fields)
    |> validate_required([:file_path])
  end

  def approve_changeset(pending_file) do
    pending_file
    |> change()
    |> validate_status(:pending)
    |> put_change(:status, :approved)
  end

  def dismiss_changeset(pending_file) do
    pending_file
    |> change()
    |> validate_status(:pending)
    |> put_change(:status, :dismissed)
  end

  def set_tmdb_match_changeset(pending_file, attrs) do
    pending_file
    |> cast(attrs, [
      :tmdb_id,
      :tmdb_type,
      :confidence,
      :match_title,
      :match_year,
      :match_poster_path
    ])
    |> validate_status(:pending)
    |> put_change(:candidates, [])
  end

  defp validate_status(changeset, expected) do
    current = get_field(changeset, :status)

    if current == expected do
      changeset
    else
      add_error(changeset, :status, "must be #{expected}, got #{current}")
    end
  end
end
