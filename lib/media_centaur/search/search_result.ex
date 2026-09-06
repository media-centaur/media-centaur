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
    # How many times the indexer has served this release. The usenet
    # analogue of `seeders`: a usenet result carries no swarm, so a
    # seeders-only popularity signal is permanently nil on a usenet
    # indexer and every tie falls to pool order. `ReleasePreference`
    # reads whichever of the two the protocol actually populates.
    :grabs,
    :indexer_name,
    :publish_date,
    # Torrent identity, when the indexer exposes it. Captured at grab
    # time onto `Target.torrent_hash` so the pursuit pairs with its live
    # torrent by infohash — robust to the tracker-prefixed names
    # (`www.X.org - …`) that break title matching. Often present for
    # public torrent indexers; nil for usenet and indexers that omit it.
    :info_hash,
    :magnet_url,
    # External identity, as the indexer declares it — the exact answer
    # to "which title is this release?", against which parsing a release
    # name is a heuristic. Prowlarr sends them as integers with `0`
    # meaning absent; normalized here to the string spelling
    # `Library.ExternalIds` uses (`imdb_id` carries its `tt` prefix).
    # Populated by newznab indexers, largely absent on public torrent
    # indexers — `TitleMatcher` falls back to title parsing without them.
    :imdb_id,
    :tmdb_id,
    :tvdb_id,
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
          grabs: integer() | nil,
          indexer_name: String.t() | nil,
          publish_date: String.t() | nil,
          info_hash: String.t() | nil,
          magnet_url: String.t() | nil,
          imdb_id: String.t() | nil,
          tmdb_id: String.t() | nil,
          tvdb_id: String.t() | nil,
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
      grabs: raw["grabs"],
      indexer_name: raw["indexer"],
      publish_date: raw["publishDate"],
      info_hash: raw["infoHash"],
      magnet_url: raw["magnetUrl"],
      imdb_id: parse_imdb_id(raw["imdbId"]),
      tmdb_id: parse_numeric_id(raw["tmdbId"]),
      tvdb_id: parse_numeric_id(raw["tvdbId"]),
      protocol: parse_protocol(raw["protocol"]),
      download_url: raw["downloadUrl"]
    }
  end

  # IMDb ids are canonically `tt` + at least seven digits; newznab sends
  # the bare number, so the prefix and the zero padding are restored here.
  defp parse_imdb_id(id) when is_integer(id) and id > 0 do
    "tt" <> String.pad_leading(Integer.to_string(id), 7, "0")
  end

  defp parse_imdb_id("tt" <> _rest = id), do: id
  defp parse_imdb_id(id) when is_binary(id), do: id |> Integer.parse() |> imdb_id_from_parse()
  defp parse_imdb_id(_id), do: nil

  defp imdb_id_from_parse({number, _rest}), do: parse_imdb_id(number)
  defp imdb_id_from_parse(:error), do: nil

  defp parse_numeric_id(id) when is_integer(id) and id > 0, do: Integer.to_string(id)
  defp parse_numeric_id(id) when is_binary(id) and id != "" and id != "0", do: id
  defp parse_numeric_id(_id), do: nil

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
