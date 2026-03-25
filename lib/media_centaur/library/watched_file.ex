defmodule MediaCentaur.Library.WatchedFile do
  @moduledoc """
  Links a video file to its resolved library entity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "watched_files" do
    field :file_path, :string
    field :state, Ecto.Enum, values: [:complete, :absent], default: :complete
    field :watch_dir, :string
    field :absent_since, :utc_datetime_usec

    belongs_to :entity, MediaCentaur.Library.Entity

    timestamps()
  end

  def link_file_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:file_path, :watch_dir, :entity_id])
    |> validate_required([:file_path])
    |> put_change(:state, :complete)
  end

  def link_file_changeset(watched_file, attrs) do
    watched_file
    |> cast(attrs, [:file_path, :watch_dir, :entity_id])
    |> put_change(:state, :complete)
  end

  def mark_absent_changeset(watched_file) do
    watched_file
    |> change(state: :absent, absent_since: DateTime.utc_now())
  end

  def mark_present_changeset(watched_file) do
    watched_file
    |> change(state: :complete, absent_since: nil)
  end

  def set_absent_since_changeset(watched_file, attrs) do
    watched_file
    |> cast(attrs, [:absent_since])
  end
end
