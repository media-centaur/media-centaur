defmodule MediaCentaur.Watcher.KnownFile do
  @moduledoc """
  Tracks filesystem presence of video files detected by the watcher.

  Each record represents a file the watcher has seen. The `state` field
  tracks whether the file is currently present on disk or absent (e.g.,
  drive disconnected). Absent files are cleaned up after a configurable
  TTL expires.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watcher_files" do
    field :file_path, :string
    field :watch_dir, :string
    field :state, Ecto.Enum, values: [:present, :absent], default: :present
    field :absent_since, :utc_datetime_usec

    timestamps()
  end

  def record_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:file_path, :watch_dir])
    |> validate_required([:file_path, :watch_dir])
    |> put_change(:state, :present)
  end
end
