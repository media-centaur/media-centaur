defmodule MediaCentaur.Acquisition.InfoHash do
  @moduledoc """
  Derives and normalizes a torrent's v1 infohash from a search result.

  The infohash is the *durable* identity of a download. Unlike the
  torrent's display name — which trackers freely mangle with a site
  prefix (`www.X.org - …`) that breaks normalized-title matching — the
  infohash is stable from grab through every queue snapshot.
  `QueueItem.id` already carries qBittorrent's infohash (lowercase
  40-char hex); capturing the same value onto `Target.torrent_hash` at
  grab time lets the pursuit pair with its live torrent by exact key.

  ## Sources, in order

  1. The indexer's `infoHash` field (Prowlarr `SearchResult.info_hash`).
  2. The `xt=urn:btih:` parameter of the `magnetUrl`, when present.

  ## Normalization

  Output is always lowercase 40-char hex, or `nil`:

    * 40-char hex → lowercased.
    * 32-char RFC-4648 base32 (the alternate magnet encoding of the same
      20 bytes) → decoded to hex.
    * Anything else (wrong length, non-hex/base32, v2-only `urn:btmh`,
      usenet releases with no hash) → `nil`, and the caller falls back to
      title matching + later backfill from the observed queue item.
  """

  alias MediaCentaur.Search.SearchResult

  @doc """
  Best-effort infohash for a search result: the `info_hash` field if
  usable, else parsed from `magnet_url`, else `nil`.
  """
  @spec from_search_result(SearchResult.t()) :: String.t() | nil
  def from_search_result(%SearchResult{info_hash: info_hash, magnet_url: magnet_url}) do
    normalize(info_hash) || from_magnet(magnet_url)
  end

  @doc "Extracts and normalizes the `xt=urn:btih:` infohash from a magnet URI."
  @spec from_magnet(String.t() | nil) :: String.t() | nil
  def from_magnet(magnet) when is_binary(magnet) do
    case Regex.run(~r/xt=urn:btih:([^&]+)/i, magnet) do
      [_, hash] -> hash |> URI.decode() |> normalize()
      _ -> nil
    end
  end

  def from_magnet(_), do: nil

  @doc """
  Normalizes an infohash string to lowercase 40-char hex, or `nil` when
  it is neither hex nor base32 of the right length.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      hex40?(trimmed) -> String.downcase(trimmed)
      base32_32?(trimmed) -> decode_base32(trimmed)
      true -> nil
    end
  end

  def normalize(_), do: nil

  defp hex40?(string), do: Regex.match?(~r/\A[0-9a-fA-F]{40}\z/, string)
  defp base32_32?(string), do: Regex.match?(~r/\A[A-Za-z2-7]{32}\z/, string)

  defp decode_base32(string) do
    case Base.decode32(String.upcase(string), padding: false) do
      {:ok, bytes} -> Base.encode16(bytes, case: :lower)
      :error -> nil
    end
  end
end
