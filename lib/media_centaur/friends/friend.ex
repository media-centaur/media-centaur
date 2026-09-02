defmodule MediaCentaur.Friends.Friend do
  @moduledoc """
  One followed public key: the x-only key as lowercase hex, and the
  nickname this install gave it. The nickname is local — nothing about a
  friend is read from the network (spec decision 6).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "friends" do
    field :pubkey, :string
    field :nickname, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a roster row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(friend \\ %__MODULE__{}, attrs) do
    friend
    |> cast(attrs, [:pubkey, :nickname])
    |> update_change(:nickname, &String.trim/1)
    |> validate_required([:pubkey, :nickname])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
