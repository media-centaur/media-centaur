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
  2. The `xt=urn:btih:` parameter of the `magnet_url` or `guid`.
  3. The release's `download_url` (via `resolve/2`): either a redirect to a
     magnet, or a served `.torrent` body whose `info` dict is hashed.

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
  Best-effort infohash for a search result, **without network access**: the
  `info_hash` field if usable, else parsed from `magnet_url`, else from `guid`
  (some indexers put a magnet URI in the guid), else `nil`.
  """
  @spec from_search_result(SearchResult.t()) :: String.t() | nil
  def from_search_result(%SearchResult{info_hash: info_hash, magnet_url: magnet_url, guid: guid}) do
    normalize(info_hash) || from_magnet(magnet_url) || from_magnet(guid)
  end

  @typedoc """
  Fetches a release's `download_url`. Returns `{:magnet, uri}` when the URL
  redirects to a magnet, `{:torrent, bytes}` when it serves a `.torrent` body,
  or `:error`. Injected in tests so resolution stays offline.
  """
  @type fetcher :: (String.t() -> {:magnet, String.t()} | {:torrent, binary()} | :error)

  @doc """
  Resolves a durable infohash for a search result, escalating to the network
  only when needed.

  Tries the synchronous `from_search_result/1` first. If that yields nothing and
  the result carries a `download_url`, fetches it via `fetcher` and derives the
  hash from either a magnet redirect or the returned `.torrent` body. Returns
  lowercase 40-char hex, or `nil` (the caller then falls back to title or
  content_path correlation — no regression).
  """
  @spec resolve(SearchResult.t(), fetcher()) :: String.t() | nil
  def resolve(%SearchResult{} = result, fetcher \\ &fetch/1) do
    from_search_result(result) || resolve_via_download(result, fetcher)
  end

  defp resolve_via_download(%SearchResult{download_url: url}, fetcher) when is_binary(url) do
    case fetcher.(url) do
      {:magnet, magnet} -> from_magnet(magnet)
      {:torrent, bytes} -> from_torrent(bytes)
      _ -> nil
    end
  end

  defp resolve_via_download(_result, _fetcher), do: nil

  defp fetch(url) do
    case Req.get(url, redirect: false, decode_body: false, receive_timeout: 15_000) do
      {:ok, %{status: status} = resp} when status in 300..399 ->
        resp
        |> Req.Response.get_header("location")
        |> List.first()
        |> case do
          "magnet:" <> _ = magnet -> {:magnet, magnet}
          _ -> :error
        end

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:torrent, body}

      _ ->
        :error
    end
  rescue
    _ -> :error
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
  Computes the v1 infohash from raw `.torrent` bytes — `SHA1` of the **exact
  original byte span** of the bencoded `info` dictionary (never a re-encode,
  which can reorder dict keys and change the hash). Returns lowercase 40-char
  hex, or `nil` when the bytes are not a bencoded dict or carry no `info` key.
  """
  @spec from_torrent(binary() | nil) :: String.t() | nil
  def from_torrent(bin) when is_binary(bin) do
    case info_span(bin) do
      {start, stop} ->
        :sha
        |> :crypto.hash(:binary.part(bin, start, stop - start))
        |> Base.encode16(case: :lower)

      :not_found ->
        nil
    end
  rescue
    _ -> nil
  end

  def from_torrent(_), do: nil

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

  # --- bencode info-dict span scanner (used by from_torrent/1) ---------------

  defp info_span(bin) do
    if byte_size(bin) > 0 and :binary.at(bin, 0) == ?d, do: walk(bin, 1), else: :not_found
  end

  defp walk(bin, i) do
    if :binary.at(bin, i) == ?e do
      :not_found
    else
      {len, colon} = read_len(bin, i, 0)
      key = :binary.part(bin, colon + 1, len)
      value_start = colon + 1 + len
      value_stop = endof(bin, value_start)
      if key == "info", do: {value_start, value_stop}, else: walk(bin, value_stop)
    end
  end

  defp endof(bin, i) do
    case :binary.at(bin, i) do
      ?i ->
        find_byte(bin, i + 1, ?e) + 1

      container when container == ?l or container == ?d ->
        skip_container(bin, i + 1)

      digit when digit >= ?0 and digit <= ?9 ->
        {len, colon} = read_len(bin, i, 0)
        colon + 1 + len
    end
  end

  defp skip_container(bin, i) do
    if :binary.at(bin, i) == ?e, do: i + 1, else: skip_container(bin, endof(bin, i))
  end

  defp read_len(bin, i, acc) do
    case :binary.at(bin, i) do
      ?: -> {acc, i}
      digit -> read_len(bin, i + 1, acc * 10 + (digit - ?0))
    end
  end

  defp find_byte(bin, i, ch) do
    if :binary.at(bin, i) == ch, do: i, else: find_byte(bin, i + 1, ch)
  end
end
