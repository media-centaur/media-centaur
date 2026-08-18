defmodule MediaCentaur.TmdbArtwork.HoldProvider do
  @moduledoc """
  Contract for contexts that hold TMDB artwork cache entries alive.

  A hold is a `{media_type, tmdb_id}` key: while any registered provider
  returns it, the daily sweep will not remove that entry regardless of
  age. Providers are registered under the `:tmdb_artwork_hold_providers`
  config key — runtime dispatch keeps the referencing contexts
  upstream of `TmdbArtwork` in the Boundary graph, mirroring
  `:retention_policy_providers`.

  `holds/0` runs inside the daily retention sweep; a provider that
  raises fails that sweep run (Oban retries), so keep it a plain query.
  """

  @callback holds() :: MapSet.t({MediaCentaur.TmdbArtwork.media_type(), integer()})
end
