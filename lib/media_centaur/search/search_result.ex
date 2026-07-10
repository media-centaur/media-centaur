defmodule MediaCentaur.Search.SearchResult do
  @moduledoc """
  A single result returned by a search provider.

  `quality` is parsed from the title via `Acquisition.Quality.parse/1` at
  construction time so callers can rank and filter without re-parsing.
  """

  alias MediaCentaur.Search.Quality

  @enforce_keys [:title, :guid, :indexer_id]
  defstruct [
    :title,
    :guid,
    :indexer_id,
    :quality,
    :size_bytes,
    :seeders,
    :leechers,
    :indexer_name,
    :publish_date,
    # Torrent identity, when the indexer exposes it. Captured at grab
    # time onto `Target.torrent_hash` so the pursuit pairs with its live
    # torrent by infohash — robust to the tracker-prefixed names
    # (`www.X.org - …`) that break title matching. Often present for
    # public torrent indexers; nil for usenet and indexers that omit it.
    :info_hash,
    :magnet_url,
    # `:torrent | :usenet`, from Prowlarr's per-result `protocol` field.
    # Prowlarr routes each grab to the matching download client, so MC
    # never picks a client at grab time — the field exists so the queue
    # can be matched and displayed per protocol. Nil when Prowlarr omits
    # or MC doesn't recognize the value.
    :protocol,
    # Prowlarr proxy link to the release. For indexers that expose neither
    # `info_hash` nor a magnet, this is the only path to a durable infohash:
    # fetching it either redirects to a magnet or serves the `.torrent` body,
    # from which `InfoHash.resolve/2` derives the hash at grab time.
    :download_url
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          guid: String.t(),
          indexer_id: integer(),
          quality: Quality.t(),
          size_bytes: integer() | nil,
          seeders: integer() | nil,
          leechers: integer() | nil,
          indexer_name: String.t() | nil,
          publish_date: String.t() | nil,
          info_hash: String.t() | nil,
          magnet_url: String.t() | nil,
          protocol: :torrent | :usenet | nil,
          download_url: String.t() | nil
        }

  @doc "Builds a SearchResult from a raw Prowlarr API result map."
  @spec from_prowlarr(map()) :: t()
  def from_prowlarr(raw) do
    title = scrub_title(raw["title"])

    %__MODULE__{
      title: title,
      guid: raw["guid"],
      indexer_id: raw["indexerId"],
      quality: Quality.parse(title),
      size_bytes: raw["size"],
      seeders: raw["seeders"],
      leechers: raw["leechers"],
      indexer_name: raw["indexer"],
      publish_date: raw["publishDate"],
      info_hash: raw["infoHash"],
      magnet_url: raw["magnetUrl"],
      protocol: parse_protocol(raw["protocol"]),
      download_url: raw["downloadUrl"]
    }
  end

  defp parse_protocol("torrent"), do: :torrent
  defp parse_protocol("usenet"), do: :usenet
  defp parse_protocol(_), do: nil

  # Indexers ship scene titles with mangled encodings, and JSON decoding
  # passes the raw bytes through. Every downstream consumer — unicode
  # regexes, Ecto casts, the UI — assumes valid UTF-8, so the invariant
  # is enforced here, where external data enters the system.
  defp scrub_title(nil), do: ""

  defp scrub_title(title) when is_binary(title) do
    if String.valid?(title), do: title, else: String.replace_invalid(title)
  end
end
