defmodule MediaCentaur.Library.EpisodeIdentity do
  @moduledoc """
  Canonical identity of a single TV episode — the TMDB-anchored
  `{series_tmdb_id, season, episode}` tuple that every slice speaks
  (library, release tracking, acquisition, display). See
  [ADR-058](`e:decisions`); this promotes the implicit `(tmdb, s, e)`
  convention that was rebuilt in ~13 places into one first-class concept.

  The struct is a pure value: no process, no DB, no TMDB calls. All
  numbering ambiguity (absolute vs. broadcast-season vs. release naming)
  lives in the edge adapters, never here — this module only *represents*
  the canonical identity and derives from it.

  ## Absolute ordinal

  Because TMDB sometimes folds multiple broadcast cours into one
  continuous season (Frieren: one 38-episode Season 1), the absolute
  ordinal — episode index across all non-special seasons — is the bridge
  to real-world numbering: `S01E29` ≡ absolute 29 ≡ a fansub's
  `Show - 29`. It is **derived, never stored** (ADR-057), computed from
  the series' per-season episode counts supplied by the caller.
  """

  @enforce_keys [:series_tmdb_id, :season, :episode]
  defstruct [:series_tmdb_id, :season, :episode]

  @type t :: %__MODULE__{
          series_tmdb_id: String.t(),
          season: pos_integer(),
          episode: pos_integer()
        }

  @doc "Builds an identity. `series_tmdb_id` is the string TMDB id used across the app."
  @spec new(String.t(), pos_integer(), pos_integer()) :: t()
  def new(series_tmdb_id, season, episode)
      when is_binary(series_tmdb_id) and is_integer(season) and is_integer(episode) do
    %__MODULE__{series_tmdb_id: series_tmdb_id, season: season, episode: episode}
  end

  @doc """
  Within-series dedup key — the `s{season}e{episode}` form
  `ReleaseTracking.Want.unit_key/3` uses for TV. Series-agnostic by
  design: the key identifies an episode *within* a known series.
  """
  @spec to_key(t()) :: String.t()
  def to_key(%__MODULE__{season: season, episode: episode}), do: "s#{season}e#{episode}"

  @doc "Display label in the canonical `SxxExx` form (matches `Format.episode_label/2`)."
  @spec label(t()) :: String.t()
  def label(%__MODULE__{season: season, episode: episode}) do
    "S#{pad2(season)}E#{pad2(episode)}"
  end

  @doc """
  Absolute episode ordinal across the series' non-special seasons.

  `season_counts` maps `season_number => episode_count` (TMDB's
  per-season counts). Season 0 (Specials) is excluded. Counts for seasons
  at or after this episode's season are ignored; an unknown prior season
  simply contributes nothing (best-effort, matching the
  no-external-mapping policy of ADR-058).
  """
  @spec absolute_ordinal(t(), %{optional(integer()) => non_neg_integer()}) :: pos_integer()
  def absolute_ordinal(%__MODULE__{season: season, episode: episode}, season_counts)
      when is_map(season_counts) do
    prior =
      season_counts
      |> Enum.filter(fn {season_number, _count} -> season_number > 0 and season_number < season end)
      |> Enum.map(fn {_season_number, count} -> count end)
      |> Enum.sum()

    prior + episode
  end

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
