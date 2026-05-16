defmodule MediaCentarr.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  The owner of an image is identified by the discriminator pair
  `(owner_type, owner_id)`. `owner_type` is one of `:movie`, `:episode`,
  `:tv_series`, `:movie_series`, `:video_object`. The
  `(owner_type, owner_id, role)` tuple is unique — one image per role
  per owner.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @owner_types [:movie, :episode, :tv_series, :movie_series, :video_object]

  schema "library_images" do
    field :role, :string
    field :content_url, :string
    field :extension, :string
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, Ecto.UUID

    timestamps()
  end

  def owner_types, do: @owner_types

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:role, :content_url, :extension, :owner_type, :owner_id])
    |> validate_required([:role, :owner_type, :owner_id])
    # The SQLite Ecto adapter synthesises the constraint name from the
    # failing column tuple: `<table>_<col1>_<col2>_..._index`. The
    # `:name` must match exactly, even though the physical index in the
    # migration is named differently for readability.
    |> unique_constraint([:owner_type, :owner_id, :role],
      name: :library_images_owner_type_owner_id_role_index
    )
  end

  def update_changeset(image, attrs) do
    cast(image, attrs, [:content_url, :extension])
  end
end
