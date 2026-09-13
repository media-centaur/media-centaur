defmodule MediaCentaur.Library.Season do
  @moduledoc """
  A TV season belonging to a `TVSeries` entity. Created from TMDB season data
  when a file for that season is first ingested.

  `episode_list` is TMDB's ordered episodes for the season, including
  episodes no file was imported for — the season's single source for "what
  episodes exist". The episode *count* is `length(episode_list)`; the
  `number_of_episodes` column it replaced held that same length, stored
  separately.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_seasons" do
    field :season_number, :integer
    field :name, :string

    embeds_many :episode_list, MediaCentaur.Library.EpisodeListEntry, on_replace: :delete

    belongs_to :tv_series, MediaCentaur.Library.TVSeries
    has_many :episodes, MediaCentaur.Library.Episode

    # Polymorphic association — Extra rows discriminate on
    # `(owner_type, owner_id)` (Library Schema v2 Phase 2 Task E).
    has_many :extras, MediaCentaur.Library.Extra,
      foreign_key: :owner_id,
      where: [owner_type: :season]

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:season_number, :name, :tv_series_id])
    |> cast_embed(:episode_list)
    # Matches the unique index restored in
    # 20260523210000_restore_season_unique_index. Surfaces a racing
    # duplicate insert as `{:error, changeset}` so `find_or_insert_by/3`
    # can recover to the winning row instead of creating a second Season.
    |> unique_constraint([:tv_series_id, :season_number])
  end

  @doc """
  Replaces the season's episode list wholesale — the write
  `MediaCentaur.Maintenance.refresh_episode_lists/0` makes. `entries` is a
  list of plain maps with `:episode_number`, `:name` and `:air_date`.
  """
  def episode_list_changeset(%__MODULE__{} = season, entries) do
    season
    |> cast(%{episode_list: entries}, [])
    |> cast_embed(:episode_list)
  end
end
