defmodule MediaCentaur.Social.Friend do
  @moduledoc """
  One followed public key: the x-only key as lowercase hex and, when the
  reader gave one, `name_override` (UIDR-047): the reader's own word for
  the friend, which masks the name the key publishes (`Social.Profile`).
  The override is optional; blank is none. `show_avatar` is the reader's
  switch for the friend's avatar, on by default. Nothing here comes from
  the network.

  `hue_override` is the reader's hue for the friend (UIDR-048), masking
  the published one; nil is none.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "friends" do
    field :pubkey, :string
    field :name_override, :string
    field :show_avatar, :boolean, default: true
    field :hue_override, :integer

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a roster row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(friend \\ %__MODULE__{}, attrs) do
    friend
    |> cast(attrs, [:pubkey, :name_override, :show_avatar, :hue_override])
    |> update_change(:name_override, &blank_to_nil/1)
    |> validate_required([:pubkey, :show_avatar])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
