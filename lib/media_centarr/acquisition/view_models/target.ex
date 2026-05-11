defmodule MediaCentarr.Acquisition.ViewModels.Target do
  @moduledoc "TMDB identity of the pursuit's goal — used in the header."

  @enforce_keys [:tmdb_type]
  defstruct [:tmdb_type, :tmdb_id, :season_number, :episode_number, :year]

  @type t :: %__MODULE__{
          tmdb_type: String.t(),
          tmdb_id: String.t() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          year: integer() | nil
        }
end
