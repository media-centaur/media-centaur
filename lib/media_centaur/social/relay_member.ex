defmodule MediaCentaur.Social.RelayMember do
  @moduledoc """
  One key seen publishing on a relay whose follow rule is members
  (`Social.Relay`): observed by the sync loop, never configured. `seen_at`
  is when the current connect last delivered an event by the key;
  `Social.sweep_members/2` drops the rows a connect did not refresh. The
  rows go with the relay (`on_delete: :delete_all`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.Social.Relay

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "relay_members" do
    belongs_to :relay, Relay, type: Ecto.UUID
    field :pubkey, :string
    field :seen_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a membership row; the pubkey must already be lowercase hex."
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:relay_id, :pubkey, :seen_at])
    |> validate_required([:relay_id, :pubkey, :seen_at])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint([:relay_id, :pubkey])
  end
end
