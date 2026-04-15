defmodule MediaCentaur.Acquisition.Quality do
  @moduledoc """
  Parses and ranks media release quality from torrent/usenet release title strings.

  Quality tiers:
  - `:uhd_4k` — 2160p, 4K, or UHD markers (preferred)
  - `:hd_1080p` — 1080p markers (acceptable)
  - `nil` — unknown or below-threshold quality (filtered out in automated grabs)

  Manual search shows all results regardless of quality; automated grabs only
  proceed when `acceptable?/1` returns true.
  """

  @type t :: :uhd_4k | :hd_1080p | nil

  @doc "Parses a quality tier from a release title string."
  @spec parse(String.t()) :: t()
  def parse(title) do
    downcased = String.downcase(title)

    cond do
      uhd_4k?(downcased) -> :uhd_4k
      hd_1080p?(downcased) -> :hd_1080p
      true -> nil
    end
  end

  @doc "Returns a numeric rank for sorting. Higher is better."
  @spec rank(t()) :: non_neg_integer()
  def rank(:uhd_4k), do: 2
  def rank(:hd_1080p), do: 1
  def rank(nil), do: 0

  @doc "Returns true when the quality meets the minimum threshold for automated grabs."
  @spec acceptable?(t()) :: boolean()
  def acceptable?(:uhd_4k), do: true
  def acceptable?(:hd_1080p), do: true
  def acceptable?(nil), do: false

  @doc "Returns a short human-readable label."
  @spec label(t()) :: String.t()
  def label(:uhd_4k), do: "4K"
  def label(:hd_1080p), do: "1080p"
  def label(nil), do: "Unknown"

  defp uhd_4k?(downcased) do
    String.contains?(downcased, "2160p") or
      String.contains?(downcased, "4k") or
      String.contains?(downcased, " uhd") or
      String.contains?(downcased, ".uhd") or
      String.contains?(downcased, "-uhd")
  end

  defp hd_1080p?(downcased) do
    String.contains?(downcased, "1080p")
  end
end
