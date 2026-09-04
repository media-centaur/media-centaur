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

  An upstream is counted whether or not it has a row on the panel. A row
  earns its place when the reader could act on it: Steam is fetched at
  most once an hour for banner art and there is nothing to do about a
  bad answer, so it is instrumented (recent feed, incident vitals) but
  not listed.
  """

  @upstreams [
    tmdb: [label: "TMDB", panel?: true],
    tmdb_images: [label: "TMDB images", panel?: true],
    prowlarr: [label: "Prowlarr", panel?: true],
    qbittorrent: [label: "qBittorrent", panel?: true],
    sabnzbd: [label: "SABnzbd", panel?: true],
    github: [label: "GitHub", panel?: true],
    steam: [label: "Steam", panel?: false],
    indexers: [label: "Indexers", panel?: true]
  ]

  @type id :: :tmdb | :tmdb_images | :prowlarr | :qbittorrent | :sabnzbd | :github | :steam | :indexers

  @doc "Every upstream id, in panel display order."
  @spec ids() :: [id()]
  def ids, do: Keyword.keys(@upstreams)

  @doc "The upstream ids that get a row on the Connections panel."
  @spec panel_ids() :: [id()]
  def panel_ids, do: for({id, meta} <- @upstreams, meta[:panel?], do: id)

  @doc "True for a known upstream id."
  @spec known?(term()) :: boolean()
  def known?(id), do: Keyword.has_key?(@upstreams, id)

  @doc "The user-facing name of an upstream."
  @spec label(id()) :: String.t()
  def label(id), do: Keyword.fetch!(@upstreams, id)[:label]
end
