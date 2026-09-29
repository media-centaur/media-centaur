defmodule MediaCentaur.Review.PendingFile do
  @moduledoc """
  A file awaiting human review before library ingestion.

  Created when the pipeline's Search stage returns `{:needs_review, payload}`
  (low confidence or no TMDB match). Stores everything the reviewer needs to
  make a decision — parsed file info, best TMDB match, and all scored candidates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "review_pending_files" do
    # File info
    field :file_path, :string
    field :media_directory, :string

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
    :media_directory,
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

  @doc """
  The parsed columns of a pending file, from a `Parser.Result`: the title
  and year the file is looked up under (`Parser.search_params/1`), its
  parsed type and its season/episode numbers.
  """
  @spec parsed_attrs(MediaCentaur.Parser.Result.t()) :: map()
  def parsed_attrs(%MediaCentaur.Parser.Result{} = parsed) do
    {title, year} = MediaCentaur.Parser.search_params(parsed)

    %{
      parsed_title: title,
      parsed_year: year,
      parsed_type: Atom.to_string(parsed.type),
      season_number: parsed.season,
      episode_number: parsed.episode
    }
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create_fields)
    |> validate_required([:file_path])
  end

  # Approval sends the match to Import, so it needs an identity. It is also
  # the retry of an item the library returned, so the reason it came back
  # with no longer describes it. A series match without an episode cannot be
  # approved: the library would have nothing to attach it to.
  def approve_changeset(pending_file) do
    pending_file
    |> change()
    |> validate_required([:tmdb_id, :tmdb_type])
    |> validate_status(:pending)
    |> validate_episode_chosen()
    |> put_change(:status, :approved)
    |> put_change(:error_message, nil)
  end

  @doc """
  True when the file is matched to a series but carries no season and
  episode. A bonus feature belongs to the series itself and needs none.
  """
  def needs_episode?(%__MODULE__{tmdb_type: "tv", parsed_type: parsed_type} = pending_file)
      when parsed_type != "extra" do
    is_nil(pending_file.season_number) or is_nil(pending_file.episode_number)
  end

  def needs_episode?(%__MODULE__{}), do: false

  def set_episode_changeset(pending_file, season_number, episode_number) do
    pending_file
    |> cast(%{season_number: season_number, episode_number: episode_number}, [
      :season_number,
      :episode_number
    ])
    |> validate_required([:season_number, :episode_number])
    |> validate_number(:season_number, greater_than_or_equal_to: 0)
    |> validate_number(:episode_number, greater_than_or_equal_to: 0)
    |> validate_status(:pending)
  end

  defp validate_episode_chosen(changeset) do
    if needs_episode?(changeset.data) do
      add_error(changeset, :episode_number, "choose the episode this file is")
    else
      changeset
    end
  end

  def dismiss_changeset(pending_file) do
    pending_file
    |> change()
    |> validate_status(:pending)
    |> put_change(:status, :dismissed)
  end

  @doc """
  Returns a terminal row to `:pending` with freshly parsed columns.

  Deliberately unguarded by `validate_status/2`: the point is to reopen
  a row that is `:approved` or `:dismissed`. `file_path` is unique, so a
  path that has been decided before cannot get a second row — reopening
  the one that exists is the only way to put it back in the queue.

  Clears the previous match so the reviewer decides again rather than
  seeing a stale candidate presented as current.
  """
  def reopen_changeset(pending_file, attrs) do
    pending_file
    |> cast(attrs, @create_fields)
    |> put_change(:status, :pending)
    |> put_change(:candidates, [])
    |> put_change(:error_message, nil)
    |> validate_required([:file_path])
  end

  @doc """
  Returns an item to `:pending` because its file was not linked, with the
  reason the reviewer reads. Unlike `reopen_changeset/2` it keeps the
  match: the reviewer sees what they chose and why it did not work.
  """
  def unlinked_changeset(pending_file, message) do
    change(pending_file, status: :pending, error_message: message)
  end

  def set_tmdb_match_changeset(pending_file, attrs) do
    pending_file
    |> cast(attrs, [
      :tmdb_id,
      :tmdb_type,
      :confidence,
      :match_title,
      :match_year,
      :match_poster_path,
      :season_number,
      :episode_number
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
