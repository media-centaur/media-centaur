defmodule MediaCentaur.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  Each entity has at most one image per role, enforced by the `unique_entity_role`
  identity and the `find_or_create` upsert action.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_images" do
    field :role, :string
    field :content_url, :string
    field :extension, :string

    belongs_to :entity, MediaCentaur.Library.Entity
    belongs_to :movie, MediaCentaur.Library.Movie
    belongs_to :episode, MediaCentaur.Library.Episode

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:role, :content_url, :extension, :entity_id, :movie_id, :episode_id])
    |> validate_required([:role])
  end

  def update_changeset(image, attrs) do
    image
    |> cast(attrs, [:content_url, :extension])
  end

  def clear_content_url_changeset(image) do
    image
    |> change(content_url: nil)
  end
end
