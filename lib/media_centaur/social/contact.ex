defmodule MediaCentaur.Social.Contact do
  @moduledoc """
  One public key the reader has a view of: the x-only key as lowercase hex
  and the reader's own state about it, none of it from the network.
  `added_at` is set when the reader added the key by hand — a **friend** —
  and nil for a key followed only because it publishes on a relay whose
  follow rule is members (`Social.RelayMember`). `name_override`
  (UIDR-047) is the reader's word for the person, masking the published
  name; blank is none. `show_avatar` is the reader's switch for the
  published picture, on by default. `hue_override` (UIDR-048) masks the
  published hue; nil is none. `hidden` keeps the person's activity off
  every surface but the Friends tab's hidden group.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "contacts" do
    field :pubkey, :string
    field :added_at, :utc_datetime
    field :name_override, :string
    field :show_avatar, :boolean, default: true
    field :hue_override, :integer
    field :hidden, :boolean, default: false

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a contact row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(contact \\ %__MODULE__{}, attrs) do
    contact
    |> cast(attrs, [:pubkey, :added_at, :name_override, :show_avatar, :hue_override, :hidden])
    |> update_change(:name_override, &blank_to_nil/1)
    |> validate_required([:pubkey, :show_avatar, :hidden])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end

  @doc "Whether the reader added this key by hand."
  @spec friend?(t()) :: boolean()
  def friend?(%__MODULE__{added_at: added_at}), do: added_at != nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
