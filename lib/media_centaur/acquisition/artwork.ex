defmodule MediaCentaur.Acquisition.Artwork do
  @moduledoc """
  Display artwork for acquisition surfaces (the pursuit modal hero):
  backdrop + logo URLs for a TMDB identity that may not be in the
  library yet. Thin facade over `MediaCentaur.TmdbArtwork` keeping the
  acquisition-side `(tmdb_id, tmdb_type)` argument order its callers
  already use.

  All failures degrade to nils; callers fall back to the synthetic
  gradient + logotype treatment (UIDR-014).
  """

  alias MediaCentaur.TmdbArtwork

  @type urls :: %{backdrop_url: String.t() | nil, logo_url: String.t() | nil}

  @doc "Local-only lookup — disk, safe on any read path."
  @spec resolve(String.t() | integer(), String.t() | atom()) :: urls()
  def resolve(tmdb_id, tmdb_type) do
    %{backdrop_url: backdrop, logo_url: logo} = TmdbArtwork.urls(tmdb_type, tmdb_id)
    %{backdrop_url: backdrop, logo_url: logo}
  end

  @doc """
  `resolve/2`, fetching + caching what's missing first. Does network —
  callers run it async (the pursuit modal uses `start_async`).
  """
  @spec ensure(String.t() | integer(), String.t() | atom()) :: urls()
  def ensure(tmdb_id, tmdb_type) do
    %{backdrop_url: backdrop, logo_url: logo} = TmdbArtwork.ensure(tmdb_type, tmdb_id)
    %{backdrop_url: backdrop, logo_url: logo}
  end
end
