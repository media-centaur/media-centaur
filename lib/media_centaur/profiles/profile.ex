defmodule MediaCentaur.Profiles.Profile do
  @moduledoc """
  One person who watches on this install (ADR-078): a name, an optional
  hue (`MediaCentaur.Hue`), and `picture_at` — when the picture file was
  last set, nil for none; the file itself is `PictureStore`'s and the
  time doubles as the URL's version. Phase 2 hangs the watching rows
  off `id`. Not `MediaCentaur.Social.Profile`, the published social
  profile of a key.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.DisplayName

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "profiles" do
    field :name, :string
    field :hue, :integer
    field :picture_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "The name is already checked by `DisplayName.check/1`; the hue by `Hue.valid?/1`. This is the row's last guard."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile \\ %__MODULE__{}, attrs) do
    profile
    |> cast(attrs, [:name, :hue, :picture_at])
    |> validate_required([:name])
    |> validate_length(:name, max: DisplayName.max_length())
    |> validate_number(:hue, greater_than_or_equal_to: 0, less_than_or_equal_to: 359)
  end
end
