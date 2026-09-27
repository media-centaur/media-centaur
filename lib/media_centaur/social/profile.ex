defmodule MediaCentaur.Social.Profile do
  @moduledoc """
  What a public key published about itself (ADR-073): its name, or
  nothing yet. One row per known key, replaced whole by a newer event;
  `raw_event` is the signed wire form the own-events diff republishes,
  `created_at` the wire time that decides which copy wins. The reader's
  own is a row like any other, under the identity's key. Built and read
  through `Social` (`save_profile/1`, `ingest_profile/1`, `own_profile/0`);
  the wire shape is `Profile.Translation`'s.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "profiles" do
    field :pubkey, :string
    field :name, :string
    field :raw_event, :map
    field :created_at, :integer

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset from `Translation.from_event/1`'s attrs."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile \\ %__MODULE__{}, attrs) do
    profile
    |> cast(attrs, [:pubkey, :name, :raw_event, :created_at])
    |> validate_required([:pubkey, :raw_event, :created_at])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
