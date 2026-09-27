defmodule MediaCentaur.Social.Friend do
  @moduledoc """
  One followed public key: the x-only key as lowercase hex and the
  reader's name for it, `name_override` (UIDR-047): the reader's own
  word for the friend, which will mask the name the key publishes once
  profiles carry one. Nothing here comes from the network.

  The column is still `nickname`, mapped with `source:`; the profiles
  campaign's phase 2 rebuild renames it when the name becomes optional
  beside the published one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "friends" do
    field :pubkey, :string
    field :name_override, :string, source: :nickname

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a roster row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(friend \\ %__MODULE__{}, attrs) do
    friend
    |> cast(attrs, [:pubkey, :name_override])
    |> update_change(:name_override, &String.trim/1)
    |> validate_required([:pubkey, :name_override])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
