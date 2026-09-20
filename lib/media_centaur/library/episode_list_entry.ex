defmodule MediaCentaur.Library.EpisodeListEntry do
  @moduledoc """
  One entry in a `MediaCentaur.Library.Season`'s episode list — an episode
  TMDB says the season contains, whether or not a file for it was ever
  imported.

  Written from the season payload at ingest
  (`MediaCentaur.Pipeline.Stages.FetchMetadata`) and rebuilt from the
  TMDB store whenever the series changes
  (`MediaCentaur.Pipeline.TmdbProjection`, ADR-071); the entries are
  `MediaCentaur.TMDB.Mapper.episode_list/1`'s.

  This is not a `MediaCentaur.Library.Episode`: an Episode row means a file
  exists, and invariants elsewhere depend on that — release tracking
  satisfies a want by finding one. An entry only means TMDB lists the
  episode.

  `air_date` is nil for episodes TMDB has not dated. An undated entry is
  treated as aired, not as upcoming: absence of a date is not evidence that
  an episode is still to come.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          episode_number: integer() | nil,
          name: String.t() | nil,
          air_date: Date.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :episode_number, :integer
    field :name, :string
    field :air_date, :date
  end

  @doc "Casts one TMDB episode into an entry."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:episode_number, :name, :air_date])
    |> validate_required([:episode_number])
  end
end
