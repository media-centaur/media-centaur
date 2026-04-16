defmodule MediaCentarr.Settings.Entry do
  @moduledoc """
  Key/value settings store persisted in SQLite.

  Used by the logging system to persist enabled component toggles and
  framework log suppression across restarts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          key: String.t() | nil,
          value: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "settings_entries" do
    field :key, :string
    field :value, :map

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end

  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:value])
  end

  def upsert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end
end
