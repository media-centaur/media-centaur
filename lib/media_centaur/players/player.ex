defmodule MediaCentaur.Players.Player do
  @moduledoc """
  One paired player: a device on the LAN that renders a viewing, admitted
  to this install by pairing. A name the owner reads in Settings → Players
  and `inserted_at`, when it paired. The id is what the device's browser
  session holds (`"player_id"`, beside ADR-078's `"profile_id"`); the gate
  reads the row back on every request, so removing the row cuts the
  device off.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.DisplayName

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "players" do
    field :name, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "The name is already checked by `DisplayName.check/1`. This is the row's last guard."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(player \\ %__MODULE__{}, attrs) do
    player
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: DisplayName.max_length())
  end
end
