defmodule MediaCentaur.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  The owner of an image is identified by the discriminator pair
  `(owner_type, owner_id)`. `owner_type` is one of `:movie`, `:episode`,
  `:tv_series`, `:movie_series`, `:video_object`. The
  `(owner_type, owner_id, role)` tuple is unique — one image per role
  per owner.

  `present?` is not stored: it is whether the file behind `content_url` is
  on disk right now, set by `Library.Images.with_presence/1` when a read
  model takes the row in (default `true` on a row read straight from the
  database, which nothing renders). `MediaCentaurWeb.LiveHelpers.image_url/2`
  withholds the URL of a row whose file is missing, so a page never emits a
  URL the image server cannot serve.
  """
  use Ecto.Schema
  @behaviour MediaCentaur.Library.OwnerTyped
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
    field :present?, :boolean, virtual: true, default: true

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
end
