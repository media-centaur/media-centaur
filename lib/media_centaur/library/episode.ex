defmodule MediaCentaur.Library.Episode do
  @moduledoc """
  A TV episode belonging to a `Season`. Stores per-episode metadata from TMDB
  and the local `content_url` linking to the video file.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_episodes" do
    field :episode_number, :integer
    field :name, :string
    field :description, :string
    field :duration, :string
    field :content_url, :string

    belongs_to :season, MediaCentaur.Library.Season
    has_many :images, MediaCentaur.Library.Image
    has_one :watch_progress, MediaCentaur.Library.WatchProgress

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:episode_number, :name, :description, :duration, :content_url, :season_id])
    |> validate_required([:season_id, :episode_number])
  end

  def set_content_url_changeset(episode, attrs) do
    episode
    |> cast(attrs, [:content_url])
  end
end
