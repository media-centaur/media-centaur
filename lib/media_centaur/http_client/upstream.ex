defmodule MediaCentaur.HttpClient.Upstream do
  @moduledoc """
  The closed set of remote parties this app makes HTTP requests to.

  An upstream is the unit the Status page's outbound-connections panel
  reports on: one row per upstream. It is deliberately not the same
  thing as an *integration* (`MediaCentaur.IntegrationHealth`), which
  is a user-configured, credential-bearing service with a verify probe.
  GitHub, Steam, and the TMDB image CDN are upstreams without being
  integrations; the download-client integration spans two upstreams.

  Every `MediaCentaur.HttpClient.new/2` call names its upstream, and the
  instrumentation event carries it, so the enum here is the whole key
  space the panel and the stats can ever see.
  """

  @upstreams [
    tmdb: "TMDB",
    tmdb_images: "TMDB images",
    prowlarr: "Prowlarr",
    qbittorrent: "qBittorrent",
    sabnzbd: "SABnzbd",
    github: "GitHub",
    steam: "Steam",
    indexers: "Indexers"
  ]

  @type id :: :tmdb | :tmdb_images | :prowlarr | :qbittorrent | :sabnzbd | :github | :steam | :indexers

  @doc "Every upstream id, in panel display order."
  @spec ids() :: [id()]
  def ids, do: Keyword.keys(@upstreams)

  @doc "True for a known upstream id."
  @spec known?(term()) :: boolean()
  def known?(id), do: Keyword.has_key?(@upstreams, id)

  @doc "The user-facing name of an upstream."
  @spec label(id()) :: String.t()
  def label(id), do: Keyword.fetch!(@upstreams, id)
end
